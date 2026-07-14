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
import 'services/socket_service.dart';
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
    // Firebase의 익명 로그인은 signInAnonymously() 직후 displayName이 아직 비어있는 상태로
    // 한 번 emit되고, updateDisplayName()+reload()가 끝난 뒤 다시 emit된다. 이 첫 emit에서
    // 무작정 '플레이어'로 덮어쓰면 실제 닉네임이 반영되기 전까지 잠깐 오표시된다 — 이미
    // 알고 있는 값(직접 입력 흐름에서 미리 세팅해둔 UserSession.nickname)이 있으면 그걸 쓴다.
    final displayName = user.displayName?.trim();
    final nickname = (displayName != null && displayName.isNotEmpty) ? displayName : UserSession.nickname;
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
          // 로그아웃해도 소켓 연결 자체는 끊기지 않아, 서버 프레젠스(presence.ts)가 계속
          // 이 uid를 온라인으로 취급해 친구 목록에서 오프라인으로 안 바뀌는 문제가 있었다.
          // authStateChanges가 null을 emit하는 시점(=signOut 직후)에 명시적으로 끊어준다.
          if (_restoredForUser) {
            // build() 도중 다른 provider(roomProvider) 상태를 바로 바꾸면 안 되므로
            // ("Tried to modify a provider while the widget tree was building"),
            // 다음 프레임으로 미룬다.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(roomProvider.notifier).disconnectSocket();
            });
          }
          _restoredForUser = false;
          return const LoginScreen();
        }
        // 닉네임은 매 emit마다 최신화한다(아바타/소켓 재설정은 하지 않음). 게스트 생성 직후엔
        // displayName이 아직 비어 있는 emit이 먼저 오고, updateDisplayName이 끝나 재emit되면
        // 그때 실제 닉네임이 온다 — 빈 값으로 오는 emit은 무시해 이미 알고 있는(직접 입력
        // 흐름에서 미리 세팅해둔) 닉네임을 '플레이어'로 덮어쓰지 않는다.
        final displayName = user.displayName?.trim();
        if (displayName != null && displayName.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            UserSession.nickname = displayName;
            ref.read(nicknameProvider.notifier).set(displayName);
          });
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
    // 이 대기 중에 사용자가 이미 로비에서 직접 방을 만들었거나 들어갔으면(roomCode가 이미
    // 채워짐), 오래된 저장 코드로 재입장을 시도해 그 상태를 덮어쓰지 않고 조용히 포기한다.
    if (ref.read(roomProvider).roomCode != null) return;

    // 재입장의 성공/실패를 실제로 기다린 뒤에만 화면을 전환한다. 이전엔 결과를 기다리지 않고
    // 곧바로 RoomScreen을 push했는데, room:error(예: 이미 삭제된 방) 응답을 아무도 구독하지
    // 않아 실패해도 빈 상태의 RoomScreen에 그대로 갇히는 문제가 있었다.
    final socket = SocketService.instance;
    final resultFuture = Future.any<bool>([
      socket.onRoomRejoined.first.then((_) => true),
      socket.onRoomError.first.then((_) => false),
    ]).timeout(const Duration(seconds: 8), onTimeout: () => false);
    ref.read(roomProvider.notifier).rejoinRoom(roomCode: code);
    final result = await resultFuture;

    if (!result) {
      await RoomSessionStore.instance.clear();
      return;
    }
    if (!mounted) return;
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
