/// 백엔드 접속 주소. 기본값은 배포된 백엔드(https://l-ai-r-game.madcamp-kaist.org)이다.
/// 로컬 개발 중에는 `--dart-define=BACKEND_URL=http://localhost:3000`으로 덮어쓴다.
/// 안드로이드 에뮬레이터에서 로컬 백엔드를 쓰려면 10.0.2.2로 바꿔야 한다.
class BackendConfig {
  BackendConfig._();

  static const String httpBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://l-ai-r-game.madcamp-kaist.org',
  );

  static const String socketUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://l-ai-r-game.madcamp-kaist.org',
  );
}
