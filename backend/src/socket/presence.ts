// 전역 접속 프레젠스 레지스트리. 방 참여 여부와 무관하게 "지금 소켓이 연결돼 있는가"를 추적한다
// (roomManager.uidSocketIndex는 방 안에 있는 uid만 추적하므로 로비/친구 화면 프레젠스에는 부족).
// 한 유저가 여러 탭/기기로 접속할 수 있어 uid당 소켓 집합으로 관리하고, 집합이 비면 오프라인.

const socketsByUid = new Map<string, Set<string>>();

export function setOnline(uid: string, socketId: string): void {
  const set = socketsByUid.get(uid) ?? new Set<string>();
  set.add(socketId);
  socketsByUid.set(uid, set);
}

// 해당 소켓만 제거하고, 그 유저의 마지막 소켓이었으면 오프라인이 됐는지를 반환한다.
export function setOffline(uid: string, socketId: string): { nowOffline: boolean } {
  const set = socketsByUid.get(uid);
  if (!set) return { nowOffline: false };
  set.delete(socketId);
  if (set.size === 0) {
    socketsByUid.delete(uid);
    return { nowOffline: true };
  }
  return { nowOffline: false };
}

export function isOnline(uid: string): boolean {
  return socketsByUid.has(uid);
}

export function socketIdsOf(uid: string): string[] {
  return [...(socketsByUid.get(uid) ?? [])];
}
