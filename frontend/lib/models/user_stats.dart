/// 내 전적. PLAN.md의 `GamePlay` 집계 파생 방식을 그대로 흉내 낸다 — 승률을 직접 저장하지
/// 않고, 라이어/시민으로 참여한 판수·승수만 들고 있다가 필요할 때 비율로 계산한다.
/// `GET /api/users/me` 응답 계약: `{ totalGames, overallWinRate, liarWinRate, citizenWinRate, level }`
/// (승률은 분모가 0이면 null = "기록 없음").
///
/// 레벨은 DB/모델에 직접 저장하지 않고 누적 [xp]만 저장한다 — 레벨은 항상 [xp]로부터
/// 계산되는 파생값이다(레벨 이름/칭호는 없음, 화면엔 숫자만 표시).
class UserStats {
  final int liarGames;
  final int liarWins;
  final int citizenGames;
  final int citizenWins;
  final int xp;

  const UserStats({
    this.liarGames = 0,
    this.liarWins = 0,
    this.citizenGames = 0,
    this.citizenWins = 0,
    this.xp = 0,
  });

  int get totalGames => liarGames + citizenGames;
  int get totalWins => liarWins + citizenWins;

  double? get overallWinRate => totalGames == 0 ? null : totalWins / totalGames;
  double? get liarWinRate => liarGames == 0 ? null : liarWins / liarGames;
  double? get citizenWinRate => citizenGames == 0 ? null : citizenWins / citizenGames;

  /// 누적 XP에서 계산되는 숫자 레벨(Lv.1부터 시작, 이름/칭호 없음).
  int get level => _levelForXp(xp);

  /// 아직 한 판도 하지 않은 신규 유저(게스트 로그인 직후 등).
  static const guest = UserStats();

  /// 로그인 회원 데모용 목데이터. 백엔드 연동 전까지 임시로 채워둔다.
  static const mockMember = UserStats(liarGames: 5, liarWins: 2, citizenGames: 7, citizenWins: 5, xp: 640);

  /// 방금 끝난 한 판을 반영한 새 전적을 돌려준다(`GamePlay` 1행 추가에 해당).
  /// XP 지급 규칙 — 사람 플레이어에게만: 승리 100 / 패배 60, 끝까지 완료 시 +10,
  /// 라이어가 역전승 단어 맞히기에 성공하면 +20. 한 게임당 한 번만 호출해야 중복 지급되지 않는다.
  UserStats recordGame({
    required bool won,
    required bool wasLiar,
    bool completedGame = true,
    bool liarComebackSuccess = false,
  }) {
    var gainedXp = won ? 100 : 60;
    if (completedGame) gainedXp += 10;
    if (wasLiar && liarComebackSuccess) gainedXp += 20;

    return UserStats(
      liarGames: liarGames + (wasLiar ? 1 : 0),
      liarWins: liarWins + (wasLiar && won ? 1 : 0),
      citizenGames: citizenGames + (wasLiar ? 0 : 1),
      citizenWins: citizenWins + (!wasLiar && won ? 1 : 0),
      xp: xp + gainedXp,
    );
  }
}

/// 레벨 L(1부터 시작)에 도달하는 데 필요한 누적 XP. Lv.1은 0.
/// "다음 레벨 필요 XP = 100 + (현재 레벨 - 1) × 30" 규칙을 누적한 닫힌 형태 —
/// Lv.20을 넘어서도 같은 규칙으로 무한히 이어진다.
int _xpThresholdForLevel(int level) {
  if (level <= 1) return 0;
  final n = level - 1;
  return 100 * n + 15 * n * (n - 1);
}

int _levelForXp(int xp) {
  var level = 1;
  while (_xpThresholdForLevel(level + 1) <= xp) {
    level++;
  }
  return level;
}
