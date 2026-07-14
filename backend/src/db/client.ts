import { PrismaClient } from '@prisma/client';

// Prisma 클라이언트 싱글턴. PLAN "DB 스키마" 참고 (유저 프로필·전적·친구).
// dev 환경의 hot-reload에서 커넥션이 중복 생성되지 않도록 globalThis에 캐시.
const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const prisma = globalForPrisma.prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== 'production') {
  globalForPrisma.prisma = prisma;
}
