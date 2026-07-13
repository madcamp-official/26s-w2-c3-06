import 'dart:typed_data';

/// 로그인에 사용한 방식. 이메일 가입 계정만 비밀번호 변경이 가능하다(PLAN.md 결정).
enum AuthProvider { guest, email, google }

/// 로그인 세션의 경량 클라이언트 캐시. 실제 인증은 Firebase Auth가, 전적/프로필은 백엔드가
/// 소유하고, 여기서는 화면 간에 닉네임/게스트 여부/프로필 사진(로컬 미리보기)만 공유한다.
/// (전적은 서버 파생값 myStatsProvider로 각 화면이 직접 조회한다.)
class UserSession {
  UserSession._();

  static String nickname = '게스트';
  static bool isGuest = true;
  static int avatarIndex = 0;
  static AuthProvider authProvider = AuthProvider.guest;

  /// 이번 세션에서 고른 프로필 사진(로컬 미리보기). 서버에는 Firebase Storage URL로 별도 저장된다.
  static Uint8List? profileImageBytes;

  static void signInAsGuest(String guestNickname) {
    nickname = guestNickname;
    isGuest = true;
    avatarIndex = 0;
    authProvider = AuthProvider.guest;
    profileImageBytes = null;
  }

  static void signInAsMember({required String nickname, AuthProvider provider = AuthProvider.email}) {
    UserSession.nickname = nickname;
    isGuest = false;
    avatarIndex = 0;
    authProvider = provider;
    profileImageBytes = null;
  }
}
