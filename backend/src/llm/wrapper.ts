import type Anthropic from '@anthropic-ai/sdk';
import { getAnthropic, hasAnthropicKey, MODEL } from './client';
import {
  wordPairPrompt,
  botTurnPrompt,
  turnCommentPrompt,
  explainWordPrompt,
  judgeLiarGuessPrompt,
} from './prompts';
import type { BotTurnContext, TurnCommentContext } from '../types';
import { mockLLM } from './mock';

// PLAN "LLM 래퍼" 인터페이스. provider/모델을 나중에 쉽게 바꿀 수 있도록 얇게만 감싼다.
export interface LiarGameLLM {
  generateWordPair(
    category: string | null,
    usedWords: string[],
  ): Promise<{ category: string; realWord: string; liarWord: string }>;
  generateBotTurn(ctx: BotTurnContext): Promise<string>;
  generateTurnComment(ctx: TurnCommentContext): Promise<string>;
  explainWordIfUnfamiliar(word: string): Promise<string | null>; // 낯설면 설명 텍스트, 아니면 null
  judgeLiarGuess(guess: string, realWord: string): Promise<boolean>; // 역전승 정답 유사판정
}

async function completeText(prompt: string, maxTokens: number): Promise<string> {
  const res = await getAnthropic().messages.create({
    model: MODEL,
    max_tokens: maxTokens,
    messages: [{ role: 'user', content: prompt }],
  });
  return res.content
    .filter((block): block is Anthropic.TextBlock => block.type === 'text')
    .map((block) => block.text)
    .join('')
    .trim();
}

const realLLM: LiarGameLLM = {
  async generateWordPair(category, usedWords) {
    const raw = await completeText(wordPairPrompt(category, usedWords), 256);
    // 모델이 JSON만 반환하도록 프롬프트했지만, 방어적으로 첫 JSON 블록만 파싱.
    const match = raw.match(/\{[\s\S]*\}/);
    if (!match) throw new Error(`generateWordPair: JSON 파싱 실패 — ${raw}`);
    return JSON.parse(match[0]) as { category: string; realWord: string; liarWord: string };
  },

  async generateBotTurn(ctx) {
    return completeText(botTurnPrompt(ctx), 128);
  },

  async generateTurnComment(ctx) {
    return completeText(turnCommentPrompt(ctx), 128);
  },

  async explainWordIfUnfamiliar(word) {
    const raw = await completeText(explainWordPrompt(word), 200);
    return raw.trim().length > 0 ? raw.trim() : null;
  },

  async judgeLiarGuess(guess, realWord) {
    const raw = await completeText(judgeLiarGuessPrompt(guess, realWord), 8);
    return raw.trim().toLowerCase().startsWith('true');
  },
};

// ANTHROPIC_API_KEY가 없는 로컬 dev 환경에서도 게임 흐름 전체를 테스트할 수 있도록,
// firebase-admin과 동일한 패턴으로 키가 없으면 결정적 mock 응답으로 폴백한다.
// 키를 넣으면 코드 변경 없이 바로 실제 Claude 호출로 전환된다.
export const llm: LiarGameLLM = hasAnthropicKey() ? realLLM : mockLLM;

if (!hasAnthropicKey()) {
  console.warn('[llm] ANTHROPIC_API_KEY 없음 — mock LLM으로 동작 (실제 Claude 호출 안 함)');
}
