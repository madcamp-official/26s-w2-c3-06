import { prisma } from './client';
import { FriendshipStatus } from '@prisma/client';

// PLAN "DB 스키마" 친구 조회: 양방향(requester/addressee)을 모두 살펴 accepted만 목록화.

export class FriendError extends Error {}

export async function sendRequest(requesterId: string, addresseeId: string) {
  if (requesterId === addresseeId) {
    throw new FriendError('자기 자신에게는 친구 요청을 보낼 수 없습니다.');
  }

  const existing = await prisma.friendship.findFirst({
    where: {
      OR: [
        { requesterId, addresseeId },
        { requesterId: addresseeId, addresseeId: requesterId },
      ],
    },
  });

  if (!existing) {
    return prisma.friendship.create({ data: { requesterId, addresseeId } });
  }

  if (existing.status === FriendshipStatus.accepted) {
    throw new FriendError('이미 친구입니다.');
  }
  if (existing.status === FriendshipStatus.blocked) {
    throw new FriendError('요청을 보낼 수 없는 사용자입니다.');
  }
  // 상대가 먼저 나에게 보낸 대기 요청이 있으면 맞수락 처리.
  if (existing.requesterId === addresseeId) {
    return prisma.friendship.update({
      where: { id: existing.id },
      data: { status: FriendshipStatus.accepted },
    });
  }
  throw new FriendError('이미 요청을 보냈습니다.');
}

export async function listPendingRequests(userId: string) {
  return prisma.friendship.findMany({
    where: { addresseeId: userId, status: FriendshipStatus.pending },
    include: { requester: { select: { uid: true, nickname: true, avatarUrl: true } } },
  });
}

export async function respondToRequest(
  userId: string,
  requestId: string,
  action: 'accept' | 'decline',
) {
  const request = await prisma.friendship.findUnique({ where: { id: requestId } });
  if (!request || request.addresseeId !== userId || request.status !== FriendshipStatus.pending) {
    throw new FriendError('처리할 수 없는 친구 요청입니다.');
  }

  if (action === 'decline') {
    await prisma.friendship.delete({ where: { id: requestId } });
    return null;
  }
  return prisma.friendship.update({
    where: { id: requestId },
    data: { status: FriendshipStatus.accepted },
  });
}

export async function listFriends(userId: string) {
  const rows = await prisma.friendship.findMany({
    where: {
      status: FriendshipStatus.accepted,
      OR: [{ requesterId: userId }, { addresseeId: userId }],
    },
    include: {
      requester: { select: { uid: true, nickname: true, avatarUrl: true } },
      addressee: { select: { uid: true, nickname: true, avatarUrl: true } },
    },
  });
  return rows.map((r) => (r.requesterId === userId ? r.addressee : r.requester));
}

export async function removeFriend(userId: string, friendUid: string): Promise<void> {
  await prisma.friendship.deleteMany({
    where: {
      status: FriendshipStatus.accepted,
      OR: [
        { requesterId: userId, addresseeId: friendUid },
        { requesterId: friendUid, addresseeId: userId },
      ],
    },
  });
}
