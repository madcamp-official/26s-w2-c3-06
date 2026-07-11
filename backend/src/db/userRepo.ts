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
export async function updateAvatarUrl(uid: string, avatarUrl: string | null): Promise<void> {
  await prisma.user.update({ where: { uid }, data: { avatarUrl } });
}

// 닉네임 중복 확인. 회원가입 폼의 "중복 확인" 버튼과, DB @unique 제약의 사전 체크용.
// excludeUid를 주면 "본인 소유 닉네임"은 사용 가능으로 취급(프로필 수정 시 재사용 대비).
export async function isNicknameAvailable(nickname: string, excludeUid?: string): Promise<boolean> {
  const existing = await prisma.user.findUnique({ where: { nickname }, select: { uid: true } });
  if (!existing) return true;
  return existing.uid === excludeUid;
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
  level: number;
}

// PLAN "레벨": 승패 무관, 참여 자체(count(plays))로 오르는 구간제 레벨.
// 정확한 구간표는 PLAN TODO에 "추후 확정"으로 남아 있어, 5판당 1레벨을 잠정 기본값으로 둔다.
const GAMES_PER_LEVEL = 5;
function deriveLevel(totalGames: number): number {
  return Math.floor(totalGames / GAMES_PER_LEVEL) + 1;
}

// 전적 4종은 GamePlay 집계로 파생 (PLAN "DB 스키마" 파생 방식 참고). 분모 0이면 null("기록 없음").
export async function getUserStats(uid: string): Promise<UserStats> {
  const plays = await prisma.gamePlay.findMany({
    where: { userId: uid },
    select: { wasLiar: true, won: true },
  });

  const totalGames = plays.length;
  const liarPlays = plays.filter((p) => p.wasLiar);
  const citizenPlays = plays.filter((p) => !p.wasLiar);

  const rate = (rows: { won: boolean }[]) =>
    rows.length === 0 ? null : rows.filter((r) => r.won).length / rows.length;

  return {
    totalGames,
    overallWinRate: rate(plays),
    liarWinRate: rate(liarPlays),
    citizenWinRate: rate(citizenPlays),
    level: deriveLevel(totalGames),
  };
}
