import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/pixel_font.dart';

import '../../services/auth_service.dart';
import '../../services/user_session.dart';
import '../../state/auth_provider.dart';
import '../../state/room_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/pixel_box.dart';
import '../../widgets/pixel_dialog.dart';
import '../../widgets/responsive_center.dart';
import '../lobby/lobby_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showAuthOptions = false;
  bool _showPassword = false;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _enterApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LobbyScreen()),
    );
  }

  /// 로그인/가입 성공 직후 공통 처리: 닉네임 확정, 소켓 연결(ID 토큰 handshake), 로비 진입.
  /// 전적(UserStats)은 로비/프로필 화면이 백엔드에서 직접 조회하므로 여기서 다루지 않는다.
  Future<void> _afterAuth(User user, {required bool isGuest}) async {
    final nickname = (user.displayName?.trim().isNotEmpty ?? false) ? user.displayName!.trim() : '플레이어';
    if (isGuest) {
      UserSession.signInAsGuest(nickname);
    } else {
      UserSession.signInAsMember(nickname: nickname);
    }
    ref.read(nicknameProvider.notifier).set(nickname);
    final token = await AuthService.instance.getIdToken();
    if (token != null) ref.read(roomProvider.notifier).connect(token);
    if (!mounted) return;
    _enterApp();
  }

  /// 인증 액션 공통 래퍼 — 중복 탭 방지, 에러 시 스낵바 표시.
  Future<void> _runAuth(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('인증 실패: ${e.message ?? e.code}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
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
                  hintText: '닉네임 (최대 8자)',
                  maxLength: 8,
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
      final user = await AuthService.instance.signInAsGuest(nickname);
      await _afterAuth(user, isGuest: true);
    });
  }

  void _handleEmailLogin() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일과 비밀번호를 입력하세요.')),
      );
      return;
    }
    _runAuth(() async {
      final user = await AuthService.instance.signInWithEmail(email: email, password: password);
      await _afterAuth(user, isGuest: false);
    });
  }

  void _handleSignUp() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignUpScreen()),
    );
  }

  void _handleGoogleAuth() {
    _runAuth(() async {
      final user = await AuthService.instance.signInOrLinkWithGoogle();
      await _afterAuth(user, isGuest: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: ResponsiveCenter(
            maxWidth: 400,
            child: _showAuthOptions ? _buildAuthOptions(context) : _buildInitial(context),
          ),
        ),
      ),
    );
  }

  Widget _buildInitial(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 96),
        const Text('🤖', textAlign: TextAlign.center, style: TextStyle(fontSize: 72, height: 1)),
        const SizedBox(height: 8),
        Text(
          'AI LIAR',
          textAlign: TextAlign.center,
          style: PixelFont.title(fontSize: 18, color: AppColors.primary, letterSpacing: 2),
        ),
        Text(
          'GAME',
          textAlign: TextAlign.center,
          style: PixelFont.title(fontSize: 18, color: AppColors.foreground, letterSpacing: 2),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '🕵️ AI가 제시어를 만들고, 우리가 라이어를 찾는\n실시간 소셜 파티게임',
            textAlign: TextAlign.center,
            style: PixelFont.body(
              fontSize: 13,
              height: 1.7,
              color: AppColors.mutedForeground,
            ).copyWith(fontFamilyFallback: const ['Noto Sans KR']),
          ),
        ),
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
          '© 2025 AI Liar Game',
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
        GestureDetector(
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
              Text('LOGIN', style: PixelFont.title(fontSize: 13, color: AppColors.foreground)),
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
                child: GestureDetector(
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
    return GestureDetector(
      onTap: onPressed,
      child: PixelBox(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        color: AppColors.secondary,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('G', style: PixelFont.title(fontSize: 18, color: AppColors.google)),
            const SizedBox(width: 10),
            Text('Google로 계속하기', style: PixelFont.body(fontSize: 13, color: AppColors.foreground)),
          ],
        ),
      ),
    );
  }
}
