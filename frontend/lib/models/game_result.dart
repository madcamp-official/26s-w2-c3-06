/// 결과 화면에 표시되는 한 판의 게임 결과.
class GameResult {
  final String category;
  final String liarNickname;
  final String realWord;
  final String fakeWord;
  final bool citizensWin;

  const GameResult({
    required this.category,
    required this.liarNickname,
    required this.realWord,
    required this.fakeWord,
    required this.citizensWin,
  });
}
