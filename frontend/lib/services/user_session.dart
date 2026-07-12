import 'dart:typed_data';

/// 로그인에 사용한 방식. 이메일 가입 계정만 비밀번호 변경이 가능하다(PLAN.md 결정).
enum AuthProvider { guest, email, google }

/// 로그인 상태를 흉내 내는 간단한 전역 세션 정보.
/// 백엔드 연동 전까지 화면 간에 닉네임/아바타/게스트 여부를 공유하기 위한 용도로만 쓴다.
class UserSession {
  UserSession._();

  static String nickname = '게스트';
  static bool isGuest = true;
  static int avatarIndex = 0;
  static AuthProvider authProvider = AuthProvider.guest;

  /// 실제로 첨부한 프로필 사진. null이면 [avatarIndex] 기반 기본 아이콘을 대신 보여준다.
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
