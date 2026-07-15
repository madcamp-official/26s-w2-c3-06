import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/pixel_font.dart';

import '../../api/backend_api.dart';
import '../../widgets/hover_tap.dart';
import '../../services/auth_service.dart';
import '../../services/user_session.dart';
import '../../state/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/pixel_box.dart';
import '../../widgets/pixel_dialog.dart';
import '../../widgets/responsive_center.dart';
import 'signup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  /// 게스트 프로필 화면에서 "로그인/회원가입"을 눌러 들어온 경우 true. 이때는 기존 게스트
  /// 세션을 로그아웃시키지 않고(뒤로가기 시 계속 게스트로 이용 가능하도록) 화면 위에 push되며,
  /// 초기 화면(로고+두 버튼)을 건너뛰고 바로 로그인 폼으로 진입하고, 성공 시 로비까지 pop한다.
  final bool pushedFromProfile;

  const LoginScreen({super.key, this.pushedFromProfile = false});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late bool _showAuthOptions;
  bool _showPassword = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _showAuthOptions = widget.pushedFromProfile;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 게스트 프로필에서 들어온 경우, 인증 성공 후 이 화면(및 그 위에 쌓인 SignUpScreen 등)을
  /// 전부 닫고 로비까지 돌아간다. 원래(비로그인) 경로로 들어온 경우엔 AuthGate가 반응형으로
  /// 알아서 전환하므로 아무것도 하지 않는다.
  void _afterAuthSuccess() {
    if (widget.pushedFromProfile && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  // 로그인 성공 후 화면 전환·세션 복원(닉네임/아바타/소켓)은 최상위 AuthGate가 인증 상태 변화를
  // 감지해 반응형으로 처리한다(main.dart). 이 화면은 인증만 수행한다.

  /// 인증 액션 공통 래퍼 — 중복 탭 방지, 에러 시 스낵바 표시.
  Future<void> _runAuth(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        showAppAlert(context, '인증 실패: ${e.message ?? e.code}');
      }
    } catch (e) {
      if (mounted) {
        showAppAlert(context, '오류: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleGuestContinue() async {
    final nicknameController = TextEditingController();
    final nickname = await showPixelDialog<String>(
      context: context,
      barrierDismissible: true,
      maxWidth: 300,
      padding: const EdgeInsets.all(24),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final canStart = nicknameController.text.trim().isNotEmpty;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('👤 게스트 플레이', style: PixelFont.title(fontSize: 10, color: AppColors.primary)),
                const SizedBox(height: 14),
                Text(
                  '사용할 닉네임을 입력하세요',
                  style: PixelFont.body(fontSize: 12, color: AppColors.mutedForeground),
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: nicknameController,
                  hintText: '닉네임',
                  onChanged: (_) => setDialogState(() {}),
                  onSubmitted: (value) {
                    final trimmed = value.trim();
                    if (trimmed.isEmpty) return;
                    Navigator.of(dialogContext).pop(trimmed);
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: '취소',
                        variant: AppButtonVariant.outlined,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: '시작 ▶',
                        onPressed: canStart ? () => Navigator.of(dialogContext).pop(nicknameController.text.trim()) : null,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
    // 다이얼로그의 pop() 직후에도 닫힘 애니메이션이 끝날 때까지 TextField(및 컨트롤러)가
    // 잠깐 더 화면에 남아있다. 여기서 바로 dispose()하면 "used after being disposed" 에러가
    // 나므로(게스트 로그인 시 발생하던 오류) 일부러 dispose를 호출하지 않는다.

    if (nickname == null || nickname.isEmpty) return;
    if (!mounted) return;
    await _runAuth(() async {
      // 닉네임 중복 사전 확인(공개 엔드포인트, 로그인 전에도 호출 가능).
      final available = await BackendApi.instance.isNicknameAvailable(nickname);
      if (!available) {
        if (mounted) {
          showAppAlert(context, '이미 사용 중인 닉네임입니다.');
        }
        return;
      }
      await AuthService.instance.signInAsGuest(nickname);
      // AuthGate가 Firebase의 후속 emit(updateDisplayName 반영)을 기다리는 동안 '플레이어'
      // 같은 임시값이 잠깐 보이지 않도록, 입력받은 닉네임을 여기서 바로 반영해둔다.
      UserSession.nickname = nickname;
      ref.read(nicknameProvider.notifier).set(nickname);
      // 익명 계정 생성 후 로컬 DB에 닉네임을 즉시 예약 — 서버 @unique 제약으로 권위 검증(409면 중복).
      try {
        await BackendApi.instance.syncNickname(nickname);
      } on BackendApiException catch (e) {
        await AuthService.instance.signOut();
        if (mounted) {
          showAppAlert(context, e.statusCode == 409 ? '이미 사용 중인 닉네임입니다.' : '닉네임 등록에 실패했습니다.');
        }
        return;
      }
      // 로그인 성공 → AuthGate가 감지해 로비로 전환하고 세션을 복원한다.
    });
  }

  void _handleEmailLogin() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      showAppAlert(context, '이메일과 비밀번호를 입력하세요.');
      return;
    }
    _runAuth(() async {
      await AuthService.instance.signInWithEmail(email: email, password: password);
      _afterAuthSuccess();
    });
  }

  void _handleSignUp() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SignUpScreen(pushedFromProfile: widget.pushedFromProfile)),
    );
  }

  void _handleGoogleAuth() {
    _runAuth(() async {
      final user = await AuthService.instance.signInOrLinkWithGoogle();
      // 이메일/게스트 가입과 동일하게, 로컬 DB User 행을 여기서 즉시 만들어 둔다. 이렇게 하지
      // 않으면 requireAuth의 토큰 클레임 폴백에만 의존하게 되는데, 그 클레임은 갱신이 늦을 수
      // 있어(캐시된 토큰) 첫 REST 요청까지 로컬 DB에 프로필이 없는 공백이 생길 수 있다.
      final nickname = user.displayName?.trim();
      if (nickname != null && nickname.isNotEmpty) {
        try {
          await BackendApi.instance.syncNickname(nickname);
        } catch (_) {
          // 실패해도 로그인 자체는 막지 않는다 — requireAuth 폴백이 뒤이어 채워준다.
        }
      }
      _afterAuthSuccess();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 게스트 프로필에서 들어온 경우에만 뒤로가기를 보여준다 — 누르면 로그아웃 없이 이
      // 라우트만 닫혀 원래 쓰던 게스트 계정으로 그대로 돌아간다(세션을 건드리지 않았으므로).
      appBar: widget.pushedFromProfile
          ? AppBar(
              leading: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
              ),
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ResponsiveCenter(
                    maxWidth: 400,
                    child: _showAuthOptions ? _buildAuthOptions(context) : _buildInitial(context),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInitial(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 64),
        Image.asset('images/logo.png', width: 280),
        const SizedBox(height: 36),
        AppButton(
          label: '🔑 로그인 / 회원가입',
          onPressed: () => setState(() => _showAuthOptions = true),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: '👤 게스트로 플레이',
          variant: AppButtonVariant.outlined,
          onPressed: _handleGuestContinue,
        ),
        const SizedBox(height: 24),
        Text(
          '© 2026 L-AI-R Game',
          textAlign: TextAlign.center,
          style: PixelFont.body(
            fontSize: 11,
            color: AppColors.mutedForeground,
          ).copyWith(fontFamilyFallback: const ['Noto Sans KR']),
        ),
      ],
    );
  }

  Widget _buildAuthOptions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        // 게스트 프로필에서 들어온 경우 AppBar 뒤로가기가 이미 있고, "홈으로"(게스트로 플레이
        // 화면)를 다시 보여주는 건 이미 게스트인 상태와 혼동을 주므로 숨긴다.
        if (!widget.pushedFromProfile)
          HoverTap(
            onTap: () => setState(() => _showAuthOptions = false),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.arrow_back, size: 14, color: AppColors.mutedForeground),
                const SizedBox(width: 6),
                Text(
                  '홈으로',
                  style: PixelFont.body(fontSize: 13, color: AppColors.mutedForeground),
                ),
              ],
            ),
          ),
        PixelBox(
          margin: const EdgeInsets.only(top: 24),
          padding: const EdgeInsets.only(top: 28, left: 28, right: 28, bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LOGIN', style: PixelFont.title(fontSize: 22, color: AppColors.foreground)),
              const SizedBox(height: 6),
              Text(
                '계속하려면 로그인하세요',
                style: PixelFont.body(fontSize: 13, color: AppColors.mutedForeground),
              ),
              const SizedBox(height: 24),
              _GoogleAuthButton(onPressed: _handleGoogleAuth),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Row(
                  children: [
                    Expanded(child: Container(height: 2, color: AppColors.border.withValues(alpha: 0.33))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '또는 이메일로',
                        style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground),
                      ),
                    ),
                    Expanded(child: Container(height: 2, color: AppColors.border.withValues(alpha: 0.33))),
                  ],
                ),
              ),
              AppTextField(
                controller: _emailController,
                hintText: '이메일 주소',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 10),
              AppTextField(
                controller: _passwordController,
                hintText: '비밀번호',
                obscureText: !_showPassword,
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, size: 18),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              const SizedBox(height: 18),
              AppButton(label: '로그인', onPressed: _handleEmailLogin),
              const SizedBox(height: 16),
              Center(
                child: HoverTap(
                  onTap: _handleSignUp,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '계정이 없으신가요? ',
                          style: PixelFont.body(fontSize: 12, color: AppColors.mutedForeground),
                        ),
                        TextSpan(
                          text: '회원가입',
                          style: PixelFont.body(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GoogleAuthButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _GoogleAuthButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return HoverTap(
      onTap: onPressed,
      child: PixelBox(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        color: AppColors.secondary,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('images/google_logo.png', width: 20, height: 20),
            const SizedBox(width: 10),
            Text('Google로 계속하기', style: PixelFont.body(fontSize: 13, color: AppColors.foreground)),
          ],
        ),
      ),
    );
  }
}
