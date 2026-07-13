/// PLAN `round:resolved` 페이로드: `{ votedOutId, wasLiar, realWord, liarWord, liarId }`.
/// `liarId`는 투표 결과와 무관하게 항상 함께 온다 — 시민이 오지목되면 역전승 단계 없이
/// 바로 게임이 끝나 그 외엔 누가 라이어였는지 알 방법이 없기 때문.
class RoundResolved {
  final String? votedOutId;
  final bool wasLiar;
  final String realWord;
  final String liarWord;
  final String liarId;

  const RoundResolved({
    required this.votedOutId,
    required this.wasLiar,
    required this.realWord,
    required this.liarWord,
    required this.liarId,
  });

  factory RoundResolved.fromJson(Map<String, dynamic> json) {
    return RoundResolved(
      votedOutId: json['votedOutId'] as String?,
      wasLiar: json['wasLiar'] as bool,
      realWord: json['realWord'] as String,
      liarWord: json['liarWord'] as String,
      liarId: json['liarId'] as String,
    );
  }
}

/// PLAN `round:finalResult` 페이로드: `{ liarGuessCorrect, winner }`.
/// `liarGuessCorrect`는 역전승 시도 자체가 없었으면(라이어가 애초에 지목 안 됨) null.
class RoundFinalResult {
  final bool? liarGuessCorrect;
  final String winner; // 'liar' | 'citizens'

  const RoundFinalResult({required this.liarGuessCorrect, required this.winner});

  bool get citizensWin => winner == 'citizens';

  factory RoundFinalResult.fromJson(Map<String, dynamic> json) {
    return RoundFinalResult(
      liarGuessCorrect: json['liarGuessCorrect'] as bool?,
      winner: json['winner'] as String,
    );
  }
}
