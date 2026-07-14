/// 방/게임에 참여 중인 플레이어(사람 또는 AI 봇).
/// 서버 계약(PLAN Player): `{ id, nickname, isBot, connected, isReady }`.
/// 방장 여부는 서버가 보내지 않고 `RoomState.hostId == player.id`로 판별한다 — [isHost]는
/// 화면 편의를 위해 클라이언트가 채워 넣는 파생 필드로, 서버 파싱(fromJson)에는 없다.
class Player {
  final String id;
  final String nickname;
  final bool isHost;
  final bool isReady;
  final bool isBot;
  final bool connected;

  const Player({
    required this.id,
    required this.nickname,
    this.isHost = false,
    this.isReady = false,
    this.isBot = false,
    this.connected = true,
  });

  Player copyWith({bool? isReady, bool? isHost}) {
    return Player(
      id: id,
      nickname: nickname,
      isHost: isHost ?? this.isHost,
      isReady: isReady ?? this.isReady,
      isBot: isBot,
      connected: connected,
    );
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      nickname: json['nickname'] as String,
      isBot: json['isBot'] as bool? ?? false,
      connected: json['connected'] as bool? ?? true,
      isReady: json['isReady'] as bool? ?? false,
    );
  }
}
