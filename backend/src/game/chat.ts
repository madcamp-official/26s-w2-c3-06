import type { Server } from 'socket.io';
import type { ChatMessageType, ChatSenderKind, RoomState } from '../types';
import { appendChatMessage } from './roomManager';

// PLAN "통합 채팅 피드": 자유 채팅·턴 설명·AI 교란 코멘트·시스템 안내 모두 이 한 경로로 나간다.
export function broadcastChat(
  io: Server,
  room: RoomState,
  senderId: ChatSenderKind,
  type: ChatMessageType,
  text: string,
) {
  const message = appendChatMessage(room, senderId, type, text);
  io.to(room.roomCode).emit('chat:message', message);
  return message;
}
