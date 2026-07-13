import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import fs from 'node:fs';
import path from 'node:path';
import { createServer } from 'node:http';
import { Server } from 'socket.io';
import { socketAuthMiddleware } from './socket/middleware';
import { registerSocketHandlers } from './socket/handlers';
import { statsRouter } from './http/statsRoutes';
import { friendsRouter } from './http/friendsRoutes';
import { startGuestCleanupCron } from './cron/guestCleanup';

const app = express();
// TODO: 배포 시 프론트와 단일 origin이면 제한. 개발 중에는 전체 허용(Socket.IO cors 설정과 동일 기조).
app.use(cors());
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
  // TODO: 배포 시 프론트와 단일 origin이면 제한. 개발 중에는 전체 허용.
  cors: { origin: '*' },
});

io.use(socketAuthMiddleware);

io.on('connection', (socket) => {
  const uid = socket.data.uid as string | undefined;
  console.log(`[socket] connected: ${socket.id} (uid=${uid ?? 'unknown'})`);

  registerSocketHandlers(io, socket);

  socket.on('disconnect', (reason) => {
    console.log(`[socket] disconnected: ${socket.id} (${reason})`);
  });
});

const PORT = Number(process.env.PORT ?? 3000);
httpServer.listen(PORT, () => {
  console.log(`[server] listening on http://localhost:${PORT}`);
  startGuestCleanupCron();
});
