import type { Socket } from 'socket.io';

// Socket.IO handshake 인증 미들웨어.
// PLAN "인증/유저 관리 흐름" 참고: 클라이언트가 Firebase ID 토큰을 handshake.auth.token으로 전달하면
// 백엔드가 firebase-admin으로 검증하고 uid를 socket.data에 실어둔다.
//
// TODO(스캐폴드): firebase-admin 초기화 후 admin.auth().verifyIdToken(token)으로 교체.
//   현재는 검증을 건너뛰고 토큰에서 파생한 임시 uid를 붙인다.
export async function socketAuthMiddleware(
  socket: Socket,
  next: (err?: Error) => void,
): Promise<void> {
  try {
    const token = socket.handshake.auth?.token as string | undefined;
    socket.data.uid = token ? `uid-${token.slice(0, 12)}` : `anon-${socket.id}`;
    next();
  } catch (err) {
    next(err instanceof Error ? err : new Error('auth failed'));
  }
}
