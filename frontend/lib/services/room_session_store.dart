import 'package:shared_preferences/shared_preferences.dart';

/// 새로고침(웹) 후에도 "어느 방에 있었는지"를 기억하기 위한 로컬 저장소.
/// AuthGate가 시작 시 이 값을 읽어 room:rejoin을 시도한다.
class RoomSessionStore {
  RoomSessionStore._();
  static final RoomSessionStore instance = RoomSessionStore._();

  static const _roomCodeKey = 'active_room_code';

  Future<String?> readRoomCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roomCodeKey);
  }

  Future<void> saveRoomCode(String roomCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roomCodeKey, roomCode);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roomCodeKey);
  }
}
