import type { Server, Socket } from 'socket.io';
import * as roomManager from '../game/roomManager';

// PLAN "Socket.IO 이벤트 계약 (MVP)" 참고.
// 스캐폴드 단계: 각 Client→Server 이벤트의 핸들러 골격만 등록한다.
// 실제 로직은 roomManager / gameEngine으로 위임 예정.
export function registerSocketHandlers(io: Server, socket: Socket): void {
  // ── 방(Room) ──
  socket.on('room:create', (_payload: { nickname: string; visibility: 'public' | 'private' }) => {
    // TODO: roomManager.createRoom → 'room:created' emit
  });

  socket.on('room:listPublic', () => {
    socket.emit('room:publicList', { rooms: roomManager.listPublicRooms() });
  });

  socket.on('room:join', (_payload: { roomCode: string; nickname: string }) => {
    // TODO: roomManager.joinRoom → 'room:joined' / 'room:playerListUpdated'
  });

  socket.on('room:leave', () => {
    // TODO: roomManager.leaveRoom
  });

  // ── 채팅 ──
  socket.on('chat:send', (_payload: { text: string }) => {
    // TODO: 통합 채팅 피드에 append 후 'chat:message' 브로드캐스트
  });

  // ── 게임 진행 ──
  socket.on('game:configure', (_payload: { category: string | null; aiBotCount: number }) => {
    // TODO(호스트 전용): gameEngine.startGame → 'game:started' + 채팅 초기화
  });

  socket.on('turn:submitDescription', (_payload: { text: string }) => {
    // TODO(현재 턴만): 설명 append + LLM 교란 코멘트 생성
  });

  socket.on('vote:cast', (_payload: { votedPlayerId: string }) => {
    // TODO: 서버 내부 집계 (개별 선택은 어떤 클라에도 전송 안 함)
  });

  socket.on('liar:guessWord', (_payload: { guess: string }) => {
    // TODO(지목된 라이어만): 역전승 판정 → 'round:finalResult'
  });
}
