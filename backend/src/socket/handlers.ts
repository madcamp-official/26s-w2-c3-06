import type { Server, Socket } from 'socket.io';
import * as roomManager from '../game/roomManager';
import * as gameEngine from '../game/gameEngine';
import { broadcastChat } from '../game/chat';
import { upsertUser } from '../db/userRepo';

// PLAN "Socket.IO 이벤트 계약 (MVP)" 참고. 각 이벤트를 roomManager/gameEngine으로 위임한다.
export function registerSocketHandlers(io: Server, socket: Socket): void {
  const uid = socket.data.uid as string;
  const isAnonymous = Boolean(socket.data.isAnonymous);

  function currentRoom() {
    return roomManager.getRoomBySocket(socket.id);
  }

  // 로비 화면이 실시간으로 갱신되도록, 공개방 목록에 영향을 주는 변화(생성/입장/퇴장/폭파)가
  // 있을 때마다 모든 연결된 소켓에 최신 목록을 브로드캐스트한다. 비공개방 변화는 목록에
  // 어차피 안 잡히니 불필요한 브로드캐스트를 피하려 visibility가 public일 때만 보낸다.
  function broadcastPublicRoomsIfPublic(visibility: 'public' | 'private'): void {
    if (visibility !== 'public') return;
    io.emit('room:publicList', { rooms: roomManager.listPublicRooms() });
  }

  // ── 방(Room) ──

  socket.on(
    'room:create',
    (payload: { nickname: string; visibility: 'public' | 'private'; maxPlayers: number }) => {
      const room = roomManager.createRoom({
        socketId: socket.id,
        uid,
        nickname: payload.nickname,
        visibility: payload.visibility,
        maxPlayers: payload.maxPlayers,
      });
      socket.join(room.roomCode);
      socket.emit('room:created', {
        roomCode: room.roomCode,
        hostId: room.hostId,
        visibility: room.visibility,
        players: room.players,
        draftConfig: room.draftConfig,
      });
      broadcastPublicRoomsIfPublic(room.visibility);
      upsertUser({ uid, nickname: payload.nickname, isAnonymous }).catch((err) =>
        console.error('[handlers] upsertUser 실패', err),
      );
    },
  );

  socket.on('room:listPublic', () => {
    socket.emit('room:publicList', { rooms: roomManager.listPublicRooms() });
  });

  socket.on('room:join', async (payload: { roomCode: string; nickname: string }) => {
    const result = roomManager.joinRoom({
      socketId: socket.id,
      uid,
      nickname: payload.nickname,
      roomCode: payload.roomCode,
    });
    if (roomManager.isJoinError(result)) {
      socket.emit('room:error', { message: result.error });
      return;
    }
    const room = result;
    socket.join(room.roomCode);
    socket.emit('room:joined', {
      roomCode: room.roomCode,
      hostId: room.hostId,
      visibility: room.visibility,
      players: room.players,
      draftConfig: room.draftConfig,
    });
    io.to(room.roomCode).emit('room:playerListUpdated', { players: room.players });
    broadcastPublicRoomsIfPublic(room.visibility);
    broadcastChat(io, room, 'system', 'system', `${payload.nickname}님이 입장했습니다.`);
    upsertUser({ uid, nickname: payload.nickname, isAnonymous }).catch((err) =>
      console.error('[handlers] upsertUser 실패', err),
    );
  });

  socket.on('room:leave', () => {
    handleExplicitLeave();
  });

  socket.on('disconnect', () => {
    handleDisconnect();
  });

  socket.on('room:rejoin', (payload: { roomCode: string }) => {
    const result = roomManager.rejoin({ socketId: socket.id, uid, roomCode: payload.roomCode });
    if (roomManager.isJoinError(result)) {
      socket.emit('room:error', { message: result.error });
      return;
    }
    const room = result;
    socket.join(room.roomCode);
    socket.emit('room:rejoined', {
      roomCode: room.roomCode,
      hostId: room.hostId,
      visibility: room.visibility,
      players: room.players,
      chatLog: room.chatLog,
      currentGame: room.currentGame ? gameEngine.toPublicGameState(room, room.currentGame) : null,
      draftConfig: room.draftConfig,
    });
    io.to(room.roomCode).emit('room:playerListUpdated', { players: room.players });
    gameEngine.resendYourWord(io, room, uid);
    gameEngine.resendLiarGuessPromptIfPending(io, room, uid);
  });

  // 명시적 나가기 — 즉시 퇴장 처리(방장이 나가면 방 폭파, 아니면 남은 인원 유지).
  function handleExplicitLeave() {
    const room = currentRoom();
    const player = room?.players.find((p) => p.id === uid);
    const result = roomManager.leaveRoom(socket.id);
    if (!result) return;
    socket.leave(result.room.roomCode);
    if (result.roomClosed) {
      io.to(result.room.roomCode).emit('room:closed');
      broadcastPublicRoomsIfPublic(result.room.visibility);
      return;
    }
    io.to(result.room.roomCode).emit('room:playerListUpdated', { players: result.room.players });
    broadcastPublicRoomsIfPublic(result.room.visibility);
    if (player) {
      broadcastChat(io, result.room, 'system', 'system', `${player.nickname}님이 퇴장했습니다.`);
    }
  }

  // 원인 불명의 연결 끊김(새로고침 포함) — 곧바로 퇴장시키지 않고 유예 시간을 준다.
  // 그 사이 room:rejoin이 오면 복귀, 만료되면 그때 진짜 퇴장 처리(방장이면 방 폭파).
  function handleDisconnect() {
    const room = currentRoom();
    const player = room?.players.find((p) => p.id === uid);
    const result = roomManager.markDisconnected(socket.id);
    if (!result) return;
    const { roomCode } = result;
    if (room) {
      io.to(roomCode).emit('room:playerListUpdated', { players: room.players });
    }
    roomManager.scheduleRemoval(roomCode, uid, () => {
      const removal = roomManager.removePlayerByUid(roomCode, uid);
      if (!removal) return;
      if (removal.roomClosed) {
        io.to(roomCode).emit('room:closed');
        broadcastPublicRoomsIfPublic(removal.room.visibility);
        return;
      }
      io.to(roomCode).emit('room:playerListUpdated', { players: removal.room.players });
      broadcastPublicRoomsIfPublic(removal.room.visibility);
      if (player) {
        broadcastChat(io, removal.room, 'system', 'system', `${player.nickname}님이 퇴장했습니다.`);
      }
    });
  }

  // ── 채팅 (언제든 자유 채팅) ──

  socket.on('chat:send', (payload: { text: string }) => {
    const room = currentRoom();
    if (!room || !payload.text?.trim()) return;
    broadcastChat(io, room, uid, 'chat', payload.text.trim());
  });

  // ── 대기방 준비 상태 ──

  socket.on('player:ready', (payload: { isReady: boolean }) => {
    const room = currentRoom();
    if (!room) return;
    roomManager.setPlayerReady(room, uid, Boolean(payload.isReady));
    io.to(room.roomCode).emit('room:playerListUpdated', { players: room.players });
  });

  // 방장이 대기방에서 봇 수/카테고리를 만지작거릴 때마다(아직 시작 전) 다른 참가자
  // 화면에도 실시간으로 보이도록 방 상태에 반영하고 브로드캐스트한다.
  socket.on('game:draftConfig', (payload: { category: string | null; aiBotCount: number }) => {
    const room = currentRoom();
    if (!room) return;
    if (!roomManager.isHost(room, uid)) return;
    const config = { category: payload.category, aiBotCount: Number(payload.aiBotCount) || 0 };
    roomManager.setDraftConfig(room, config);
    io.to(room.roomCode).emit('game:draftConfigUpdated', config);
  });

  // ── 게임 진행 ──

  const MIN_PARTICIPANTS = 3;

  socket.on('game:configure', async (payload: { category: string | null; aiBotCount: number }) => {
    const room = currentRoom();
    if (!room) return;
    if (!roomManager.isHost(room, uid)) {
      socket.emit('room:error', { message: '호스트만 게임을 시작할 수 있습니다.' });
      return;
    }
    if (room.currentGame && room.currentGame.phase !== 'ended') {
      socket.emit('room:error', { message: '이미 게임이 진행 중입니다.' });
      return;
    }
    if (!room.players.every((p) => p.isReady)) {
      socket.emit('room:error', { message: '모든 참가자가 준비 완료 상태여야 합니다.' });
      return;
    }
    if (room.players.length + payload.aiBotCount < MIN_PARTICIPANTS) {
      socket.emit('room:error', { message: `참가자(사람+봇)가 최소 ${MIN_PARTICIPANTS}명 이상이어야 합니다.` });
      return;
    }
    try {
      await gameEngine.startGame(io, room, payload);
      const resetConfig = { category: null, aiBotCount: 0 };
      roomManager.setDraftConfig(room, resetConfig);
      io.to(room.roomCode).emit('game:draftConfigUpdated', resetConfig);
    } catch (err) {
      console.error('[handlers] game:configure 실패', err);
      socket.emit('room:error', { message: '게임 시작에 실패했습니다. 잠시 후 다시 시도해주세요.' });
    }
  });

  socket.on('turn:submitDescription', (payload: { text: string }) => {
    const room = currentRoom();
    if (!room || !payload.text?.trim()) return;
    gameEngine.submitDescription(io, room, uid, payload.text.trim());
  });

  socket.on('vote:cast', (payload: { votedPlayerId: string }) => {
    const room = currentRoom();
    if (!room) return;
    gameEngine.castVote(io, room, uid, payload.votedPlayerId);
  });

  socket.on('liar:guessWord', (payload: { guess: string }) => {
    const room = currentRoom();
    if (!room || !payload.guess?.trim()) return;
    void gameEngine.submitLiarGuess(io, room, uid, payload.guess.trim());
  });
}
