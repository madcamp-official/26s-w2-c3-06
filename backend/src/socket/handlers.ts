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
      });
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
    });
    io.to(room.roomCode).emit('room:playerListUpdated', { players: room.players });
    broadcastChat(io, room, 'system', 'system', `${payload.nickname}님이 입장했습니다.`);
    upsertUser({ uid, nickname: payload.nickname, isAnonymous }).catch((err) =>
      console.error('[handlers] upsertUser 실패', err),
    );
  });

  socket.on('room:leave', () => {
    handleLeave();
  });

  socket.on('disconnect', () => {
    handleLeave();
  });

  function handleLeave() {
    const room = currentRoom();
    const player = room?.players.find((p) => p.id === uid);
    const result = roomManager.leaveRoom(socket.id);
    if (!result) return;
    socket.leave(result.room.roomCode);
    if (result.roomClosed) {
      io.to(result.room.roomCode).emit('room:closed');
      return;
    }
    io.to(result.room.roomCode).emit('room:playerListUpdated', { players: result.room.players });
    if (player) {
      broadcastChat(io, result.room, 'system', 'system', `${player.nickname}님이 퇴장했습니다.`);
    }
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
