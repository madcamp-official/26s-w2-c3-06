/// 결과 화면에 표시되는 한 판의 게임 결과. `RoundResolved`/`RoundFinalResult`(서버 이벤트)를
/// 조합해 room_provider가 만든다.
class GameResult {
  final String? category;
  final String realWord;
  final String liarWord;
  final bool citizensWin;

  /// 투표로 지목된 사람의 닉네임. 아무도 지목되지 않았으면 null.
  final String? accusedNickname;

  /// 지목된 사람이 실제 라이어였는지.
  final bool wasLiar;

  /// 실제 라이어의 닉네임. 투표 결과와 무관하게 항상 공개된다(시민이 오지목되면
  /// 역전승 단계 없이 바로 게임이 끝나 그 외엔 알 방법이 없으므로).
  final String liarNickname;

  /// 라이어가 역전승을 시도하며 입력한 답. 역전승 시도가 없었다면 null.
  final String? liarGuess;
  final bool? liarGuessCorrect;

  const GameResult({
    required this.category,
    required this.realWord,
    required this.liarWord,
    required this.citizensWin,
    required this.accusedNickname,
    required this.wasLiar,
    required this.liarNickname,
    this.liarGuess,
    this.liarGuessCorrect,
  });
}
