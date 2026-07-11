import type { Socket } from 'socket.io';
import { admin, initFirebaseAdmin, isFirebaseReady } from '../firebase/admin';

// Socket.IO handshake 인증 미들웨어.
// PLAN "인증/유저 관리 흐름" 참고: 클라이언트가 Firebase ID 토큰을 handshake.auth.token으로 전달하면
// 백엔드가 firebase-admin으로 검증하고 uid를 socket.data에 실어둔다.
//
// 서비스 계정 키가 없는 로컬 dev 환경에서는 검증을 생략하고 토큰 문자열에서 파생한
// 임시 uid를 붙인다(개발 편의용 — 프로덕션에서는 반드시 키가 있어야 함).
export async function socketAuthMiddleware(
  socket: Socket,
  next: (err?: Error) => void,
): Promise<void> {
  const token = socket.handshake.auth?.token as string | undefined;

  if (!token) {
    next(new Error('unauthorized: 토큰이 없습니다'));
    return;
  }

  initFirebaseAdmin();

  if (!isFirebaseReady()) {
    socket.data.uid = `dev-${token.slice(0, 16)}`;
    socket.data.isAnonymous = true;
    next();
    return;
  }

  try {
    const decoded = await admin.auth().verifyIdToken(token);
    socket.data.uid = decoded.uid;
    socket.data.isAnonymous = decoded.firebase?.sign_in_provider === 'anonymous';
    next();
  } catch {
    next(new Error('unauthorized: 유효하지 않은 토큰'));
  }
}
