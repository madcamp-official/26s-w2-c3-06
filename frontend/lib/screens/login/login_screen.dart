import 'package:flutter/material.dart';
import '../../theme/pixel_font.dart';

import '../../services/user_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/pixel_box.dart';
import '../../widgets/pixel_dialog.dart';
import '../../widgets/responsive_center.dart';
import '../lobby/lobby_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showAuthOptions = false;
  bool _showPassword = false;

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
    nicknameController.dispose();

    if (nickname == null || nickname.isEmpty) return;
    if (!mounted) return;
    UserSession.signInAsGuest(nickname);
    _enterApp();
  }

  void _handleEmailLogin() {
    UserSession.signInAsMember(nickname: '이메일 사용자');
    _enterApp();
  }

  void _handleSignUp() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignUpScreen()),
    );
  }

  void _handleGoogleAuth() {
    UserSession.signInAsMember(nickname: 'Google 사용자', provider: AuthProvider.google);
    _enterApp();
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
