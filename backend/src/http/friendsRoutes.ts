import { Router } from 'express';
import { requireAuth, type AuthedRequest } from './authMiddleware';
import * as friendRepo from '../db/friendRepo';
import { findUidByNickname, isAnonymousUser } from '../db/userRepo';
import * as presence from '../socket/presence';

// PLAN "DB 스키마" 친구 기능(요청/수락/거절/목록) REST API.
// Socket.IO 이벤트 계약에는 없는 프로필 조회용 REST 확장 — 실시간성이 필요 없는 CRUD라 REST로 구현.
export const friendsRouter = Router();

friendsRouter.post('/requests', requireAuth, async (req: AuthedRequest, res) => {
  // 친구 요청은 게스트끼리는 물론 게스트-회원 간에도 막고 회원끼리만 허용한다(게스트는
  // uid가 세션마다 바뀔 수 있어 친구 관계가 쉽게 끊어짐).
  if (req.isAnonymous) {
    res.status(403).json({ error: '게스트는 친구 요청을 보낼 수 없습니다. 회원가입 후 이용해주세요.' });
    return;
  }
  const { addresseeUid, addresseeNickname } = req.body as {
    addresseeUid?: string;
    addresseeNickname?: string;
  };
  // uid를 직접 주거나, 닉네임으로 대상을 지정할 수 있다(친구 추가 UI는 닉네임 입력).
  let targetUid = addresseeUid;
  if (!targetUid && addresseeNickname?.trim()) {
    targetUid = (await findUidByNickname(addresseeNickname.trim())) ?? undefined;
    if (!targetUid) {
      res.status(404).json({ error: '해당 닉네임의 사용자를 찾을 수 없습니다.' });
      return;
    }
  }
  if (!targetUid) {
    res.status(400).json({ error: 'addresseeUid 또는 addresseeNickname이 필요합니다.' });
    return;
  }
  if (targetUid === req.uid) {
    res.status(409).json({ error: '자기 자신에게는 친구 요청을 보낼 수 없습니다.' });
    return;
  }
  if (await isAnonymousUser(targetUid)) {
    res.status(403).json({ error: '게스트에게는 친구 요청을 보낼 수 없습니다.' });
    return;
  }
  try {
    const friendship = await friendRepo.sendRequest(req.uid!, targetUid);
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
