import type { NextFunction, Request, Response } from 'express';
import { admin, initFirebaseAdmin, isFirebaseReady } from '../firebase/admin';

// REST 엔드포인트(유저 전적·친구)용 Bearer 토큰 검증. Authorization: Bearer <Firebase ID Token>
export interface AuthedRequest extends Request {
  uid?: string;
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
    next();
  } catch {
    res.status(401).json({ error: 'unauthorized: 유효하지 않은 토큰' });
  }
}
