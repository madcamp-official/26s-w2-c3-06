import OpenAI from 'openai';

// OpenAI SDK 초기화. client.ts(Anthropic)와 동일한 패턴 — provider 전환은 wrapper.ts의
// LLM_PROVIDER 분기 하나로만 이뤄지도록, 이 파일은 client.ts와 같은 모양의 얇은 래퍼로 둔다.
export const OPENAI_MODEL = 'gpt-5.4-mini';
// 정답 판정(judgeLiarGuess)은 단순 참/거짓 분류라 가장 저렴한 티어로 충분 — 생성용 모델과 분리.
export const OPENAI_JUDGE_MODEL = 'gpt-5.4-nano';
// 단어 설명(explainWord)도 창작이 아니라 단순 정보 전달이라 가장 저렴한 티어로 충분.
export const OPENAI_EXPLAIN_MODEL = 'gpt-5.4-nano';

let client: OpenAI | null = null;

export function hasOpenAIKey(): boolean {
  return Boolean(process.env.OPENAI_API_KEY);
}

export function getOpenAI(): OpenAI {
  if (!client) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error('OPENAI_API_KEY 환경변수가 설정되지 않았습니다.');
    }
    client = new OpenAI({ apiKey });
  }
  return client;
}
