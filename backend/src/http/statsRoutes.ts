import { Router } from 'express';
import { requireAuth, type AuthedRequest } from './authMiddleware';
import {
  deleteUserProfile,
  getUserProfile,
  getUserStats,
  isNicknameAvailable,
  updateAvatarUrl,
  upsertUser,
} from '../db/userRepo';
import { admin, initFirebaseAdmin, isFirebaseReady } from '../firebase/admin';

// PLAN "DB 스키마" 전적 4종(전체 게임수·전체/라이어/시민 승률) 조회 API.
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

// 회원가입/닉네임 변경 직후 로컬 DB 즉시 반영용. Firebase ID 토큰의 name 클레임은
// updateDisplayName 직후 바로 갱신되지 않을 수 있어(토큰이 캐시돼 있으면 다음 자연
// 갱신 전까지 옛 값), requireAuth의 토큰 클레임 동기화만으로는 가입 직후 시점을
// 보장할 수 없다. 프론트가 닉네임 확정 직후 이 엔드포인트를 명시적으로 호출해,
// 친구 요청(FK: Friendship.addresseeId → User.uid) 등이 가입 직후에도 바로
// 동작하도록 로컬 User 행을 즉시 생성/갱신한다.
statsRouter.put('/me', requireAuth, async (req: AuthedRequest, res) => {
  const { nickname } = req.body as { nickname?: string };
  const trimmed = nickname?.trim();
  if (!trimmed) {
    res.status(400).json({ error: 'nickname이 필요합니다.' });
    return;
  }
  const available = await isNicknameAvailable(trimmed, req.uid!);
  if (!available) {
    res.status(409).json({ error: '이미 사용 중인 닉네임입니다.' });
    return;
  }
  try {
    await upsertUser({ uid: req.uid!, nickname: trimmed, isAnonymous: req.isAnonymous ?? true });
  } catch (err) {
    // 동시 요청 등으로 사전 체크 이후 유일성 제약에 걸린 경우(P2002)의 방어적 처리.
    if ((err as { code?: string }).code === 'P2002') {
      res.status(409).json({ error: '이미 사용 중인 닉네임입니다.' });
      return;
    }
    throw err;
  }
  res.status(204).end();
});

// 로그인 시 프리셋 인덱스·업로드 사진을 복원하기 위한 프로필 조회.
statsRouter.get('/me/profile', requireAuth, async (req: AuthedRequest, res) => {
  const profile = await getUserProfile(req.uid!);
  res.json(profile ?? { nickname: null, avatarIndex: 0, avatarUrl: null });
});

// 프로필 사진 저장. 클라이언트가 Firebase Storage(avatars/{uid} 경로, Storage 보안 규칙으로
// 본인만 쓰기 가능)에 직접 업로드한 뒤, 그 다운로드 URL만 이 엔드포인트로 넘겨 DB에 기록한다
// — 서버는 파일을 직접 다루지 않는다. avatarUrl: null이면 프리셋(avatarIndex)으로 되돌리는 것.
statsRouter.patch('/me/avatar', requireAuth, async (req: AuthedRequest, res) => {
  const uid = req.uid!;
  const { avatarUrl } = req.body as { avatarUrl?: string | null };

  if (avatarUrl != null) {
    if (typeof avatarUrl !== 'string') {
      res.status(400).json({ error: 'avatarUrl은 문자열 또는 null이어야 합니다.' });
      return;
    }
    // 본인 uid 경로(avatars/{uid})로 업로드된 파일인지 확인 — 남의 스토리지 URL을
    // 프로필 사진으로 등록하는 것을 막는다.
    const expectedPath = encodeURIComponent(`avatars/${uid}`);
    if (!avatarUrl.startsWith('https://firebasestorage.googleapis.com/') || !avatarUrl.includes(expectedPath)) {
      res.status(400).json({ error: '본인 프로필 사진 경로가 아닙니다.' });
      return;
    }
  }

  await updateAvatarUrl(uid, avatarUrl ?? null);
  res.status(204).end();
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
