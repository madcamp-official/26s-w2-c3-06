import { Router } from 'express';
import { requireAuth, type AuthedRequest } from './authMiddleware';
import * as friendRepo from '../db/friendRepo';
import * as presence from '../socket/presence';

// PLAN "DB 스키마" 친구 기능(요청/수락/거절/목록) REST API.
// Socket.IO 이벤트 계약에는 없는 프로필 조회용 REST 확장 — 실시간성이 필요 없는 CRUD라 REST로 구현.
export const friendsRouter = Router();

friendsRouter.post('/requests', requireAuth, async (req: AuthedRequest, res) => {
  const { addresseeUid } = req.body as { addresseeUid?: string };
  if (!addresseeUid) {
    res.status(400).json({ error: 'addresseeUid가 필요합니다.' });
    return;
  }
  try {
    const friendship = await friendRepo.sendRequest(req.uid!, addresseeUid);
    res.status(201).json(friendship);
  } catch (err) {
    if (err instanceof friendRepo.FriendError) {
      res.status(409).json({ error: err.message });
      return;
    }
    throw err;
  }
});

friendsRouter.get('/requests', requireAuth, async (req: AuthedRequest, res) => {
  const requests = await friendRepo.listPendingRequests(req.uid!);
  res.json({ requests });
});

friendsRouter.post('/requests/:id/accept', requireAuth, async (req: AuthedRequest, res) => {
  try {
    const friendship = await friendRepo.respondToRequest(req.uid!, req.params.id as string, 'accept');
    res.json(friendship);
  } catch (err) {
    if (err instanceof friendRepo.FriendError) {
      res.status(409).json({ error: err.message });
      return;
    }
    throw err;
  }
});

friendsRouter.post('/requests/:id/decline', requireAuth, async (req: AuthedRequest, res) => {
  try {
    await friendRepo.respondToRequest(req.uid!, req.params.id as string, 'decline');
    res.status(204).end();
  } catch (err) {
    if (err instanceof friendRepo.FriendError) {
      res.status(409).json({ error: err.message });
      return;
    }
    throw err;
  }
});

friendsRouter.get('/', requireAuth, async (req: AuthedRequest, res) => {
  const friends = await friendRepo.listFriends(req.uid!);
  // 접속 여부(isOnline)를 현재 소켓 프레젠스 스냅샷으로 덧붙인다 — 방 초대 가능 여부/온라인 표시용.
  const withPresence = friends.map((f) => ({ ...f, isOnline: presence.isOnline(f.uid) }));
  res.json({ friends: withPresence });
});

friendsRouter.delete('/:uid', requireAuth, async (req: AuthedRequest, res) => {
  await friendRepo.removeFriend(req.uid!, req.params.uid as string);
  res.status(204).end();
});
