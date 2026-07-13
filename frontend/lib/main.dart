import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/backend_api.dart';
import 'firebase_options.dart';
import 'screens/lobby/lobby_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/room/room_screen.dart';
import 'services/auth_service.dart';
import 'services/room_session_store.dart';
import 'services/user_session.dart';
import 'state/auth_provider.dart';
import 'state/room_provider.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '라이어 게임',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AuthGate(),
    );
  }
}

/// 최상위 라우팅을 Firebase 로그인 상태로 결정한다(PLAN "인증/유저 관리 흐름").
/// 로그인/로그아웃 화면 전환을 여기서 반응형으로 처리하므로 개별 화면은 수동 내비게이션 없이
/// 인증만 수행하면 된다. 새로고침(웹) 시에도 Firebase 세션이 복원되면 로그인 화면을 건너뛴다.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _restoredForUser = false;

  /// 로그인된 세션을 앱 상태에 반영: 닉네임/아바타 복원, 소켓 연결(ID 토큰 handshake).
  Future<void> _restoreSession(User user) async {
    final nickname =
        (user.displayName?.trim().isNotEmpty ?? false) ? user.displayName!.trim() : '플레이어';
    if (user.isAnonymous) {
      UserSession.signInAsGuest(nickname);
    } else {
      UserSession.signInAsMember(nickname: nickname);
    }
    ref.read(nicknameProvider.notifier).set(nickname);
    final token = await AuthService.instance.getIdToken();
    if (token != null) ref.read(roomProvider.notifier).connect(token);
    try {
      final profile = await BackendApi.instance.getMyProfile();
      ref.read(avatarUrlProvider.notifier).set(profile.avatarUrl);
    } catch (_) {
      // 오프라인 등으로 프로필 조회 실패해도 로그인 자체는 막지 않는다.
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const _Loading(),
      error: (_, __) => const LoginScreen(),
      data: (user) {
        if (user == null) {
          _restoredForUser = false;
          return const LoginScreen();
        }
        if (!_restoredForUser) {
          _restoredForUser = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession(user));
        }
        return const _HomeGate();
      },
    );
  }
}

/// 로그인 후 홈. 저장된 방 코드가 있으면(새로고침 전에 방에 있었음) 소켓 연결 직후 재입장을 시도하고,
/// 없으면 로비를 보여준다. RoomScreen은 항상 로비 위에 push되는 라우트로 유지해 나가기 동작을 일관되게 한다.
class _HomeGate extends ConsumerStatefulWidget {
  const _HomeGate();

  @override
  ConsumerState<_HomeGate> createState() => _HomeGateState();
}

class _HomeGateState extends ConsumerState<_HomeGate> {
  @override
  void initState() {
    super.initState();
    _maybeRejoin();
  }

  Future<void> _maybeRejoin() async {
    final code = await RoomSessionStore.instance.readRoomCode();
    if (code == null || !mounted) return;
    // 소켓이 연결될 때까지 잠깐 기다렸다가 재입장 요청.
    var waited = 0;
    while (mounted && !ref.read(roomProvider).socketConnected && waited < 5000) {
      await Future.delayed(const Duration(milliseconds: 150));
      waited += 150;
    }
    if (!mounted || !ref.read(roomProvider).socketConnected) return;
    ref.read(roomProvider.notifier).rejoinRoom(roomCode: code);
    if (!mounted) return;
    // 재입장 성공(roomCode 채워짐)/실패(room:error)는 RoomScreen과 방 이벤트가 처리한다.
    Navigator.of(context).push(MaterialPageRoute(
      settings: const RouteSettings(name: 'room'),
      builder: (_) => const RoomScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return const LobbyScreen();
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
