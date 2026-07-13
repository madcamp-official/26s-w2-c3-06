import { prisma } from './client';

// PLAN "DB 스키마" 참고. Firebase uid를 PK로 사용.

export async function upsertUser(opts: {
  uid: string;
  nickname: string;
  isAnonymous: boolean;
}) {
  return prisma.user.upsert({
    where: { uid: opts.uid },
    update: {
      nickname: opts.nickname,
      isAnonymous: opts.isAnonymous,
      lastActive: new Date(),
    },
    create: {
      uid: opts.uid,
      nickname: opts.nickname,
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
    create: { uid, avatarUrl, isAnonymous, nickname: fallbackNickname ?? `guest-${uid.slice(0, 8)}` },
  });
}

// 닉네임 중복 확인. 회원가입 폼의 "중복 확인" 버튼과, DB @unique 제약의 사전 체크용.
// excludeUid를 주면 "본인 소유 닉네임"은 사용 가능으로 취급(프로필 수정 시 재사용 대비).
export async function isNicknameAvailable(nickname: string, excludeUid?: string): Promise<boolean> {
  const existing = await prisma.user.findUnique({ where: { nickname }, select: { uid: true } });
  if (!existing) return true;
  return existing.uid === excludeUid;
}

// 닉네임으로 uid 조회 — 친구 요청을 닉네임으로 보낼 때 대상 uid 해석에 쓴다. 없으면 null.
export async function findUidByNickname(nickname: string): Promise<string | null> {
  const user = await prisma.user.findUnique({ where: { nickname }, select: { uid: true } });
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

function deriveLevel(exp: number): number {
  let level = 1;
  while (levelThreshold(level + 1) <= exp) level++;
  return level;
}

// 게임 1판이 정상 종료됐을 때(사람 참가자만) 지급하는 EXP. PLAN "경험치(EXP) 및 레벨 정책" 참고.
// 방을 나가 승패 판정 자체가 안 난 경우는 이 함수가 아예 호출되지 않아 0 EXP가 자연스레 보장된다.
// (주의: 아래 지급액은 구(舊) 정책 값이다. 역할·투표대상·참여도까지 반영하는 새 정책은 GamePlay에
//  없는 필드(투표 대상 등)가 필요해 PLAN에서 별도 작업으로 남겨둔 상태 — 용어만 EXP로 통일했다.)
function expForOutcome(wasLiar: boolean, won: boolean): number {
  if (wasLiar) return won ? 110 : 60;
  return won ? 100 : 60;
}

// finalizeGame이 recordGame과 함께 호출 — 한 게임당 유저별로 한 번만 불려 중복 지급을 막는다.
export async function awardExp(
  entries: { userId: string; wasLiar: boolean; won: boolean }[],
): Promise<void> {
  await Promise.all(
    entries.map((e) =>
      prisma.user.update({
        where: { uid: e.userId },
        data: { exp: { increment: expForOutcome(e.wasLiar, e.won) } },
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
