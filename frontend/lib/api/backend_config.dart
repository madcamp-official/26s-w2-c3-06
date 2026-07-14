import 'package:flutter/foundation.dart' show kIsWeb;

/// 백엔드 접속 주소.
///
/// 배포 환경에서는 백엔드가 프론트 정적 파일을 같은 origin으로 서빙하므로(PLAN
/// "배포 및 DB 운영"), 웹에서는 별도 주입 없이 현재 페이지의 origin(`Uri.base.origin`)을
/// 그대로 쓴다 — 이래야 Railway 기본 도메인·커스텀 도메인 등 어떤 주소로 접속해도
/// 항상 자기 자신을 호출한다. `--dart-define=BACKEND_URL=https://...`로 명시적으로
/// 주입하면 그 값이 우선한다(예: 프론트/백엔드를 분리 배포하는 경우).
///
/// 웹이 아닌 플랫폼(안드로이드 에뮬레이터 등 로컬 개발)은 origin 개념이 없어 기존처럼
/// localhost:3000을 기본값으로 쓴다. 안드로이드 에뮬레이터에서 로컬 백엔드를 쓰려면
/// 10.0.2.2로 바꿔야 한다.
class BackendConfig {
  BackendConfig._();

  static const String _override = String.fromEnvironment('BACKEND_URL');

  static String get httpBaseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return Uri.base.origin;
    return 'http://localhost:3000';
  }

  static String get socketUrl => httpBaseUrl;
}
