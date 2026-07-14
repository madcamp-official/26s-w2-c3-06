import type { NextFunction, Request, Response } from 'express';
import { admin, initFirebaseAdmin, isFirebaseReady } from '../firebase/admin';
import { ensureUserExists } from '../db/userRepo';

// REST 엔드포인트(유저 전적·친구)용 Bearer 토큰 검증. Authorization: Bearer <Firebase ID Token>
export interface AuthedRequest extends Request {
  uid?: string;
  isAnonymous?: boolean;
  nickname?: string;
}

export async function requireAuth(
  req: AuthedRequest,
  res: Response,
  next: NextFunction,
): Promise<void> {
  const header = req.header('authorization');
  const token = header?.startsWith('Bearer ') ? header.slice('Bearer '.length) : undefined;

  if (!token) {
    res.status(401).json({ error: 'unauthorized: Authorization 헤더가 없습니다' });
    return;
  }

  initFirebaseAdmin();

  if (!isFirebaseReady()) {
    req.uid = `dev-${token.slice(0, 16)}`;
    next();
    return;
  }

  try {
    const decoded = await admin.auth().verifyIdToken(token);
    req.uid = decoded.uid;
    req.isAnonymous = decoded.firebase?.sign_in_provider === 'anonymous';
    req.nickname = decoded.name;
    // 로컬 User.nickname이 room:create/join 없이는 갱신되지 않아, 친구 목록 등에
    // 방을 아직 안 만든/안 들어간 유저(막 가입 직후)의 User 행 자체가 없을 수 있었다.
    // 신규 유저만 생성하고 기존 유저의 nickname은 절대 덮어쓰지 않는다 — 토큰의 name
    // 클레임은 updateDisplayName 직후 바로 갱신되지 않아, 매번 upsert하면 방금 바꾼
    // 닉네임이 옛 클레임 값으로 되돌아가는 부작용이 있었다(실제 닉네임 변경은
    // PUT /api/users/me가 전담). 뒤이은 라우트 핸들러가 로컬 DB에 아직 없는 User 행을
    // 전제로 동작(예: 프로필 사진 저장)하지 않도록 next() 전에 반드시 기다린다.
    if (decoded.name) {
      try {
        await ensureUserExists({
          uid: decoded.uid,
          nickname: decoded.name,
          isAnonymous: decoded.firebase?.sign_in_provider === 'anonymous',
        });
      } catch (err) {
        console.error('[http] requireAuth 유저 프로비저닝 실패', err);
      }
    }
    next();
  } catch (err) {
    console.error('[http] verifyIdToken 실패', err);
    res.status(401).json({ error: 'unauthorized: 유효하지 않은 토큰' });
  }
}
