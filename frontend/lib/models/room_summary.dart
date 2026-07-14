/// 로비 화면의 공개방 목록에 표시되는 방 요약 정보.
class RoomSummary {
  final String code;
  final String title;
  final String emoji;
  final String category;
  final String hostNickname;
  final int playerCount;
  final int maxPlayers;
  final bool inProgress;

  const RoomSummary({
    required this.code,
    required this.title,
    this.emoji = '🎮',
    required this.category,
    required this.hostNickname,
    required this.playerCount,
    required this.maxPlayers,
    this.inProgress = false,
  });

  /// 서버 room:publicList 계약
  /// `{ roomCode, title, emoji, hostNickname, category, playerCount, maxPlayers, inProgress }`.
  /// category는 방장이 고르는 중인 값으로 null(AI 랜덤)일 수 있어 표시용 문구로 대체한다.
  factory RoomSummary.fromJson(Map<String, dynamic> json) {
    return RoomSummary(
      code: json['roomCode'] as String,
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? json['title'] as String
          : '이름 없는 방',
      emoji: (json['emoji'] as String?)?.trim().isNotEmpty == true ? json['emoji'] as String : '🎮',
      category: (json['category'] as String?) ?? 'AI 랜덤',
      hostNickname: (json['hostNickname'] as String?) ?? '',
      playerCount: json['playerCount'] as int,
      maxPlayers: json['maxPlayers'] as int,
      inProgress: json['inProgress'] as bool? ?? false,
    );
  }
}
