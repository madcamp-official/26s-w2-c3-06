import type Anthropic from '@anthropic-ai/sdk';
import { getAnthropic, hasAnthropicKey, MODEL as ANTHROPIC_MODEL } from './anthropicClient';
import { getOpenAI, hasOpenAIKey, OPENAI_MODEL } from './openaiClient';
import {
  categoryCandidatesPrompt,
  wordPairPrompt,
  botTurnPrompt,
  turnCommentPrompt,
  turnCommentSystemPrompt,
  explainWordPrompt,
  judgeLiarGuessPrompt,
} from './prompts';
import type { BotTurnContext, TurnCommentContext } from '../types';
import { mockLLM } from './mock';
import { isFuzzyMatch } from './textMatch';

// PLAN "LLM 래퍼" 인터페이스. provider/모델을 나중에 쉽게 바꿀 수 있도록 얇게만 감싼다.
export interface LiarGameLLM {
  generateWordPair(
    category: string | null,
    usedWords: string[],
    usedCategories: string[],
  ): Promise<{ category: string; realWord: string; liarWord: string }>;
  generateBotTurn(ctx: BotTurnContext): Promise<string>;
  generateTurnComment(ctx: TurnCommentContext): Promise<string>;
  explainWord(word: string): Promise<string | null>; // 난이도 무관 항상 설명 텍스트 생성(생성 실패 시에만 null)
  judgeLiarGuess(guess: string, realWord: string): Promise<boolean>; // 역전승 정답 유사판정
}

// 실제 호출할 provider. .env의 LLM_PROVIDER로 명시 지정(anthropic|openai) — 나중에 다시
// Claude로 돌아가고 싶으면 이 값만 anthropic으로 바꾸면 된다(코드 변경 불필요, 두 키 모두
// .env에 남아있으면 즉시 전환 가능). 명시 지정이 없으면 키가 있는 쪽을 자동으로 고른다.
type LLMProvider = 'anthropic' | 'openai';

function resolveProvider(): LLMProvider | null {
  const explicit = process.env.LLM_PROVIDER?.trim().toLowerCase();
  if (explicit === 'anthropic' || explicit === 'openai') return explicit;
  if (hasOpenAIKey()) return 'openai';
  if (hasAnthropicKey()) return 'anthropic';
  return null;
}

const provider = resolveProvider();

// 프롬프트 문구·JSON 파싱·거절 감지 등 나머지 로직은 provider와 무관하게 전부 동일하게
// 재사용한다 — 여기서 실제 API 호출 부분만 provider별로 분기한다.
async function completeText(prompt: string, maxTokens: number, system?: string): Promise<string> {
  if (provider === 'openai') {
    const res = await getOpenAI().chat.completions.create({
      model: OPENAI_MODEL,
      max_tokens: maxTokens,
      messages: [
        ...(system ? [{ role: 'system' as const, content: system }] : []),
        { role: 'user' as const, content: prompt },
      ],
    });
    return (res.choices[0]?.message?.content ?? '').trim();
  }

  const res = await getAnthropic().messages.create({
    model: ANTHROPIC_MODEL,
    max_tokens: maxTokens,
    ...(system ? { system } : {}),
    messages: [{ role: 'user', content: prompt }],
  });
  return res.content
    .filter((block): block is Anthropic.TextBlock => block.type === 'text')
    .map((block) => block.text)
    .join('')
    .trim();
}

// 프롬프트를 아무리 다듬어도 모델이 드물게 거절 응답을 내놓을 수 있다. 그 텍스트를 그대로
// 게임 채팅에 "AI 코멘트"·"봇의 설명"인 것처럼 흘려보내면 안 되므로, 거절처럼 보이는 응답은
// 여기서 걸러 에러로 처리한다 — 호출부(gameEngine)가 이미 실패 시 "코멘트 생략"으로 조용히
// 넘어가도록 되어 있어, 플레이어에게는 그냥 이번 턴에 코멘트가 없는 것처럼만 보인다.
const REFUSAL_PATTERNS = [
  /i can.?t help/i,
  /i cannot/i,
  /i.?m (not able|unable) to/i,
  /against my/i,
  /i.?m sorry, but/i,
  /죄송하지만/,
  /도와드릴 수 없/,
  /도와드리기 (어렵|힘들)/,
  /응할 수 없/,
];

function assertNotRefusal(text: string, maxExpectedLength: number): void {
  if (text.length > maxExpectedLength || REFUSAL_PATTERNS.some((re) => re.test(text))) {
    throw new Error(`LLM 응답이 거절/이상 응답으로 보여 사용하지 않음: ${text.slice(0, 120)}`);
  }
}

function pickRandom<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

function parseJsonBlock<T>(raw: string, label: string): T {
  // 모델이 JSON만 반환하도록 프롬프트했지만, 방어적으로 첫 JSON 블록만 파싱.
  const match = raw.match(/\{[\s\S]*\}/);
  if (!match) throw new Error(`${label}: JSON 파싱 실패 — ${raw}`);
  return JSON.parse(match[0]) as T;
}

const realLLM: LiarGameLLM = {
  async generateWordPair(category, usedWords, usedCategories) {
    // category가 null(AI 랜덤)이면 먼저 후보 3개를 받아 서버가 무작위로 하나를 고른다 —
    // 모델에게 직접 하나만 확정해달라고 하면 항상 비슷하게 "무난한" 답으로 수렴하는 경향이 있다.
    let resolvedCategory = category;
    if (!resolvedCategory) {
      const catRaw = await completeText(categoryCandidatesPrompt(usedCategories), 200);
      const catParsed = parseJsonBlock<{ categories: string[] }>(catRaw, 'categoryCandidates');
      if (!catParsed.categories?.length) throw new Error('categoryCandidates: 빈 응답');
      resolvedCategory = pickRandom(catParsed.categories);
    }

    const raw = await completeText(wordPairPrompt(resolvedCategory, usedWords), 200);
    const parsed = parseJsonBlock<{ citizenWord: string; liarWord: string }>(raw, 'wordPair');
    if (!parsed.citizenWord || !parsed.liarWord) throw new Error('wordPair: 빈 응답');
    return { category: resolvedCategory, realWord: parsed.citizenWord, liarWord: parsed.liarWord };
  },

  async generateBotTurn(ctx) {
    const text = await completeText(botTurnPrompt(ctx), 128);
    assertNotRefusal(text, 220);
    return text;
  },

  async generateTurnComment(ctx) {
    const text = await completeText(turnCommentPrompt(ctx), 128, turnCommentSystemPrompt);
    assertNotRefusal(text, 160);
    return text;
  },

  async explainWord(word) {
    const raw = await completeText(explainWordPrompt(word), 200);
    return raw.trim().length > 0 ? raw.trim() : null;
  },

  async judgeLiarGuess(guess, realWord) {
    // "펜싱"을 "팬싱"으로 쓰는 등 사소한 오타는 LLM이 지침을 줘도 가끔 너무 엄격하게 오답
    // 처리하는 경우가 있어, 편집 거리 기반 결정적 체크를 먼저 하고 통과하면 LLM 호출 없이
    // 바로 정답 처리한다. 이 체크를 통과 못 하면(의미는 같지만 표기가 많이 다른 경우,
    // 예: "burger"/"버거") 기존처럼 LLM에게 의미 판단을 맡긴다.
    if (isFuzzyMatch(guess, realWord)) return true;
    const raw = await completeText(judgeLiarGuessPrompt(guess, realWord), 8);
    return raw.trim().toLowerCase().startsWith('true');
  },
};

// API 키가 하나도 없는 로컬 dev 환경에서도 게임 흐름 전체를 테스트할 수 있도록,
// firebase-admin과 동일한 패턴으로 키가 없으면 결정적 mock 응답으로 폴백한다.
export const llm: LiarGameLLM = provider ? realLLM : mockLLM;

if (!provider) {
  console.warn('[llm] ANTHROPIC_API_KEY/OPENAI_API_KEY 없음 — mock LLM으로 동작 (실제 LLM 호출 안 함)');
} else {
  console.log(`[llm] provider=${provider} 로 동작`);
}
