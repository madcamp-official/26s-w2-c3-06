import type { ChatMessage, ChatMessageType, ChatSenderKind, Player, RoomState } from '../types';

// 인메모리 방 상태 저장소. PLAN "데이터 모델" · "저장소 구조" 참고.
// 방/게임/라운드 같은 휘발성 상태는 이 프로세스 메모리에만 둔다.
const rooms = new Map<string, RoomState>();

// socket.id → 현재 어느 방에 어떤 uid로 들어가 있는지 (leave/disconnect 처리에 사용).
interface SocketBinding {
  roomCode: string;
  uid: string;
}
const socketIndex = new Map<string, SocketBinding>();

// uid → 현재 소켓 id. 개별 전송(round:yourWord, liar:guessPrompt)에 사용.
// 같은 uid로 동시에 여러 소켓이 접속하는 경우는 다루지 않는다(최신 소켓만 유지).
const uidSocketIndex = new Map<string, string>();

export function getSocketIdByUid(uid: string): string | undefined {
  return uidSocketIndex.get(uid);
}

export interface JoinError {
  error: string;
}

export function isJoinError(x: RoomState | JoinError): x is JoinError {
  return 'error' in x;
}

// 4자리 숫자 코드 발급 (충돌 시 재생성).
function generateRoomCode(): string {
  let code: string;
  do {
    code = String(Math.floor(1000 + Math.random() * 9000));
  } while (rooms.has(code));
  return code;
}

export function getRoom(roomCode: string): RoomState | undefined {
  return rooms.get(roomCode);
}

export function getRoomBySocket(socketId: string): RoomState | undefined {
  const binding = socketIndex.get(socketId);
  return binding ? rooms.get(binding.roomCode) : undefined;
}

export function getUidBySocket(socketId: string): string | undefined {
  return socketIndex.get(socketId)?.uid;
}

// 로비 공개방 목록. PLAN 계약대로 { roomCode, playerCount }만 노출.
export function listPublicRooms(): { roomCode: string; playerCount: number }[] {
  return [...rooms.values()]
    .filter((r) => r.visibility === 'public')
    .map((r) => ({ roomCode: r.roomCode, playerCount: r.players.length }));
}

export function createRoom(opts: {
  socketId: string;
  uid: string;
  nickname: string;
  visibility: 'public' | 'private';
}): RoomState {
  const roomCode = generateRoomCode();
  const host: Player = {
    id: opts.uid,
    nickname: opts.nickname,
    isBot: false,
    isHost: true,
    connected: true,
  };
  const room: RoomState = {
    roomCode,
    hostId: opts.uid,
    visibility: opts.visibility,
    players: [host],
    chatLog: [],
    currentGame: null,
    gameHistory: [],
    createdAt: Date.now(),
  };
  rooms.set(roomCode, room);
  socketIndex.set(opts.socketId, { roomCode, uid: opts.uid });
  uidSocketIndex.set(opts.uid, opts.socketId);
  return room;
}

export function joinRoom(opts: {
  socketId: string;
  uid: string;
  nickname: string;
  roomCode: string;
}): RoomState | JoinError {
  const room = rooms.get(opts.roomCode);
  if (!room) return { error: '존재하지 않는 방 코드입니다.' };
  if (room.currentGame && room.currentGame.phase !== 'ended') {
    return { error: '이미 게임이 진행 중인 방입니다.' };
  }
  if (room.players.some((p) => p.id === opts.uid)) {
    return { error: '이미 참가 중인 방입니다.' };
  }

  const player: Player = {
    id: opts.uid,
    nickname: opts.nickname,
    isBot: false,
    isHost: false,
    connected: true,
  };
  room.players.push(player);
  socketIndex.set(opts.socketId, { roomCode: opts.roomCode, uid: opts.uid });
  uidSocketIndex.set(opts.uid, opts.socketId);
  return room;
}

// 방 나가기. 방장이 나가면 다음 플레이어에게 방장을 승계하고, 마지막 인원이면 방을 닫는다.
// (재접속/게임 중 이탈 처리는 PLAN TODO의 room:rejoin 스트레치로 미룸 — 남은 참가자로 게임은 계속 진행)
export function leaveRoom(
  socketId: string,
): { room: RoomState; roomClosed: boolean } | undefined {
  const binding = socketIndex.get(socketId);
  if (!binding) return undefined;
  socketIndex.delete(socketId);
  if (uidSocketIndex.get(binding.uid) === socketId) {
    uidSocketIndex.delete(binding.uid);
  }

  const room = rooms.get(binding.roomCode);
  if (!room) return undefined;

  room.players = room.players.filter((p) => p.id !== binding.uid);

  if (room.players.length === 0) {
    rooms.delete(room.roomCode);
    return { room, roomClosed: true };
  }

  if (room.hostId === binding.uid) {
    room.hostId = room.players[0].id;
    room.players[0].isHost = true;
  }
  return { room, roomClosed: false };
}

export function isHost(room: RoomState, uid: string): boolean {
  return room.hostId === uid;
}

export function appendChatMessage(
  room: RoomState,
  senderId: ChatSenderKind,
  type: ChatMessageType,
  text: string,
): ChatMessage {
  const message: ChatMessage = {
    id: `${room.roomCode}-${room.chatLog.length}-${Date.now()}`,
    senderId,
    type,
    text,
    timestamp: Date.now(),
  };
  room.chatLog.push(message);
  return message;
}

// 새 게임 시작 시 채팅 초기화 (PLAN: "새로운 게임이 시작될 때 초기화").
export function resetChatLog(room: RoomState): void {
  room.chatLog = [];
}
