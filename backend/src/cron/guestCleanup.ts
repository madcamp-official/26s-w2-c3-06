import cron from 'node-cron';
import { prisma } from '../db/client';
import { admin, initFirebaseAdmin, isFirebaseReady } from '../firebase/admin';

// PLAN "게스트 정리(cleanup)": 별도 Cloud Functions 없이 백엔드 프로세스 내에서 node-cron으로
// 매일 1회, 마지막 활동(lastActive)이 30일 이상 지난 익명 계정을 Firebase Auth + 로컬 DB에서 함께 삭제.
const INACTIVE_DAYS = 30;

export async function runGuestCleanup(): Promise<void> {
  const cutoff = new Date(Date.now() - INACTIVE_DAYS * 24 * 60 * 60 * 1000);
  const staleGuests = await prisma.user.findMany({
    where: { isAnonymous: true, lastActive: { lt: cutoff } },
    select: { uid: true },
  });

  if (staleGuests.length === 0) {
    console.log('[cron] guestCleanup: 정리 대상 없음');
    return;
  }

  initFirebaseAdmin();
  for (const { uid } of staleGuests) {
    try {
      if (isFirebaseReady()) {
        await admin.auth().deleteUser(uid);
      }
      // onDelete: Cascade로 GamePlay·Friendship도 함께 삭제됨 (schema.prisma 참고).
      await prisma.user.delete({ where: { uid } });
    } catch (err) {
      console.error(`[cron] guestCleanup: uid=${uid} 삭제 실패`, err);
    }
  }
  console.log(`[cron] guestCleanup: ${staleGuests.length}명 정리 완료`);
}

export function startGuestCleanupCron(): void {
  // 매일 04:00에 1회 실행.
  cron.schedule('0 4 * * *', () => {
    runGuestCleanup().catch((err) => console.error('[cron] guestCleanup 실행 실패', err));
  });
  console.log('[cron] guestCleanup 스케줄 등록 완료 (매일 04:00)');
}
