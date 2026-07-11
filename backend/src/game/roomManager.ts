import type { RoomState } from '../types';

// 인메모리 방 상태 저장소. PLAN "데이터 모델" · "저장소 구조" 참고.
// 방/게임/라운드 같은 휘발성 상태는 이 프로세스 메모리에만 둔다.
const rooms = new Map<string, RoomState>();

// 4자리 숫자 코드 발급 (충돌 시 재생성).
export function generateRoomCode(): string {
  let code: string;
  do {
    code = String(Math.floor(1000 + Math.random() * 9000));
  } while (rooms.has(code));
  return code;
}

export function getRoom(roomCode: string): RoomState | undefined {
  return rooms.get(roomCode);
}

// 로비 공개방 목록. PLAN 계약대로 { roomCode, playerCount }만 노출.
export function listPublicRooms(): { roomCode: string; playerCount: number }[] {
  return [...rooms.values()]
    .filter((r) => r.visibility === 'public')
    .map((r) => ({ roomCode: r.roomCode, playerCount: r.players.length }));
}

// TODO: createRoom / joinRoom / leaveRoom / removeRoom 구현
