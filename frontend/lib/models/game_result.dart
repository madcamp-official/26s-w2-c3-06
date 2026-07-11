/// 결과 화면에 표시되는 한 판의 게임 결과.
class GameResult {
  final String category;
  final String liarNickname;
  final String realWord;
  final String fakeWord;
  final bool citizensWin;
  final String summary;

  /// 라이어가 역전승을 시도하며 입력한 답. 역전승 시도가 없었다면 null.
  final String? liarGuess;

  const GameResult({
    required this.category,
    required this.liarNickname,
    required this.realWord,
    required this.fakeWord,
    required this.citizensWin,
    required this.summary,
    this.liarGuess,
  });
}
