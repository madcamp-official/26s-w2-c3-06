import { Router } from 'express';
import { requireAuth, type AuthedRequest } from './authMiddleware';
import { deleteUserProfile, getUserStats, isNicknameAvailable } from '../db/userRepo';
import { admin, initFirebaseAdmin, isFirebaseReady } from '../firebase/admin';

// PLAN "DB 스키마" 전적 4종(전체 게임수·전체/라이어/비라이어 승률) 조회 API.
// Socket.IO 이벤트 계약에는 없는 프로필 조회용 REST 확장.
export const statsRouter = Router();

// 닉네임 중복 확인. 회원가입 단계에서는 아직 Firebase 세션이 없으므로(익명 로그인조차
// 하기 전) 유일하게 인증 없이 여는 엔드포인트다 — 닉네임 사용 여부(boolean)만 노출해
// 민감정보 유출은 없다.
statsRouter.get('/nickname-availability/:nickname', async (req, res) => {
  const nickname = (req.params.nickname as string).trim();
  if (!nickname) {
    res.status(400).json({ error: 'nickname이 필요합니다.' });
    return;
  }
  const available = await isNicknameAvailable(nickname);
  res.json({ available });
});

statsRouter.get('/me', requireAuth, async (req: AuthedRequest, res) => {
  const stats = await getUserStats(req.uid!);
  res.json(stats);
});

statsRouter.get('/:uid', requireAuth, async (req: AuthedRequest, res) => {
  const stats = await getUserStats(req.params.uid as string);
  res.json(stats);
});

// 회원탈퇴. 프론트는 이 엔드포인트 하나만 호출하면 된다 — Firebase Auth 계정 삭제는
// firebase-admin(서버 권한)으로 처리해 "최근 로그인 필요" 재인증 제약을 우회한다.
// 게스트 정리 cron(cron/guestCleanup.ts)과 동일한 삭제 패턴.
statsRouter.delete('/me', requireAuth, async (req: AuthedRequest, res) => {
  const uid = req.uid!;
  initFirebaseAdmin();
  if (isFirebaseReady()) {
    await admin
      .auth()
      .deleteUser(uid)
      .catch((err) => console.error('[http] Firebase 계정 삭제 실패', err));
  }
  await deleteUserProfile(uid);
  res.status(204).end();
});
