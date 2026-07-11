import type { GameState, RoomState } from '../types';

// 게임/라운드 상태 머신. PLAN "Socket.IO 이벤트 계약"의 페이즈 전이를 서버가 전적으로 소유.
// 대기 → 설정 → 설명 → 토론 → 투표 → 결과 → (역전승 시도) → 게임종료(대기로 복귀)
//
// 스캐폴드 단계: 시그니처만 정의. 실제 전이·타이머·제시어 배정은 추후 구현.

// 새 게임 시작: 제시어 쌍 생성, 라이어 배정(MVP 1명), 봇 추가, 채팅 초기화.
export async function startGame(
  _room: RoomState,
  _opts: { category: string | null; aiBotCount: number },
): Promise<GameState> {
  // TODO: LLM generateWordPair → liarIds 배정 → participantIds 구성 → phase 전이
  throw new Error('not implemented');
}

// 타이머 만료 동작(PLAN): 설명/투표 시간이 지나면 미제출·미투표로 간주하고 다음 페이즈로 진행.
// TODO: submitDescription / castVote / resolveRound / handleLiarGuess
