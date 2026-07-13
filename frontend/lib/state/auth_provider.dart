import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService.instance);

/// 현재 Firebase 로그인 상태. null이면 로그인/게스트 세션 모두 없는 상태(메인 화면으로).
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// 현재 유저가 게스트(익명)인지 여부. 로그인 안 된 상태에서는 false를 반환한다
/// (화면 쪽에서 authStateProvider의 null 여부로 "비로그인"을 먼저 구분해야 함).
final isGuestProvider = Provider<bool>((ref) {
  final user = ref.watch(authStateProvider).value;
  return user?.isAnonymous ?? false;
});

class NicknameNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

/// 로그인/가입 흐름에서 확정된 닉네임. room:create/join 등 소켓 이벤트에 실어 보낼 때 쓴다.
/// Firebase `displayName`을 세션 시작 시 이 값으로 미러링해, 재로그인해도 다시 물어보지 않는다.
final nicknameProvider = NotifierProvider<NicknameNotifier, String?>(NicknameNotifier.new);

class AvatarUrlNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

/// 업로드한 프로필 사진의 Firebase Storage 다운로드 URL. null이면 기본 아이콘을 쓴다.
final avatarUrlProvider = NotifierProvider<AvatarUrlNotifier, String?>(AvatarUrlNotifier.new);
