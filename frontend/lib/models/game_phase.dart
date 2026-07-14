/// 서버가 소유하는 게임 페이즈 전이(PLAN "Socket.IO 이벤트 계약" 참고).
/// 서버는 phase 값을 직접 이벤트로 보내지 않고, 어떤 이벤트가 왔는지로 클라가 추론한다:
/// game:started → describing, (설명 종료 system 메시지 후) → discussion,
/// vote:started → voting, round:resolved → resolution, liar:guessPrompt(본인만) → liarGuess,
/// game:ended → waiting(대기)로 복귀.
enum GamePhase { waiting, describing, discussion, voting, resolution, liarGuess, ended }
