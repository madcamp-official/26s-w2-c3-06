// PLAN "데이터 모델 (인메모리)" 참고. 방/게임/라운드는 서버 메모리에만 존재.

export interface Player {
  id: string;
  nickname: string;
  isBot: boolean;
  isHost: boolean;
  connected: boolean;
}

export interface Round {
  roundNumber: number;
  playerOrder: string[];
  turns: { playerId: string; text: string }[];
  votes: Record<string, string>; // 서버 전용, 클라이언트로 절대 전송 안 함
  votedOutId?: string;
  wasLiar?: boolean;
  liarGuess?: string;
  liarGuessCorrect?: boolean;
  winner?: 'liar' | 'citizens';
}

export type GamePhase =
  | 'setup'
  | 'describing'
  | 'discussion'
  | 'voting'
  | 'resolution'
  | 'liarGuess'
  | 'ended';

export interface GameState {
  gameNumber: number;
  category: string;
  realWord: string;
  liarWord: string;
  liarIds: string[]; // 서버 전용 비밀. MVP: 길이 1 고정. 추후 라이어 수 선택 시 증가
  participantIds: string[]; // 방 플레이어 + 이번 게임에 호스트가 추가한 봇
  aiBotCount: number;
  phase: GamePhase;
  usedWordsThisGame: string[];
  rounds: Round[]; // MVP: 길이 1
}

export type ChatSenderKind = string | 'ai' | 'system';
export type ChatMessageType = 'chat' | 'turnDescription' | 'aiComment' | 'system';

export interface ChatMessage {
  id: string;
  senderId: ChatSenderKind;
  type: ChatMessageType;
  text: string;
  timestamp: number;
}

export interface RoomState {
  roomCode: string; // 4자리 숫자 문자열, 예: "4821"
  hostId: string;
  visibility: 'public' | 'private';
  players: Player[];
  chatLog: ChatMessage[]; // 방 존재 동안 유지, 새 게임 시작 시에만 초기화
  currentGame: GameState | null;
  gameHistory: GameState[];
  createdAt: number;
}

// ── LLM 래퍼 컨텍스트 (PLAN "LLM 래퍼" 참고) ──

export interface BotTurnContext {
  category: string;
  assignedWord: string; // 봇에게 배정된 단어 (진짜/가짜 여부·라이어 여부는 알려주지 않음)
  priorTurns: { nickname: string; text: string }[];
}

export interface TurnCommentContext {
  category: string;
  latestDescription: string; // 방금 제출된 설명 (실제 라이어 정체는 절대 포함하지 않음)
  priorTurns: { nickname: string; text: string }[];
}
