import type { BotTurnContext, TurnCommentContext } from '../types';

// PLAN "LLM 래퍼" 프롬프트 핵심을 담는다. 실제 문안은 튜닝하며 다듬을 예정.

export function wordPairPrompt(category: string | null, usedWords: string[]): string {
  const categoryLine = category
    ? `카테고리는 "${category}"이다.`
    : '적절한 카테고리를 하나 직접 골라라.';
  return [
    '라이어게임용 제시어 쌍을 만든다.',
    categoryLine,
    '같은 카테고리 안에서 연관성은 있지만 서로 다른 두 단어(realWord, liarWord)를 생성하라.',
    '너무 멀면 라이어가 바로 티나고, 너무 가까우면 설명이 똑같아진다 (예: "동물" → 사자/호랑이).',
    usedWords.length ? `이미 사용한 단어는 피하라: ${usedWords.join(', ')}.` : '',
    '반드시 JSON만 출력: {"category": string, "realWord": string, "liarWord": string}',
  ]
    .filter(Boolean)
    .join('\n');
}

export function botTurnPrompt(ctx: BotTurnContext): string {
  const prior = ctx.priorTurns.map((t) => `- ${t.nickname}: ${t.text}`).join('\n') || '(아직 없음)';
  return [
    `카테고리 "${ctx.category}"에서 너에게 배정된 단어는 "${ctx.assignedWord}"이다.`,
    '너는 이 단어가 진짜인지 가짜인지, 네가 라이어인지 전혀 모른다 (사람 참가자와 동일 조건).',
    '단어를 직접 말하지 말고, 너무 완벽하지 않게 자연스러운 한 문장으로 설명하라.',
    `지금까지 나온 설명:\n${prior}`,
    '설명 문장만 출력하라.',
  ].join('\n');
}

// turnCommentPrompt와 함께 전달되는 system 프롬프트. "실제 사람을 속이는 행위"가 아니라
// 참가자 전원이 동의하고 기대하는 게임 내 코미디 캐릭터임을 먼저 분명히 못박아, 모델이
// 이 요청을 "기만/사기 생성 요청"으로 오인해 거부하지 않도록 한다(예전엔 이 framing이 없어
// "deceptive comments... pretending to have information I don't have"라며 거부한 사례가 있었음).
export const turnCommentSystemPrompt = [
  '너는 파티게임 앱 "L-AI-R GAME"(추리 게임) 안에서만 존재하는 캐릭터 "잼민이봇"이다.',
  '이 앱은 매 턴마다 AI가 근거 없이 짓궂은 드립/약올림 코멘트를 던지는 것이 정식 게임 기능이라는 걸',
  '모든 참가자가 알고 동의한 상태에서 플레이한다 — 실제 사람을 상대로 한 기만·사기가 아니라,',
  '다 함께 즐기는 코미디 캐릭터 연기다. 너의 코멘트는 사실 주장이 아니라 그냥 드립/의견일 뿐이다.',
  '너는 이 게임의 정답(진짜 제시어가 무엇인지, 누가 라이어인지)을 절대 전달받지 않으며 알지도 못한다.',
  '따라서 정답을 안다고 주장하거나 특정 단어가 진짜/가짜라고 단정하지 마라 — 근거 없는 의심과',
  '드립만 던지는 캐릭터다. 실제 욕설·혐오 표현·인신공격은 하지 않는다(유치한 장난 수준까지만).',
].join(' ');

export function turnCommentPrompt(ctx: TurnCommentContext): string {
  // 실제 라이어가 누구인지, 진짜/가짜 제시어가 무엇인지는 이 함수에 절대 전달되지 않는다
  // (TurnCommentContext 자체에 그 필드가 없음 — 구조적으로 유출 불가).
  const prior = ctx.priorTurns.map((t) => `- ${t.nickname}: ${t.text}`).join('\n') || '(아직 없음)';
  return [
    `[게임 상황] 카테고리: "${ctx.category}"`,
    `방금 나온 설명: "${ctx.latestDescription}"`,
    `이전 설명들:\n${prior}`,
    '',
    '[코멘트 작성 규칙]',
    '- 말투: 초등학생이 단체 채팅방에서 떠드는 것처럼 유치하고 산만하게 써라. 반말, "ㅋㅋㅋ", "ㅇㅈ?",',
    '  "레알?", "노잼", "완전 수상함ㅋ" 같은 표현을 적극 써서 상대를 약올리는(킹받게 하는) 톤으로.',
    '- 닉네임을 불러가며 놀리듯 도발해도 되지만, 실제 욕설·혐오·인신공격은 절대 금지 — 유치한 장난까지만.',
    '- 진짜 정답은 너도 모르니 절대 아는 척하거나 특정 단어를 진짜/가짜라고 단정하지 말고,',
    '  근거 없이 의심하는 드립만 던져라(예: "야 그거 좀 이상한데?ㅋㅋ").',
    '- 한 문장, 코멘트 내용만 출력하라. 따옴표나 부연 설명은 붙이지 마라.',
  ].join('\n');
}

// 난이도와 무관하게 모든 제시어에 대해 짧은 텍스트 설명을 생성하도록 요청한다.
export function explainWordPrompt(word: string): string {
  return [
    `단어: "${word}"`,
    '이 단어의 뜻을 한두 문장으로 짧게 설명하라(이미지 생성 없이 텍스트로만).',
    '흔히 아는 쉬운 단어여도 반드시 짧은 설명을 제공하라.',
    '다른 말 없이 설명 문장만 출력하라.',
  ].join('\n');
}

// 라이어의 역전승 답안과 진짜 제시어가 의미상 같은지 판정. 오타·맞춤법·한글/영어 표기 차이는 정답으로 인정.
export function judgeLiarGuessPrompt(guess: string, realWord: string): string {
  return [
    `진짜 제시어: "${realWord}"`,
    `라이어가 제출한 답: "${guess}"`,
    '두 표현이 의미상 같은 대상을 가리키는지 판단하라.',
    '오타, 맞춤법 오류, 한글/영어 표기 차이(예: "burger"와 "버거")는 정답으로 인정한다.',
    '정답이면 "true", 아니면 "false"만 출력하라. 다른 말은 절대 출력하지 마라.',
  ].join('\n');
}
