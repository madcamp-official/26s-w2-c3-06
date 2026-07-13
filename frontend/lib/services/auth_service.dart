import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

/// PLAN "인증/유저 관리 흐름" 참고. Firebase Auth는 인증 전용 — 전적·친구 등 프로필 데이터는
/// 백엔드 로컬 DB가 관리한다(socket_service의 room:create/join에서 nickname을 매번 실어 보내면
/// 백엔드가 upsert). 닉네임 자체는 PLAN이 허용하는 두 저장 방식("Firebase displayName 또는
/// 자체 DB 프로필") 중 Firebase `displayName`을 클라이언트 측 캐시로 사용해, 재로그인 시
/// 매번 닉네임을 다시 입력하지 않아도 되게 한다.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// 현재 로그인된 유저의 Firebase ID 토큰. 소켓 handshake·REST Authorization 헤더에 사용.
  Future<String?> getIdToken({bool forceRefresh = false}) {
    return _auth.currentUser?.getIdToken(forceRefresh) ?? Future.value(null);
  }

  Future<User> signInAsGuest(String nickname) async {
    final result = await _auth.signInAnonymously();
    await result.user!.updateDisplayName(nickname);
    await result.user!.reload();
    return _auth.currentUser!;
  }

  /// 로그인 폼. 익명 승격이 아니라 완전히 별개 계정으로 로그인(기존 세션은 버림).
  Future<User> signInWithEmail({required String email, required String password}) async {
    final result = await _auth.signInWithEmailAndPassword(email: email, password: password);
    return result.user!;
  }

  /// 회원가입 폼. PLAN "통합 버튼 인증 로직": 익명 상태면 계정 승격(link)을 먼저 시도해
  /// UID를 유지하고, 이미 가입된 이메일이면 기존 계정으로 로그인 전환(이전 익명 계정 폐기).
  Future<User> signUpOrLinkWithEmail({
    required String email,
    required String password,
    required String nickname,
  }) async {
    final current = _auth.currentUser;
    User user;
    if (current != null && current.isAnonymous) {
      final credential = EmailAuthProvider.credential(email: email, password: password);
      try {
        final result = await current.linkWithCredential(credential);
        user = result.user!;
      } on FirebaseAuthException catch (e) {
        if (_isAlreadyInUse(e.code)) {
          final result = await _auth.signInWithEmailAndPassword(email: email, password: password);
          user = result.user!;
        } else {
          rethrow;
        }
      }
    } else {
      final result = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      user = result.user!;
    }
    await user.updateDisplayName(nickname);
    await user.reload();
    return _auth.currentUser!;
  }

  /// Google 로그인/가입 통합 버튼. 익명이면 link, 실패(이미 가입된 계정)면 기존 계정으로 전환.
  Future<User> signInOrLinkWithGoogle() async {
    final current = _auth.currentUser;

    if (kIsWeb) {
      final provider = GoogleAuthProvider();
      if (current != null && current.isAnonymous) {
        try {
          final result = await current.linkWithPopup(provider);
          return result.user!;
        } on FirebaseAuthException catch (e) {
          if (_isAlreadyInUse(e.code)) {
            final result = await _auth.signInWithPopup(provider);
            return result.user!;
          }
          rethrow;
        }
      }
      final result = await _auth.signInWithPopup(provider);
      return result.user!;
    }

    final credential = await _googleCredential();
    if (current != null && current.isAnonymous) {
      try {
        final result = await current.linkWithCredential(credential);
        return result.user!;
      } on FirebaseAuthException catch (e) {
        if (_isAlreadyInUse(e.code)) {
          final result = await _auth.signInWithCredential(credential);
          return result.user!;
        }
        rethrow;
      }
    }
    final result = await _auth.signInWithCredential(credential);
    return result.user!;
  }

  /// 완전히 로그아웃 — 메인 화면의 "게스트로 계속하기"와 동일한 새 익명 세션 시작 지점으로 복귀.
  Future<void> signOut() => _auth.signOut();

  Future<void> updateNickname(String nickname) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.updateDisplayName(nickname);
    await user.reload();
  }

  bool _isAlreadyInUse(String code) =>
      code == 'credential-already-in-use' || code == 'email-already-in-use';

  Future<OAuthCredential> _googleCredential() async {
    final googleSignIn = GoogleSignIn.instance;
    await googleSignIn.initialize();
    final account = await googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'Google ID 토큰을 가져오지 못했습니다.',
      );
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }
}
