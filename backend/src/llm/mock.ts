import type { LiarGameLLM } from './wrapper';
import type { BotTurnContext, TurnCommentContext } from '../types';

// ANTHROPIC_API_KEY 없이 로컬에서 게임 흐름을 끝까지 돌려볼 수 있는 결정적 mock.
// 실제 프롬프트 품질과는 무관 — 어디까지나 배선(wiring) 검증용.
const WORD_POOLS: Record<string, [string, string]> = {
  동물: ['사자', '호랑이'],
  음식: ['김밥', '유부초밥'],
  영화: ['타이타닉', '아바타'],
  스포츠: ['축구', '풋살'],
};
const DEFAULT_CATEGORY = '동물';

let counter = 0;

export const mockLLM: LiarGameLLM = {
  async generateWordPair(category, usedWords, _usedCategories) {
    const resolvedCategory = category && WORD_POOLS[category] ? category : DEFAULT_CATEGORY;
    let [realWord, liarWord] = WORD_POOLS[resolvedCategory];
    if (usedWords.includes(realWord)) {
      counter += 1;
      realWord = `${realWord}${counter}`;
      liarWord = `${liarWord}${counter}`;
    }
    return { category: resolvedCategory, realWord, liarWord };
  },

  async generateBotTurn(ctx: BotTurnContext) {
    return `(mock) ${ctx.assignedWord}에 대한 설명입니다.`;
  },

  async generateTurnComment(ctx: TurnCommentContext) {
    return `(mock) 야 "${ctx.latestDescription.slice(0, 10)}..." 이거 완전 수상한데?ㅋㅋㅋ 노잼이야 ㅇㅈ?`;
  },

  async explainWord(word: string, category: string) {
    // 난이도 무관 항상 설명을 생성하는 실제 동작에 맞춰, mock도 결정적 설명 문자열을 반환.
    return `(mock) "${category}" 카테고리의 "${word}"에 대한 짧은 설명입니다.`;
  },

  async judgeLiarGuess(guess: string, realWord: string) {
    return guess.trim().toLowerCase() === realWord.trim().toLowerCase();
  },
};
