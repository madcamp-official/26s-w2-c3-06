import type { BotTurnContext, TurnCommentContext } from '../types';

// PLAN "LLM 래퍼" 프롬프트 핵심을 담는다. 실제 문안은 튜닝하며 다듬을 예정.

// category가 null일 때(AI 랜덤 카테고리) 후보 3개를 뽑아 코드에서 무작위로 하나를 고른다.
// LLM이 직접 하나를 확정해버리면 같은 프롬프트라도 항상 비슷한(가장 "무난한") 답으로 수렴하는
// 경향이 있어, 후보를 여러 개 받고 실제 무작위 선택은 서버 코드가 해서 다양성을 확보한다.
export function categoryCandidatesPrompt(usedCategories: string[]): string {
  return [
    '라이어게임(추리 파티게임)에 쓸 카테고리 후보 3개를 제안하라.',
    '조건:',
    '- 서로 다른 3개일 것.',
    '- "동물", "음식", "직업"처럼 너무 흔하고 뻔한 카테고리는 피하라.',
    '- 그렇다고 대부분의 사람이 못 알아들을 정도로 생소한 카테고리도 피하라 — 초중고생도 듣자마자',
    '  감이 오는 수준에서, 약간 의외성 있고 흥미로운 카테고리를 골라라.',
    usedCategories.length ? `이미 사용한 카테고리는 피하라: ${usedCategories.join(', ')}.` : '',
    '반드시 JSON만 출력: {"categories": [string, string, string]}',
  ]
    .filter(Boolean)
    .join('\n');
}

// realWord/liarWord 후보 3쌍을 뽑아 코드에서 무작위로 하나를 고른다(카테고리 후보와 동일한 이유).
export function wordPairPrompt(category: string, usedWords: string[]): string {
  return [
    `카테고리 "${category}"의 라이어게임용 제시어 쌍 후보 3개를 만든다.`,
    '각 후보는 같은 카테고리 안에서 연관성은 있지만 서로 다른 두 단어(realWord, liarWord)여야 한다.',
    '너무 멀면 라이어가 바로 티나고, 너무 가까우면 설명이 똑같아진다 (예: "동물" → 사자/호랑이).',
    '단어 자체도 너무 흔하고 뻔한 조합("사자/호랑이" 같은 전형적인 예시)은 피하고, 그렇다고 대부분의',
    '사람이 모를 정도로 생소한 단어도 피하라 — 초중고생도 알 만한 수준에서 살짝 의외성 있는 단어를 써라.',
    '3개 후보는 서로 겹치지 않게 다양한 단어로 만들어라.',
    usedWords.length ? `이미 사용한 단어는 피하라: ${usedWords.join(', ')}.` : '',
    '반드시 JSON만 출력: {"pairs": [{"realWord": string, "liarWord": string}, {"realWord": string, "liarWord": string}, {"realWord": string, "liarWord": string}]}',
  ]
    .filter(Boolean)
    .join('\n');
}

export function botTurnPrompt(ctx: BotTurnContext): string {
  const prior = ctx.priorTurns.map((t) => `- ${t.nickname}: ${t.text}`).join('\n') || '(아직 없음)';
  return [
    "너는 지금 '라이어게임'이라는 추리 파티게임에 실제 참가자로 함께 플레이 중이다.",
    `카테고리는 "${ctx.category}"이고, 너에게 배정된 단어는 "${ctx.assignedWord}"이다.`,
    '너는 이 단어가 진짜 제시어인지 가짜(라이어용) 제시어인지, 네가 라이어인지 전혀 모른다',
    '(다른 참가자와 동일 조건 — 너만 특별히 아는 정보는 없다).',
    '',
    '[설명 작성 규칙]',
    '- 단어 자체나 그 단어를 바로 연상시키는 결정적 특징(정확한 생김새·용도·직접적인 유사어)은',
    '  절대 말하지 마라. 네 설명만 듣고 다른 사람이 원래 단어를 바로 맞히면 안 된다.',
    '- 그 대신 애매하고 간접적인 힌트나 개인적인 경험·느낌을 살짝 섞어서, "나는 이 단어를 잘 알고',
    '  있다"는 여유와 확신이 은근히 묻어나게 말해라 — 이게 네가 라이어가 아니라는 인상을 슬쩍',
    '  풍기게 하는 센스다. 단, 이것도 너무 티나게 자신만만하면 안 되고 자연스러워야 한다.',
    '- 반드시 반말로 써라. 너무 정제되고 완벽한 문장 말고, 사람이 즉흥적으로 말하듯 자연스러운',
    '  한 문장으로.',
    '- 이전에 나온 설명들과 내용이 겹치지 않게 하라.',
    `지금까지 나온 설명:\n${prior}`,
    '설명 문장만 출력하라. 다른 말 붙이지 마라.',
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
