// PLAN "데이터 모델 (인메모리)" 참고. 방/게임/라운드는 서버 메모리에만 존재.

export interface Player {
  id: string;
  nickname: string;
  isBot: boolean;
  connected: boolean;
  isReady: boolean; // 대기방 준비 상태. 봇은 참여 즉시 true로 고정
}

// 한 게임 안의 "설명 한 바퀴". 설명 순서(playerOrder)는 게임 단위로 고정이고 투표는
// 게임당 한 번뿐이므로, 순서·투표·판정 결과는 여기가 아니라 GameState에 둔다.
// 라운드는 그 바퀴에 제출된 설명(turns)만 담는다.
export interface Round {
  roundNumber: number;
  turns: { playerId: string; text: string }[];
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
  playerOrder: string[]; // 설명 순서. 게임 단위로 한 번 정해 모든 라운드에서 고정 사용
  usedWordsThisGame: string[];
  rounds: Round[]; // 설명 라운드들. MVP: 길이 1

  // 투표·판정은 게임 단위. 라운드가 아니라 게임에 귀속된다(동점 재투표 시 rounds가 늘어도
  // votes는 "이번 투표" 한 번만의 집계 — 재투표 시작 시 초기화됨).
  votes: Record<string, string>; // 서버 전용, 클라이언트로 절대 전송 안 함

  // null이면 아직 동점이 발생하지 않은 일반 진행(최초 설명은 전원, 최초 투표는 전원 대상).
  // 배열이면 직전 투표에서 동점이 된 플레이어 id 목록 — 이 목록이 동시에 "지금 재설명
  // 라운드의 발화 순서 대상"이자 "다음 재투표의 유효 후보 목록"이다(둘이 항상 같은 집합).
  tieCandidates: string[] | null;
  votedOutId?: string;
  wasLiar?: boolean;
  liarGuess?: string;
  liarGuessCorrect?: boolean;
  winner?: 'liar' | 'citizens';
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

// 방장이 대기방에서 만지고 있는 다음 게임 설정(아직 시작 전). game:configure와 같은 모양 —
// 다른 참가자 화면에 실시간으로 보여주기 위해 방 상태에 들고 있는다.
export interface DraftGameConfig {
  category: string | null; // null이면 AI 랜덤 생성
  aiBotCount: number;
}

export interface RoomState {
  roomCode: string; // 4자리 숫자 문자열, 예: "4821"
  hostId: string;
  title: string; // 방 제목. 방 생성 시 지정(미지정 시 "{방장}의 방")
  emoji: string; // 로비 목록에 표시되는 방 이모지. 방 생성 시 지정(미지정 시 기본 이모지)
  visibility: 'public' | 'private';
  maxPlayers: number; // 방장이 방 생성 시 지정, 시스템상 상한 없음(사람+봇 합산 기준)
  players: Player[];
  customCategories: string[]; // 방장이 이 방에서 직접 추가한 카테고리 이름. 방 종료(소멸) 시 함께 사라짐
  draftConfig: DraftGameConfig; // 방장이 게임 시작 전 고르고 있는 봇 수/카테고리 (실시간 공유용)
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
