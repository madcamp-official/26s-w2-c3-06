import admin from 'firebase-admin';
import { existsSync } from 'node:fs';

// PLAN "인증/유저 관리 흐름": Firebase Auth는 인증 전용, 소켓 handshake·REST 요청에서
// ID 토큰을 firebase-admin으로 검증한다.
//
// 서비스 계정 키(GOOGLE_APPLICATION_CREDENTIALS)가 없는 로컬 개발 환경에서도
// 서버가 죽지 않도록, 키가 없으면 초기화를 건너뛰고 dev fallback으로 동작한다
// (auth 미들웨어가 이 상태를 감지해 토큰 검증을 생략).
let initialized = false;

export function initFirebaseAdmin(): boolean {
  if (initialized) return true;
  if (admin.apps.length > 0) {
    initialized = true;
    return true;
  }

  const credPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!credPath || !existsSync(credPath)) {
    console.warn(
      '[firebase] GOOGLE_APPLICATION_CREDENTIALS 없음 — dev fallback 모드로 동작 (ID 토큰 검증 생략)',
    );
    return false;
  }

  admin.initializeApp({ credential: admin.credential.applicationDefault() });
  initialized = true;
  console.log('[firebase] admin SDK 초기화 완료');
  return true;
}

export function isFirebaseReady(): boolean {
  return initialized;
}

export { admin };
