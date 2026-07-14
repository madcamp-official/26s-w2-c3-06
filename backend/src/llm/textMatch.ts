// 라이어 역전승 정답 판정에 쓰는 문자열 유사도 유틸. LLM 판정("burger"/"버거" 같은 번역·동의어
// 인정)만으로는 "펜싱"을 "팬싱"으로 오타 낸 경우처럼 아주 사소한 오타조차 오답 처리될 수 있어,
// 편집 거리 기반의 결정적(deterministic) 사전 체크를 함께 둔다.

export function normalizeWord(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, '');
}

function levenshtein(a: string, b: string): number {
  const m = a.length;
  const n = b.length;
  if (m === 0) return n;
  if (n === 0) return m;
  const dp: number[][] = Array.from({ length: m + 1 }, () => new Array<number>(n + 1).fill(0));
  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] =
        a[i - 1] === b[j - 1]
          ? dp[i - 1][j - 1]
          : 1 + Math.min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]);
    }
  }
  return dp[m][n];
}

// 짧은 단어(2~3자)는 편집 거리 1까지, 그보다 긴 단어는 길이의 20%(최소 1)까지 오타로 인정한다.
// "펜싱"(2자)과 "팬싱"처럼 한 글자만 다른 경우를 확실히 정답으로 인정하기 위함.
export function isFuzzyMatch(guess: string, realWord: string): boolean {
  const a = normalizeWord(guess);
  const b = normalizeWord(realWord);
  if (!a || !b) return false;
  if (a === b) return true;
  const threshold = Math.max(1, Math.floor(b.length * 0.2));
  return levenshtein(a, b) <= threshold;
}
