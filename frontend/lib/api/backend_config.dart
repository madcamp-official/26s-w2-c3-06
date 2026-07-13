/// 백엔드 접속 주소. 로컬 개발 기본값은 Flutter Web 기준 localhost:3000.
/// 안드로이드 에뮬레이터에서 로컬 백엔드를 쓰려면 10.0.2.2로 바꿔야 한다.
/// 배포 시에는 `--dart-define=BACKEND_URL=https://...`로 주입한다(PLAN "배포 및 DB 운영":
/// 백엔드+프론트가 Railway 단일 서비스로 통합 배포되므로 실제로는 same-origin이라 무관해질 수 있음).
class BackendConfig {
  BackendConfig._();

  static const String httpBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const String socketUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:3000',
  );
}
