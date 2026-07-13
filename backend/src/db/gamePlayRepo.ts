import { prisma } from './client';

// 게임 1판 종료 시, 사람 참가자별로 1행씩 기록한다 (봇은 uid가 없어 기록 안 함).
export interface GamePlayEntry {
  userId: string;
  wasLiar: boolean;
  won: boolean;
}

export async function recordGame(entries: GamePlayEntry[]): Promise<void> {
  if (entries.length === 0) return;
  await prisma.gamePlay.createMany({ data: entries });
}
