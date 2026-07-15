/**
 * LLM 프롬프트 튜닝용 임시 하네스 서버 (git 미추적, .claude/ 하위).
 *
 * 목적: 로그인/게임 없이 generateWordPair·explainWord 등의 입력→출력을 OpenAI로 돌려본다.
 * 프롬프트 문구는 backend/src/llm/prompts.ts의 "실제 함수"를 그대로 import하므로, 그 파일을
 * 수정하고 서버만 재시작(tsx watch면 자동)하면 바로 반영된다. 게임 서버(wrapper.ts)의
 * 파싱/후보선택 로직은 여기서 최소한으로 재현한다.
 *
 * 이제 게임 본체가 OpenAI만 쓰므로(backend/src/llm/wrapper.ts) 이 하네스도 OpenAI 단일
 * provider로만 돌린다 — 예전에 있던 Anthropic과의 나란히 비교 기능은 제거됨.
 *
 * 실행: .claude/prompt-harness/run.sh  (또는 아래 참고)
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// 키는 backend/.env에 있다 — 실행 cwd와 무관하게 그 파일을 명시적으로 로드한다.
dotenv.config({ path: path.resolve(__dirname, '../../backend/.env') });

import {
  categoryCandidatesPrompt,
  wordPairCandidatesPrompt,
  explainWordPrompt,
  botTurnPrompt,
  impersonationPrompt,
  impersonationSystemPrompt,
  judgeLiarGuessPrompt,
} from '../../backend/src/llm/prompts';
import { getOpenAI, OPENAI_MODEL, OPENAI_EXPLAIN_MODEL, hasOpenAIKey } from '../../backend/src/llm/openaiClient';
import type { BotTurnContext, ImpersonationContext } from '../../backend/src/types';

const PORT = Number(process.env.HARNESS_PORT ?? 4100);

// wrapper.ts의 completeText와 동일한 호출 방식.
// search=true면 웹 검색 모드: OpenAI Responses API web_search 툴 사용
// (제시어 생성·단어 설명은 이제 게임 본체에서도 정식으로 항상 켜져 있음 — wrapper.ts 참고).
async function completeText(
  prompt: string,
  maxTokens: number,
  system?: string,
  search = false,
  modelOverride?: string,
  reasoningEffort?: 'none' | 'low' | 'medium' | 'high',
): Promise<string> {
  if (search) {
    // gpt-4o-mini-search-preview(전용 검색 모델)는 gpt-4o 세대 전용이라 폐기됨.
    // gpt-5.4 계열은 Chat Completions에 web_search_options를 얹는 방식 자체가 막혀 있고
    // (400 Unknown parameter), 대신 Responses API + tools:[{type:"web_search"}]로만 검색이
    // 가능하다 — 파라미터 하나가 아니라 엔드포인트/요청·응답 모양이 통째로 다르다.
    const res = await getOpenAI().responses.create({
      model: modelOverride ?? OPENAI_MODEL,
      // 검색 시 추론 토큰 소모가 커서 작으면 답을 못 내고 status:"incomplete"로 끊긴다.
      max_output_tokens: Math.max(maxTokens, 8192),
      tools: [{ type: 'web_search' }],
      input: [
        ...(system ? [{ role: 'system' as const, content: system }] : []),
        { role: 'user' as const, content: prompt },
      ],
    } as any);
    return String((res as any).output_text ?? '').trim();
  }
  const res = await getOpenAI().chat.completions.create({
    model: modelOverride ?? OPENAI_MODEL,
    // gpt-5.4 계열부터 max_tokens가 아니라 max_completion_tokens를 요구한다(400 에러).
    // reasoning 모델은 숨은 추론 토큰도 이 한도에서 함께 차감되므로, 짧은 답을 기대하고
    // 너무 작게 주면 추론만 하다 끊겨 400 에러가 난다.
    max_completion_tokens: maxTokens,
    ...(reasoningEffort ? { reasoning_effort: reasoningEffort } : {}),
    messages: [
      ...(system ? [{ role: 'system' as const, content: system }] : []),
      { role: 'user' as const, content: prompt },
    ],
  });
  return (res.choices[0]?.message?.content ?? '').trim();
}

// wrapper.ts와 동일한 견고 파서 — 첫 완결 JSON 객체만 중괄호 균형으로 잘라내 뒤 잡텍스트 무시.
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

function parseJsonBlock<T>(raw: string): T {
  const json = extractFirstJsonObject(raw);
  if (!json) throw new Error(`JSON 파싱 실패 — ${raw}`);
  return JSON.parse(json) as T;
}

function pickRandom<T>(arr: T[]): { value: T; index: number } {
  const index = Math.floor(Math.random() * arr.length);
  return { value: arr[index], index };
}

// ── generateWordPair 재현 (wrapper.ts realLLM.generateWordPair 기반) ──
// 카테고리 후보 3개 전부와 어느 걸 골랐는지, 그리고 각 단계의 원문 응답을 모두 반환해
// 프론트에서 검토할 수 있게 한다.
interface Labeled { label: string; text: string }

async function runWordPair(opts: { category: string | null; usedWords: string[]; usedCategories: string[] }) {
  // 게임 공용 wordPairCandidatesPrompt에 실존·친숙도 검증을 웹 검색으로 하라는 지시가
  // 이제 정식으로 포함돼 있어(backend/src/llm/prompts.ts), 검색은 선택이 아니라 항상 켠다 —
  // 실제 게임과 동일하게 하네스도 web_search 툴을 항상 붙인다.
  const search = true;
  // prompts/raws는 각 단계 직후 바로 채워두고, 파싱 실패 시에도 catch에서 함께 돌려준다 —
  // 이래야 모델이 뭘 뱉었는지(원문)와 어떤 프롬프트를 보냈는지를 화면에서 진단할 수 있다.
  const prompts: Labeled[] = [];
  const raws: Labeled[] = [];
  try {
    let resolvedCategory = opts.category?.trim() || null;
    let categoryCandidates: string[] | null = null;
    let pickedCategoryIndex: number | null = null;

    if (!resolvedCategory) {
      const catPrompt = categoryCandidatesPrompt(opts.usedCategories);
      const catRaw = await completeText(catPrompt, 200);
      prompts.push({ label: '① 카테고리 후보 프롬프트', text: catPrompt });
      raws.push({ label: '① 카테고리 후보 응답', text: catRaw });
      const catParsed = parseJsonBlock<{ categories: string[] }>(catRaw);
      if (!catParsed.categories?.length) throw new Error('categoryCandidates: 빈 응답');
      categoryCandidates = catParsed.categories;
      const picked = pickRandom(categoryCandidates);
      resolvedCategory = picked.value;
      pickedCategoryIndex = picked.index;
    }

    // 검색 지시문은 이제 wordPairCandidatesPrompt 안에 정식으로 포함돼 있으므로 여기서
    // 별도로 덧붙이지 않는다 — wrapper.ts(실제 게임)와 동일하게 프롬프트는 그대로 쓰고
    // API 호출에서만 web_search 툴을 얹는다.
    const pairPrompt = wordPairCandidatesPrompt(resolvedCategory, opts.usedWords);
    // 검색 모드는 검증 과정을 텍스트로 길게 풀어쓰는 경향이 있어 400~900으론 JSON 직전에
    // 잘린다 — 여유 있게 잡는다.
    const raw = await completeText(pairPrompt, 2500, undefined, search);
    prompts.push({ label: '② 제시어 쌍 프롬프트', text: pairPrompt });
    raws.push({ label: '② 제시어 쌍 응답', text: raw });
    const parsed = parseJsonBlock<{ pairs: { citizenWord: string; liarWord: string }[] }>(raw);
    const pairs = (parsed.pairs ?? []).filter((p) => p?.citizenWord && p?.liarWord);
    if (!pairs.length) throw new Error('wordPair: 빈 응답');
    const pickedPair = pickRandom(pairs);

    return {
      ok: true as const,
      category: resolvedCategory,
      categoryCandidates, // null이면 사용자가 카테고리를 직접 지정
      pickedCategoryIndex,
      wordPairs: pairs, // 후보 3쌍 전부 (프론트에서 나머지 2쌍도 확인 가능)
      pickedPairIndex: pickedPair.index,
      realWord: pairs[pickedPair.index].citizenWord, // 시민에게 제공 (선택된 쌍)
      liarWord: pairs[pickedPair.index].liarWord, // 라이어에게 제공 (선택된 쌍)
      searched: search,
      prompts,
      raws,
    };
  } catch (e) {
    return { ok: false as const, error: String((e as Error)?.message ?? e), prompts, raws };
  }
}

// ── explainWord 재현 (wrapper.ts realLLM.explainWord 기반) ──
async function runExplainWord(word: string, category: string) {
  // 게임 공용 explainWordPrompt에 웹 검색으로 사실관계를 확인하라는 지시가 이제 정식으로
  // 포함돼 있어(backend/src/llm/prompts.ts), 검색은 항상 켠다.
  const search = true;
  try {
    const prompt = explainWordPrompt(word, category);
    const raw = await completeText(prompt, 200, undefined, search, OPENAI_EXPLAIN_MODEL);
    return {
      ok: true as const,
      explanation: raw.trim().length > 0 ? raw.trim() : null,
      searched: search,
      prompts: [{ label: '프롬프트', text: prompt }] as Labeled[],
      raws: [{ label: '응답', text: raw }] as Labeled[],
    };
  } catch (e) {
    return { ok: false as const, error: String((e as Error)?.message ?? e), prompts: [] as Labeled[], raws: [] as Labeled[] };
  }
}

// wrapper.ts의 assertNotRefusal과 동일한 거절/이상응답 감지 — 게임은 이런 응답을 버려
// "메시지 생략"으로 처리하므로, 하네스에서도 그 응답이 걸러질지 플래그로 보여준다.
const REFUSAL_PATTERNS = [
  /i can.?t help/i, /i cannot/i, /i.?m (not able|unable) to/i, /against my/i, /i.?m sorry, but/i,
  /죄송하지만/, /도와드릴 수 없/, /도와드리기 (어렵|힘들)/, /응할 수 없/,
];
function isRefusalOrOverLength(text: string, maxExpectedLength: number): boolean {
  return text.length > maxExpectedLength || REFUSAL_PATTERNS.some((re) => re.test(text));
}

// ── generateBotTurn 재현 (wrapper.ts realLLM.generateBotTurn 기반) ──
async function runBotTurn(ctx: BotTurnContext) {
  try {
    const prompt = botTurnPrompt(ctx);
    const text = await completeText(prompt, 128);
    return {
      ok: true as const,
      text,
      refused: isRefusalOrOverLength(text, 220), // 게임에서 걸러지는지(assertNotRefusal 한도 220)
      prompts: [{ label: '봇 턴 프롬프트', text: prompt }] as Labeled[],
      raws: [{ label: '봇 턴 응답', text }] as Labeled[],
    };
  } catch (e) {
    return { ok: false as const, error: String((e as Error)?.message ?? e), prompts: [] as Labeled[], raws: [] as Labeled[] };
  }
}

// ── generateImpersonationMessage 재현 (wrapper.ts realLLM.generateImpersonationMessage 기반) ──
// 토론 페이즈 중 서버가 5초 간격으로 실제 참가자 한 명을 무작위로 골라 그 사람인 척 자유
// 채팅 메시지를 흘려보내는 기능 — 더 이상 턴마다 붙는 "코멘트"가 아니다.
async function runImpersonation(ctx: ImpersonationContext) {
  try {
    const prompt = impersonationPrompt(ctx);
    const text = await completeText(prompt, 128, impersonationSystemPrompt);
    return {
      ok: true as const,
      text,
      refused: isRefusalOrOverLength(text, 160), // 게임에서 걸러지는지(assertNotRefusal 한도 160)
      prompts: [
        { label: '사칭 메시지 프롬프트', text: prompt },
        { label: '시스템 프롬프트', text: impersonationSystemPrompt },
      ] as Labeled[],
      raws: [{ label: '사칭 메시지 응답', text }] as Labeled[],
    };
  } catch (e) {
    return { ok: false as const, error: String((e as Error)?.message ?? e), prompts: [] as Labeled[], raws: [] as Labeled[] };
  }
}

// ── judgeLiarGuess 재현 (wrapper.ts realLLM.judgeLiarGuess 기반) ──
// 퍼지 매칭은 제거됐으므로 판정은 전적으로 LLM 응답에 의존한다. 카테고리 맥락으로 동음이의어를 해석.
async function runJudge(guess: string, realWord: string, category: string) {
  try {
    const prompt = judgeLiarGuessPrompt(guess, realWord, category);
    // reasoning 모델의 숨은 추론 토큰까지 감안해 max_completion_tokens는 넉넉히, 대신
    // reasoning_effort는 none으로 낮춰 단순 참/거짓 판정에 불필요한 추론을 줄인다
    // (gpt-5.4-mini는 'minimal'을 지원하지 않고 none/low/medium/high/xhigh만 지원).
    const raw = await completeText(prompt, 20, undefined, false, undefined, 'none');
    return {
      ok: true as const,
      verdict: raw.trim().toLowerCase().startsWith('true'),
      prompts: [{ label: '판정 프롬프트', text: prompt }] as Labeled[],
      raws: [{ label: '판정 응답', text: raw }] as Labeled[],
    };
  } catch (e) {
    return { ok: false as const, error: String((e as Error)?.message ?? e), prompts: [] as Labeled[], raws: [] as Labeled[] };
  }
}

async function runTimed<T extends { ok: boolean }>(fn: () => Promise<T>) {
  const t0 = Date.now();
  const v = await fn();
  return { ...v, ms: Date.now() - t0 };
}

function sendJson(res: http.ServerResponse, code: number, body: unknown) {
  const s = JSON.stringify(body);
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(s);
}

function readBody(req: http.IncomingMessage): Promise<any> {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (c) => (data += c));
    req.on('end', () => {
      try {
        resolve(data ? JSON.parse(data) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  try {
    if (req.method === 'GET' && (req.url === '/' || req.url === '/index.html')) {
      const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(html);
      return;
    }

    if (req.method === 'GET' && req.url === '/api/status') {
      sendJson(res, 200, {
        openai: { hasKey: hasOpenAIKey(), model: OPENAI_MODEL, explainModel: OPENAI_EXPLAIN_MODEL },
      });
      return;
    }

    if (req.method === 'POST' && req.url === '/api/word-pair') {
      const body = await readBody(req);
      const category: string | null = body.random ? null : String(body.category ?? '').trim();
      const usedWords: string[] = String(body.usedWords ?? '').split(',').map((s: string) => s.trim()).filter(Boolean);
      const usedCategories: string[] = String(body.usedCategories ?? '').split(',').map((s: string) => s.trim()).filter(Boolean);
      const result = await runTimed(() => runWordPair({ category: category || null, usedWords, usedCategories }));
      sendJson(res, 200, result);
      return;
    }

    if (req.method === 'POST' && req.url === '/api/explain-word') {
      const body = await readBody(req);
      const word = String(body.word ?? '').trim();
      const category = String(body.category ?? '').trim();
      if (!word) {
        sendJson(res, 400, { error: '단어를 입력하세요.' });
        return;
      }
      if (!category) {
        sendJson(res, 400, { error: '카테고리를 입력하세요.' });
        return;
      }
      const result = await runTimed(() => runExplainWord(word, category));
      sendJson(res, 200, result);
      return;
    }

    if (req.method === 'POST' && req.url === '/api/bot-turn') {
      const body = await readBody(req);
      const ctx: BotTurnContext = {
        category: String(body.category ?? '').trim(),
        assignedWord: String(body.assignedWord ?? '').trim(),
        priorTurns: Array.isArray(body.priorTurns) ? body.priorTurns : [],
      };
      if (!ctx.category || !ctx.assignedWord) {
        sendJson(res, 400, { error: '카테고리와 배정 단어가 필요합니다.' });
        return;
      }
      const result = await runTimed(() => runBotTurn(ctx));
      sendJson(res, 200, result);
      return;
    }

    if (req.method === 'POST' && req.url === '/api/impersonation') {
      const body = await readBody(req);
      const ctx: ImpersonationContext = {
        category: String(body.category ?? '').trim(),
        otherParticipantNicknames: Array.isArray(body.otherParticipantNicknames) ? body.otherParticipantNicknames : [],
        recentDiscussion: Array.isArray(body.recentDiscussion) ? body.recentDiscussion : [],
        explanations: Array.isArray(body.explanations) ? body.explanations : [],
      };
      if (!ctx.category) {
        sendJson(res, 400, { error: '카테고리가 필요합니다.' });
        return;
      }
      const result = await runTimed(() => runImpersonation(ctx));
      sendJson(res, 200, result);
      return;
    }

    if (req.method === 'POST' && req.url === '/api/judge') {
      const body = await readBody(req);
      const guess = String(body.guess ?? '').trim();
      const realWord = String(body.realWord ?? '').trim();
      const category = String(body.category ?? '').trim();
      if (!guess || !realWord) {
        sendJson(res, 400, { error: '진짜 제시어와 라이어 답이 모두 필요합니다.' });
        return;
      }
      if (!category) {
        sendJson(res, 400, { error: '카테고리가 필요합니다.' });
        return;
      }
      const result = await runTimed(() => runJudge(guess, realWord, category));
      sendJson(res, 200, result);
      return;
    }

    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Not Found');
  } catch (e) {
    sendJson(res, 500, { error: String((e as Error)?.message ?? e) });
  }
});

server.listen(PORT, () => {
  console.log(`[harness] http://localhost:${PORT}`);
  console.log(`[harness] openai=${OPENAI_MODEL}(key:${hasOpenAIKey()})`);
  console.log('[harness] prompts.ts를 수정하면 tsx watch가 자동 재시작합니다.');
});
