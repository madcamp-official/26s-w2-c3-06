/// 로그인 상태를 흉내 내는 간단한 전역 세션 정보.
/// 백엔드 연동 전까지 화면 간에 닉네임/아바타/게스트 여부를 공유하기 위한 용도로만 쓴다.
class UserSession {
  UserSession._();

  static String nickname = '게스트';
  static bool isGuest = true;
  static int avatarIndex = 0;

  static void signInAsGuest(String guestNickname) {
    nickname = guestNickname;
    isGuest = true;
    avatarIndex = 0;
  }

  static void signInAsMember({required String nickname}) {
    UserSession.nickname = nickname;
    isGuest = false;
    avatarIndex = 0;
  }
}
