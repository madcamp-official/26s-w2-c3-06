import { prisma } from './client';

// PLAN "DB 스키마" 참고. Firebase uid를 PK로 사용.

export async function upsertUser(opts: {
  uid: string;
  nickname: string;
  avatarIndex?: number;
  isAnonymous: boolean;
}) {
  return prisma.user.upsert({
    where: { uid: opts.uid },
    update: {
      nickname: opts.nickname,
      avatarIndex: opts.avatarIndex ?? undefined,
      isAnonymous: opts.isAnonymous,
      lastActive: new Date(),
    },
    create: {
      uid: opts.uid,
      nickname: opts.nickname,
      avatarIndex: opts.avatarIndex ?? 0,
      isAnonymous: opts.isAnonymous,
    },
  });
}

export async function touchLastActive(uid: string): Promise<void> {
  await prisma.user.update({ where: { uid }, data: { lastActive: new Date() } }).catch(() => {
    // 유저 행이 아직 없으면(예: DB 연동 전 소켓 흐름) 조용히 무시 — 전적 기록 시 upsert로 생성됨.
  });
}

export interface UserStats {
  totalGames: number;
  overallWinRate: number | null;
  liarWinRate: number | null;
  citizenWinRate: number | null;
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
  };
}
