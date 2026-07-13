import type { NextFunction, Request, Response } from 'express';
import { admin, initFirebaseAdmin, isFirebaseReady } from '../firebase/admin';
import { upsertUser } from '../db/userRepo';

// REST 엔드포인트(유저 전적·친구)용 Bearer 토큰 검증. Authorization: Bearer <Firebase ID Token>
export interface AuthedRequest extends Request {
  uid?: string;
  isAnonymous?: boolean;
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
    // 로컬 User.nickname이 room:create/join 없이는 갱신되지 않아, 친구 목록 등에
    // 방을 아직 안 만든/안 들어간 유저의 옛 닉네임이 노출될 수 있었다. 인증된 REST
    // 요청마다 토큰의 name 클레임으로 가볍게 동기화(응답을 막지 않는 fire-and-forget).
    if (decoded.name) {
      upsertUser({
        uid: decoded.uid,
        nickname: decoded.name,
        isAnonymous: decoded.firebase?.sign_in_provider === 'anonymous',
      }).catch((err) => console.error('[http] requireAuth 닉네임 동기화 실패', err));
    }
    next();
  } catch {
    res.status(401).json({ error: 'unauthorized: 유효하지 않은 토큰' });
  }
}
