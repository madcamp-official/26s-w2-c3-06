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

export function turnCommentPrompt(ctx: TurnCommentContext): string {
  // 실제 라이어가 누구인지는 절대 입력하지 않는다("정답을 모르는 관전자"처럼 행동).
  const prior = ctx.priorTurns.map((t) => `- ${t.nickname}: ${t.text}`).join('\n') || '(아직 없음)';
  return [
    `카테고리 "${ctx.category}"의 라이어게임을 관전 중이다. 너는 정답을 모른다.`,
    `방금 제출된 설명: "${ctx.latestDescription}"`,
    `이전 설명들:\n${prior}`,
    '이 설명에 대해 다른 플레이어들을 의도적으로 헷갈리게 만드는 짧은 교란 코멘트를 한 문장 생성하라.',
    '플레이어를 지칭할 때는 항상 닉네임을 사용하라.',
    '정답을 아는 척하지 말고, 자연스러운 노이즈가 되도록 하라. 코멘트 문장만 출력하라.',
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
