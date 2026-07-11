import Anthropic from '@anthropic-ai/sdk';

// Anthropic SDK 초기화. PLAN "확정된 제품/기술 결정": 세 함수 모두 Haiku 4.5로 시작.
export const MODEL = 'claude-haiku-4-5-20251001';

let client: Anthropic | null = null;

export function getAnthropic(): Anthropic {
  if (!client) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new Error('ANTHROPIC_API_KEY 환경변수가 설정되지 않았습니다.');
    }
    client = new Anthropic({ apiKey });
  }
  return client;
}
