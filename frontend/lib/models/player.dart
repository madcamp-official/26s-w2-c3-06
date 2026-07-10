/// 방/게임에 참여 중인 플레이어(사람 또는 AI 봇).
class Player {
  final String id;
  final String nickname;
  final bool isHost;
  final bool isReady;
  final bool isBot;

  const Player({
    required this.id,
    required this.nickname,
    this.isHost = false,
    this.isReady = false,
    this.isBot = false,
  });

  Player copyWith({bool? isReady}) {
    return Player(
      id: id,
      nickname: nickname,
      isHost: isHost,
      isReady: isReady ?? this.isReady,
      isBot: isBot,
    );
  }
}
