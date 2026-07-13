/// 내 전적. PLAN.md의 `GamePlay` 집계 파생 방식을 그대로 흉내 낸다 — 승률을 직접 저장하지
/// 않고, 라이어/시민으로 참여한 판수·승수만 들고 있다가 필요할 때 비율로 계산한다.
/// `GET /api/users/me` 응답 계약: `{ totalGames, overallWinRate, liarWinRate, citizenWinRate, level }`
/// (승률은 분모가 0이면 null = "기록 없음").
class UserStats {
  final int liarGames;
  final int liarWins;
  final int citizenGames;
  final int citizenWins;

  const UserStats({
    this.liarGames = 0,
    this.liarWins = 0,
    this.citizenGames = 0,
    this.citizenWins = 0,
  });

  int get totalGames => liarGames + citizenGames;
  int get totalWins => liarWins + citizenWins;

  double? get overallWinRate => totalGames == 0 ? null : totalWins / totalGames;
  double? get liarWinRate => liarGames == 0 ? null : liarWins / liarGames;
  double? get citizenWinRate => citizenGames == 0 ? null : citizenWins / citizenGames;

  /// PLAN.md: 별도 컬럼 없이 `count(plays)`(전체 게임수)에서 파생되는 구간제 레벨.
  /// 정확한 구간표는 문서에도 "추후 확정"으로 남아있어, 5게임당 1레벨로 임시 구현한다.
  int get level => 1 + totalGames ~/ 5;

  /// 아직 한 판도 하지 않은 신규 유저(게스트 로그인 직후 등).
  static const guest = UserStats();

  /// 로그인 회원 데모용 목데이터. 백엔드 연동 전까지 임시로 채워둔다.
  static const mockMember = UserStats(liarGames: 5, liarWins: 2, citizenGames: 7, citizenWins: 5);

  /// 방금 끝난 한 판을 반영한 새 전적을 돌려준다(`GamePlay` 1행 추가에 해당).
  UserStats recordGame({required bool won, required bool wasLiar}) {
    return UserStats(
      liarGames: liarGames + (wasLiar ? 1 : 0),
      liarWins: liarWins + (wasLiar && won ? 1 : 0),
      citizenGames: citizenGames + (wasLiar ? 0 : 1),
      citizenWins: citizenWins + (!wasLiar && won ? 1 : 0),
    );
  }
}
