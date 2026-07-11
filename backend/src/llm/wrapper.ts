import type Anthropic from '@anthropic-ai/sdk';
import { getAnthropic, MODEL } from './client';
import { wordPairPrompt, botTurnPrompt, turnCommentPrompt } from './prompts';
import type { BotTurnContext, TurnCommentContext } from '../types';

// PLAN "LLM 래퍼" 인터페이스. provider/모델을 나중에 쉽게 바꿀 수 있도록 얇게만 감싼다.
export interface LiarGameLLM {
  generateWordPair(
    category: string | null,
    usedWords: string[],
  ): Promise<{ category: string; realWord: string; liarWord: string }>;
  generateBotTurn(ctx: BotTurnContext): Promise<string>;
  generateTurnComment(ctx: TurnCommentContext): Promise<string>;
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

export const llm: LiarGameLLM = {
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
};
