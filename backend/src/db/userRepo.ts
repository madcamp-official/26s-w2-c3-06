import { prisma } from './client';

// PLAN "DB 스키마" 참고. Firebase uid를 PK로 사용.

// 닉네임 정규화 — 저장·조회 모든 경로에서 통일해서 쓴다.
// 유니코드 정규화(NFC)로 한글 조합/분해형 차이를 없애고, 소프트하이픈(U+00AD)·제로폭 문자 등
// 눈에 보이지 않는 서식 문자를 제거한 뒤 앞뒤 공백을 잘라낸다. 구글 계정 이름 등 외부에서 가져온
// displayName에 이런 불가시 문자가 섞이면 화면엔 같아 보이는 닉네임이 nickname @unique를 우회해
// 중복 저장되던 문제(예: "김혜리" vs U+00AD가 붙은 "김혜리")를 막는다.
// 닉네임에서 제거할 보이지 않는 서식 문자들(리터럴로 두면 유지보수 불가라 코드포인트로 명시):
// U+00AD 소프트하이픈, U+200B~200D 제로폭(공백/비접합/접합), U+2060 워드조이너, U+FEFF BOM/ZWNBSP.
const INVISIBLE_CODEPOINTS = [0x00ad, 0x200b, 0x200c, 0x200d, 0x2060, 0xfeff];
export function sanitizeNickname(name: string): string {
  let s = (name ?? "").normalize("NFC");
  for (const cp of INVISIBLE_CODEPOINTS) s = s.split(String.fromCharCode(cp)).join("");
  return s.trim();
}

export async function upsertUser(opts: {
  uid: string;
  nickname: string;
  isAnonymous: boolean;
}) {
  const nickname = sanitizeNickname(opts.nickname);
  return prisma.user.upsert({
    where: { uid: opts.uid },
    update: {
      nickname,
      isAnonymous: opts.isAnonymous,
      lastActive: new Date(),
    },
    create: {
      uid: opts.uid,
      nickname,
      isAnonymous: opts.isAnonymous,
    },
  });
}

// requireAuth의 "로컬 DB에 User 행이 아직 없는 신규 유저 프로비저닝" 전용. Firebase ID 토큰의
// name 클레임은 updateDisplayName 직후 즉시 갱신되지 않아(다음 토큰 갱신 전까지 캐시됨), 이미
// 존재하는 유저에게 upsertUser처럼 nickname을 매번 덮어쓰면 방금 바꾼 닉네임이 오래된 토큰의
// name 클레임으로 되돌아가버린다. 존재하지 않을 때만 생성하고, 이미 있으면 손대지 않는다
// (실제 닉네임 변경은 PUT /api/users/me의 upsertUser가 전담).
export async function ensureUserExists(opts: {
  uid: string;
  nickname: string;
  isAnonymous: boolean;
}) {
  return prisma.user.upsert({
    where: { uid: opts.uid },
    update: { lastActive: new Date() },
    create: {
      uid: opts.uid,
      nickname: sanitizeNickname(opts.nickname),
      isAnonymous: opts.isAnonymous,
    },
  });
}

export interface UserProfile {
  nickname: string;
  avatarUrl: string | null;
}

// 로그인 시 프론트가 업로드한 프로필 사진을 복원하기 위한 조회.
// 로컬 DB에 아직 프로필이 없는 유저(막 가입해 upsertUser가 아직 안 돈 경우)는 null.
export async function getUserProfile(uid: string): Promise<UserProfile | null> {
  const user = await prisma.user.findUnique({
    where: { uid },
    select: { nickname: true, avatarUrl: true },
  });
  return user ?? null;
}

// 프로필 사진 업로드/삭제(avatarUrl: null). 실제 파일은 Firebase Storage가 들고 있고
// 여기선 다운로드 URL만 소유 — updateAvatarUrl 호출 전 라우트에서 본인 경로인지 검증한다.
// upsert를 쓰는 이유: 로그인 직후 닉네임 동기화(upsertUser)가 아직 반영되기 전에(레이스,
// 또는 토큰 name 클레임 캐시로 requireAuth의 fallback이 못 도는 경우) 사진부터 올리는
// 게스트가 있을 수 있어, User 행이 아직 없으면 fallbackNickname으로 새로 만든다.
export async function updateAvatarUrl(
  uid: string,
  avatarUrl: string | null,
  fallbackNickname?: string,
  isAnonymous = true,
): Promise<void> {
  await prisma.user.upsert({
    where: { uid },
    update: { avatarUrl },
    create: {
      uid,
      avatarUrl,
      isAnonymous,
      nickname: fallbackNickname ? sanitizeNickname(fallbackNickname) : `guest-${uid.slice(0, 8)}`,
    },
  });
}

// 닉네임 중복 확인. 회원가입 폼의 "중복 확인" 버튼과, DB @unique 제약의 사전 체크용.
// excludeUid를 주면 "본인 소유 닉네임"은 사용 가능으로 취급(프로필 수정 시 재사용 대비).
export async function isNicknameAvailable(nickname: string, excludeUid?: string): Promise<boolean> {
  const existing = await prisma.user.findUnique({
    where: { nickname: sanitizeNickname(nickname) },
    select: { uid: true },
  });
  if (!existing) return true;
  return existing.uid === excludeUid;
}

// 닉네임으로 uid 조회 — 친구 요청을 닉네임으로 보낼 때 대상 uid 해석에 쓴다. 없으면 null.
export async function findUidByNickname(nickname: string): Promise<string | null> {
  const user = await prisma.user.findUnique({
    where: { nickname: sanitizeNickname(nickname) },
    select: { uid: true },
  });
  return user?.uid ?? null;
}

// 친구 요청은 게스트(익명 계정)끼리는 물론 게스트-회원 간에도 막고 회원끼리만 허용한다 —
// 게스트는 uid가 매 세션 바뀔 수 있어 친구 관계가 끊기기 쉽기 때문. 대상 uid의 DB 행이
// 아직 없으면(친구 요청 대상이 될 정도로 실존하는 닉네임이면 이미 있는 게 정상이지만
// 방어적으로) 게스트로 간주해 차단한다.
export async function isAnonymousUser(uid: string): Promise<boolean> {
  const user = await prisma.user.findUnique({ where: { uid }, select: { isAnonymous: true } });
  return user?.isAnonymous ?? true;
}

export async function touchLastActive(uid: string): Promise<void> {
  await prisma.user.update({ where: { uid }, data: { lastActive: new Date() } }).catch(() => {
    // 유저 행이 아직 없으면(예: DB 연동 전 소켓 흐름) 조용히 무시 — 전적 기록 시 upsert로 생성됨.
  });
}

// 로컬 DB 프로필 삭제. onDelete: Cascade로 GamePlay·Friendship도 함께 삭제됨 (schema.prisma 참고).
export async function deleteUserProfile(uid: string): Promise<void> {
  await prisma.user.delete({ where: { uid } }).catch(() => {
    // 로컬 DB에 프로필이 아직 없던 유저(게임을 한 번도 안 한 경우)면 조용히 무시.
  });
}

export interface UserStats {
  totalGames: number;
  overallWinRate: number | null;
  liarWinRate: number | null;
  citizenWinRate: number | null;
  exp: number;
  level: number;
}

// PLAN "DB 스키마"의 EXP 및 레벨 참고. EXP는 GamePlay와 달리 파생값이 아니라 User.exp 컬럼에
// 직접 저장되는 단조증가 값이다(게임 종료 시 awardExp로 증가시킨다).

// 레벨 L(L≥1)까지 도달하는 데 필요한 누적 EXP 임계값. 다음 레벨까지 필요한 증분은
// 100 + (L-1)*30으로 매 레벨 30씩 늘어나며, 이를 누적한 닫힌 형태 공식이다.
// (L=1은 0, L=2는 100, L=3은 230, L=4는 390 ... PLAN의 레벨 구간표와 정확히 일치)
function levelThreshold(level: number): number {
  if (level <= 1) return 0;
  return 100 * (level - 1) + 15 * (level - 1) * (level - 2);
}

export function deriveLevel(exp: number): number {
  let level = 1;
  while (levelThreshold(level + 1) <= exp) level++;
  return level;
}

// 한 게임 종료 시 플레이어 1명의 EXP를 계산하기 위한 입력. gameEngine이 finalize 시점의
// 게임 상태(투표 내역·지목·역전승·설명 제출 여부)에서 채워 넘긴다. PLAN "경험치(EXP) 및
// 레벨 정책" 표와 1:1 대응한다.
export interface ExpAwardInput {
  wasLiar: boolean; // 이 게임에서 라이어였는지
  won: boolean; // 이 유저가 속한 팀이 최종 승리했는지
  votedForLiar: boolean; // (시민용) 실제 라이어에게 투표했는지 — 라이어 본인에겐 무의미
  wasComebackWin: boolean; // (라이어용) 지목된 뒤 진짜 제시어를 맞혀 역전승했는지
  submittedAllDescriptions: boolean; // 자기 차례의 필수 설명을 모두 제출했는지
  voted: boolean; // 투표를 완료했는지
  gameValid: boolean; // 반복 플레이 악용 방지 통과(정상 게임)인지 — 무효면 전원 0 EXP
}

// PLAN "경험치 지급 정책" 표의 역할·게임결과·개인결과별 기본 EXP(baseExp).
function baseExp(i: ExpAwardInput): number {
  if (i.wasLiar) {
    if (i.won) return i.wasComebackWin ? 75 : 60; // 지목 후 역전승 75 / 들키지 않고 승리 60
    return 10; // 라이어 패배(제시어 추측 실패)
  }
  // 시민
  if (i.won) return i.votedForLiar ? 45 : 30; // 승리 + 라이어 정확 지목 45 / 오지목 30
  return i.votedForLiar ? 16 : 6; // 패배해도 라이어 지목 16 / 패배 + 오판 6
}

// 최종 EXP = max(0, floor(baseExp × 참여도 보정 × 반복플레이 보정)). PLAN 계산식과 동일.
// - 참여도: 설명 제출 + 투표 완료 둘 다 1.0, 둘 중 하나만 0.5, 둘 다 안 함 0
// - 반복플레이: 정상 게임 1, 무효 게임 0
export function computeExpAward(i: ExpAwardInput): number {
  const participationCount = (i.submittedAllDescriptions ? 1 : 0) + (i.voted ? 1 : 0);
  const participationMultiplier = participationCount === 2 ? 1 : participationCount === 1 ? 0.5 : 0;
  const repeatMatchMultiplier = i.gameValid ? 1 : 0;
  return Math.max(0, Math.floor(baseExp(i) * participationMultiplier * repeatMatchMultiplier));
}

// finalizeGame이 recordGame과 함께 호출 — 한 게임당 유저별로 한 번만 불려 중복 지급을 막는다.
// EXP는 이미 계산된 값(computeExpAward 결과)을 그대로 누적한다. 0 이하는 갱신을 건너뛴다
// (경험치는 단조증가만 하므로 감소·무변경 업데이트는 불필요).
export async function awardExp(entries: { userId: string; exp: number }[]): Promise<void> {
  await Promise.all(
    entries
      .filter((e) => e.exp > 0)
      .map((e) =>
        prisma.user.update({
          where: { uid: e.userId },
          data: { exp: { increment: e.exp } },
        }),
      ),
  );
}

// 전적은 GamePlay 집계로 파생하고(PLAN "DB 스키마" 파생 방식 참고), EXP는 User.exp를 그대로
// 읽는다. 분모 0인 승률은 null("기록 없음"). 아직 로컬 DB에 User 행이 없는 유저(막 가입해
// upsertUser가 아직 안 돈 경우)는 exp 0/level 1로 취급한다.
export async function getUserStats(uid: string): Promise<UserStats> {
  const [plays, user] = await Promise.all([
    prisma.gamePlay.findMany({ where: { userId: uid }, select: { wasLiar: true, won: true } }),
    prisma.user.findUnique({ where: { uid }, select: { exp: true } }),
  ]);

  const totalGames = plays.length;
  const liarPlays = plays.filter((p) => p.wasLiar);
  const citizenPlays = plays.filter((p) => !p.wasLiar);

  const rate = (rows: { won: boolean }[]) =>
    rows.length === 0 ? null : rows.filter((r) => r.won).length / rows.length;

  const exp = user?.exp ?? 0;

  return {
    totalGames,
    overallWinRate: rate(plays),
    liarWinRate: rate(liarPlays),
    citizenWinRate: rate(citizenPlays),
    exp,
    level: deriveLevel(exp),
  };
}
