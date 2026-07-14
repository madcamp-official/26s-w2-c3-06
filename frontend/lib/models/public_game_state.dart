import 'player.dart';

/// room:rejoined의 currentGame.rounds[i]. 설명 한 바퀴에 제출된 설명(turns)만 담는다.
/// 순서·투표 판정 결과는 게임 단위라 PublicGameState에 있다.
class PublicRound {
  final List<Map<String, String>> turns;

  const PublicRound({required this.turns});

  factory PublicRound.fromJson(Map<String, dynamic> json) {
    return PublicRound(
      turns: (json['turns'] as List)
          .map((e) => Map<String, String>.from(e as Map))
          .toList(),
    );
  }
}

/// room:rejoined.currentGame 페이로드. 서버가 그 시점에 공개해도 되는 정보만 담겨 온다
/// (realWord/liarWord/liarId는 resolution 단계 이후에만 값이 채워짐).
/// playerOrder(설명 순서)와 투표 판정 결과는 게임 단위 필드다(votes 개별 내역은 서버 전용이라 오지 않음).
class PublicGameState {
  final int gameNumber;
  final String category;
  final int aiBotCount;
  final String phase; // 서버 GamePhase 원문 문자열 ('setup' 포함)
  final List<String> participantIds;
  final List<Player> participants;
  final String? realWord;
  final String? liarWord;
  final String? liarId;
  final List<String> playerOrder;
  final String? votedOutId;
  final bool? wasLiar;
  final String? liarGuess;
  final bool? liarGuessCorrect;
  final String? winner;
  final List<PublicRound> rounds;

  const PublicGameState({
    required this.gameNumber,
    required this.category,
    required this.aiBotCount,
    required this.phase,
    required this.participantIds,
    required this.participants,
    this.realWord,
    this.liarWord,
    this.liarId,
    required this.playerOrder,
    this.votedOutId,
    this.wasLiar,
    this.liarGuess,
    this.liarGuessCorrect,
    this.winner,
    required this.rounds,
  });

  PublicRound? get currentRound => rounds.isEmpty ? null : rounds.first;

  factory PublicGameState.fromJson(Map<String, dynamic> json) {
    return PublicGameState(
      gameNumber: json['gameNumber'] as int,
      category: json['category'] as String,
      aiBotCount: json['aiBotCount'] as int,
      phase: json['phase'] as String,
      participantIds: (json['participantIds'] as List).cast<String>(),
      participants: (json['participants'] as List)
          .map((e) => Player.fromJson(e as Map<String, dynamic>))
          .toList(),
      realWord: json['realWord'] as String?,
      liarWord: json['liarWord'] as String?,
      liarId: json['liarId'] as String?,
      playerOrder: (json['playerOrder'] as List).cast<String>(),
      votedOutId: json['votedOutId'] as String?,
      wasLiar: json['wasLiar'] as bool?,
      liarGuess: json['liarGuess'] as String?,
      liarGuessCorrect: json['liarGuessCorrect'] as bool?,
      winner: json['winner'] as String?,
      rounds: (json['rounds'] as List)
          .map((e) => PublicRound.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
