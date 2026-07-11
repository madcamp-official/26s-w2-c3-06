import 'dotenv/config';
import express from 'express';
import { createServer } from 'node:http';
import { Server } from 'socket.io';
import { socketAuthMiddleware } from './socket/middleware';
import { registerSocketHandlers } from './socket/handlers';

const app = express();
app.use(express.json());

// 헬스체크 (배포 상태 확인용)
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', ts: Date.now() });
});

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
});
