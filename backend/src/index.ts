import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { createServer } from 'node:http';
import { Server } from 'socket.io';
import { socketAuthMiddleware } from './socket/middleware';
import { registerSocketHandlers } from './socket/handlers';
import * as presence from './socket/presence';
import { statsRouter } from './http/statsRoutes';
import { friendsRouter } from './http/friendsRoutes';
import { startGuestCleanupCron } from './cron/guestCleanup';

const app = express();

// 배포 도메인만 허용(Express CORS·Socket.IO CORS 공통). 네이티브 앱(Android/iOS)·서버 간
// 호출은 브라우저가 아니라 Origin 헤더 자체가 없으므로 항상 허용해도 안전하다.
const PROD_ORIGINS = ['https://l-ai-r-game.madcamp-kaist.org', 'https://l-ai-r-game.up.railway.app'];
function isAllowedOrigin(origin: string | undefined): boolean {
  if (!origin) return true;
  if (PROD_ORIGINS.includes(origin)) return true;
  return /^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(origin);
}

app.use(cors({ origin: (origin, callback) => callback(null, isAllowedOrigin(origin)) }));
app.use(express.json());

// 헬스체크 (배포 상태 확인용)
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', ts: Date.now() });
});

// PLAN "DB 스키마" 전적·친구 조회용 REST 확장 (Socket.IO 계약에는 없음)
app.use('/api/users', statsRouter);
app.use('/api/friends', friendsRouter);

// 웹 프론트(Flutter web build) 정적 호스팅 — 앱 전체를 백엔드와 단일 origin으로 서빙한다.
// 기본 경로는 repo의 frontend/build/web (dev의 src/·prod의 dist/ 어느 쪽에서 실행해도 동일하게 해석).
// WEB_DIR 환경변수로 재정의 가능. 빌드 폴더가 없으면(로컬에서 `flutter build web` 전) 조용히 비활성화.
const webDir = process.env.WEB_DIR ?? path.resolve(__dirname, '../../frontend/build/web');
if (fs.existsSync(path.join(webDir, 'index.html'))) {
  app.use(express.static(webDir));
  // SPA 폴백: /api·/health·/socket.io가 아닌 GET 요청은 index.html로 넘겨 클라이언트 라우팅에 맡긴다.
  app.use((req, res, next) => {
    if (
      req.method !== 'GET' ||
      req.path.startsWith('/api') ||
      req.path.startsWith('/health') ||
      req.path.startsWith('/socket.io')
    ) {
      next();
      return;
    }
    res.sendFile(path.join(webDir, 'index.html'));
  });
  console.log(`[server] 웹 프론트 정적 호스팅 활성: ${webDir}`);
} else {
  console.warn(
    `[server] 웹 빌드 없음(${webDir}) — 정적 호스팅 비활성. \`flutter build web\` 후 재시작하면 활성화됩니다.`,
  );
}

const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: { origin: (origin, callback) => callback(null, isAllowedOrigin(origin)) },
});

io.use(socketAuthMiddleware);

io.on('connection', (socket) => {
  const uid = socket.data.uid as string | undefined;
  console.log(`[socket] connected: ${socket.id} (uid=${uid ?? 'unknown'})`);

  if (uid) presence.setOnline(uid, socket.id);

  registerSocketHandlers(io, socket);

  socket.on('disconnect', (reason) => {
    console.log(`[socket] disconnected: ${socket.id} (${reason})`);
    if (uid) presence.setOffline(uid, socket.id);
  });
});

const PORT = Number(process.env.PORT ?? 3000);
httpServer.listen(PORT, () => {
  console.log(`[server] listening on http://localhost:${PORT}`);
  startGuestCleanupCron();
});
