import type {
  ChatMessage,
  ChatMessageType,
  ChatSenderKind,
  DraftGameConfig,
  Player,
  RoomState,
} from '../types';

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

// disconnect(새로고침·순단 등) 시 곧바로 퇴장 처리하지 않고, 유예 시간 동안 room:rejoin을
// 기다린다. 그 사이 재접속하면 cancelRemoval로 취소되고, 만료되면 진짜 퇴장 처리된다.
const REJOIN_GRACE_PERIOD_MS = 30_000;
const pendingRemovals = new Map<string, NodeJS.Timeout>();

function pendingRemovalKey(roomCode: string, uid: string): string {
  return `${roomCode}:${uid}`;
}

export function scheduleRemoval(roomCode: string, uid: string, onExpire: () => void): void {
  cancelRemoval(roomCode, uid);
  const timer = setTimeout(() => {
    pendingRemovals.delete(pendingRemovalKey(roomCode, uid));
    onExpire();
  }, REJOIN_GRACE_PERIOD_MS);
  pendingRemovals.set(pendingRemovalKey(roomCode, uid), timer);
}

export function cancelRemoval(roomCode: string, uid: string): void {
  const key = pendingRemovalKey(roomCode, uid);
  const timer = pendingRemovals.get(key);
  if (timer) {
    clearTimeout(timer);
    pendingRemovals.delete(key);
  }
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

// 로비 공개방 목록. PLAN 계약대로 { roomCode, playerCount, maxPlayers }를 노출.
export function listPublicRooms(): { roomCode: string; playerCount: number; maxPlayers: number }[] {
  return [...rooms.values()]
    .filter((r) => r.visibility === 'public')
    .map((r) => ({ roomCode: r.roomCode, playerCount: r.players.length, maxPlayers: r.maxPlayers }));
}

export function createRoom(opts: {
  socketId: string;
  uid: string;
  nickname: string;
  visibility: 'public' | 'private';
  maxPlayers: number;
}): RoomState {
  const roomCode = generateRoomCode();
  const host: Player = {
    id: opts.uid,
    nickname: opts.nickname,
    isBot: false,
    isHost: true,
    connected: true,
    isReady: false,
  };
  const room: RoomState = {
    roomCode,
    hostId: opts.uid,
    visibility: opts.visibility,
    maxPlayers: opts.maxPlayers,
    players: [host],
    customCategories: [],
    draftConfig: { category: null, aiBotCount: 0 },
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
  if (room.players.length >= room.maxPlayers) {
    return { error: '방 인원이 가득 찼습니다.' };
  }

  const player: Player = {
    id: opts.uid,
    nickname: opts.nickname,
    isBot: false,
    isHost: false,
    connected: true,
    isReady: false,
  };
  room.players.push(player);
  socketIndex.set(opts.socketId, { roomCode: opts.roomCode, uid: opts.uid });
  uidSocketIndex.set(opts.uid, opts.socketId);
  return room;
}

// 대기방 준비 상태 토글. 게임 중이거나 대상 플레이어가 없으면 조용히 무시.
export function setPlayerReady(room: RoomState, uid: string, isReady: boolean): void {
  const player = room.players.find((p) => p.id === uid);
  if (!player) return;
  player.isReady = isReady;
}

// 방장이 대기방에서 봇 수/카테고리를 만지작거릴 때마다 호출 — 다른 참가자 화면에도
// 실시간으로 보여주기 위해 방 상태에 반영한다(아직 game:configure를 보낸 건 아님).
export function setDraftConfig(room: RoomState, config: DraftGameConfig): void {
  room.draftConfig = config;
}

// 방장이 프리셋에 없는 카테고리를 자유 입력하면 이 방의 재사용 목록에 추가한다(중복 방지).
export function addCustomCategory(room: RoomState, category: string): void {
  if (!room.customCategories.includes(category)) {
    room.customCategories.push(category);
  }
}

// 방장이 나가면(퇴장/유예 만료) 승계하지 않고 방 자체를 닫는다.
function removePlayerFromRoom(
  room: RoomState,
  uid: string,
): { room: RoomState; roomClosed: boolean } {
  const wasHost = room.hostId === uid;
  room.players = room.players.filter((p) => p.id !== uid);

  if (wasHost || room.players.length === 0) {
    rooms.delete(room.roomCode);
    return { room, roomClosed: true };
  }

  return { room, roomClosed: false };
}

// 명시적 방 나가기(room:leave). 즉시 퇴장 처리 — 방장이 나가면 방을 닫고,
// 방장이 아니면 남은 인원으로 계속 유지한다(마지막 인원이 나가도 방을 닫음).
export function leaveRoom(
  socketId: string,
): { room: RoomState; roomClosed: boolean } | undefined {
  const binding = socketIndex.get(socketId);
  if (!binding) return undefined;
  socketIndex.delete(socketId);
  if (uidSocketIndex.get(binding.uid) === socketId) {
    uidSocketIndex.delete(binding.uid);
  }
  cancelRemoval(binding.roomCode, binding.uid);

  const room = rooms.get(binding.roomCode);
  if (!room) return undefined;

  return removePlayerFromRoom(room, binding.uid);
}

// disconnect 유예 시간이 만료됐을 때 실제로 퇴장 처리한다(socketIndex는 markDisconnected
// 시점에 이미 정리되어 있으므로 uid 기준으로 방에서만 제거).
export function removePlayerByUid(
  roomCode: string,
  uid: string,
): { room: RoomState; roomClosed: boolean } | undefined {
  const room = rooms.get(roomCode);
  if (!room) return undefined;
  return removePlayerFromRoom(room, uid);
}

// disconnect(새로고침·순단 등) 시 호출. 방에서 제거하지 않고 connected=false만 표시하며,
// 소켓 인덱스만 정리한다(호출부에서 scheduleRemoval로 유예 타이머를 걸어야 함).
export function markDisconnected(
  socketId: string,
): { roomCode: string; uid: string } | undefined {
  const binding = socketIndex.get(socketId);
  if (!binding) return undefined;
  socketIndex.delete(socketId);
  if (uidSocketIndex.get(binding.uid) === socketId) {
    uidSocketIndex.delete(binding.uid);
  }

  const room = rooms.get(binding.roomCode);
  const player = room?.players.find((p) => p.id === binding.uid);
  if (player) {
    player.connected = false;
  }
  return { roomCode: binding.roomCode, uid: binding.uid };
}

// room:rejoin. 유예 시간 내에 재접속한 플레이어를 같은 방/같은 uid로 복귀시킨다.
export function rejoin(opts: {
  socketId: string;
  uid: string;
  roomCode: string;
}): RoomState | JoinError {
  const room = rooms.get(opts.roomCode);
  if (!room) return { error: '존재하지 않는 방 코드입니다.' };
  const player = room.players.find((p) => p.id === opts.uid);
  if (!player) return { error: '이 방에 참가한 기록이 없습니다.' };

  player.connected = true;
  socketIndex.set(opts.socketId, { roomCode: opts.roomCode, uid: opts.uid });
  uidSocketIndex.set(opts.uid, opts.socketId);
  cancelRemoval(opts.roomCode, opts.uid);
  return room;
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
