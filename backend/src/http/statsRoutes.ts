import { Router } from 'express';
import { requireAuth, type AuthedRequest } from './authMiddleware';
import { getUserStats } from '../db/userRepo';

// PLAN "DB 스키마" 전적 4종(전체 게임수·전체/라이어/비라이어 승률) 조회 API.
// Socket.IO 이벤트 계약에는 없는 프로필 조회용 REST 확장.
export const statsRouter = Router();

statsRouter.get('/me', requireAuth, async (req: AuthedRequest, res) => {
  const stats = await getUserStats(req.uid!);
  res.json(stats);
});

statsRouter.get('/:uid', requireAuth, async (req: AuthedRequest, res) => {
  const stats = await getUserStats(req.params.uid as string);
  res.json(stats);
});
