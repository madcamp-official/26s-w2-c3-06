/// 로비 화면의 공개방 목록에 표시되는 방 요약 정보.
class RoomSummary {
  final String code;
  final String title;
  final String hostNickname;
  final int playerCount;
  final int maxPlayers;

  const RoomSummary({
    required this.code,
    required this.title,
    required this.hostNickname,
    required this.playerCount,
    required this.maxPlayers,
  });
}
