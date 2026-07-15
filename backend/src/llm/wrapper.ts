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

// PLAN "LLM 래퍼" 인터페이스. provider/모델을 나중에 쉽게 바꿀 수 있도록 얇게만 감싼다.
export interface LiarGameLLM {
  generateWordPair(
    category: string | null,
    usedWords: string[],
    usedCategories: string[],
  ): Promise<{ category: string; realWord: string; liarWord: string }>;
  generateBotTurn(ctx: BotTurnContext): Promise<string>;
  generateTurnComment(ctx: TurnCommentContext): Promise<string>;
  explainWord(word: string, category: string): Promise<string | null>; // 카테고리 맥락으로 해석해 설명 텍스트 생성(생성 실패 시에만 null)
  judgeLiarGuess(guess: string, realWord: string, category: string): Promise<boolean>; // 역전승 정답 판정(카테고리 맥락)
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

// 모델이 JSON만 반환하도록 프롬프트했지만, 유효한 JSON 뒤에 설명 문장이나 두 번째 블록을
// 덧붙이는 경우가 있다. 첫 '{'부터 중괄호 균형을 맞춰 첫 완결 객체 하나만 잘라내(문자열 리터럴
// 안의 중괄호는 무시), 뒤에 붙은 잡텍스트가 있어도 안전하게 파싱한다. 코드펜스도 먼저 제거.
function extractFirstJsonObject(raw: string): string | null {
  const cleaned = raw.replace(/```(?:json)?/gi, '');
  const start = cleaned.indexOf('{');
  if (start < 0) return null;
  let depth = 0;
  let inStr = false;
  let esc = false;
  for (let i = start; i < cleaned.length; i++) {
    const ch = cleaned[i];
    if (inStr) {
      if (esc) esc = false;
      else if (ch === '\\') esc = true;
      else if (ch === '"') inStr = false;
    } else if (ch === '"') inStr = true;
    else if (ch === '{') depth++;
    else if (ch === '}') {
      depth--;
      if (depth === 0) return cleaned.slice(start, i + 1);
    }
  }
  return null;
}

function parseJsonBlock<T>(raw: string, label: string): T {
  const json = extractFirstJsonObject(raw);
  if (!json) throw new Error(`${label}: JSON 파싱 실패 — ${raw}`);
  return JSON.parse(json) as T;
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

    // 카테고리와 동일한 이유로 제시어 쌍도 후보 3개를 받아 서버가 무작위로 하나를 고른다.
    const raw = await completeText(wordPairPrompt(resolvedCategory, usedWords), 400);
    const parsed = parseJsonBlock<{ pairs: { citizenWord: string; liarWord: string }[] }>(raw, 'wordPair');
    const pairs = (parsed.pairs ?? []).filter((p) => p?.citizenWord && p?.liarWord);
    if (!pairs.length) throw new Error('wordPair: 빈 응답');
    const pair = pickRandom(pairs);
    return { category: resolvedCategory, realWord: pair.citizenWord, liarWord: pair.liarWord };
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

  async explainWord(word, category) {
    const raw = await completeText(explainWordPrompt(word, category), 200);
    return raw.trim().length > 0 ? raw.trim() : null;
  },

  async judgeLiarGuess(guess, realWord, category) {
    // 정답 판정은 전적으로 LLM에게 맡긴다 — 오타·표기 차이 허용과 동음이의어의 카테고리 맥락
    // 해석까지 프롬프트(judgeLiarGuessPrompt)의 지침대로 모델이 판단한다.
    const raw = await completeText(judgeLiarGuessPrompt(guess, realWord, category), 8);
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
