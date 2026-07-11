import 'package:flutter/material.dart';

import '../../services/user_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
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
    final nickname = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('게스트 닉네임'),
          content: AppTextField(
            controller: nicknameController,
            label: '닉네임',
            hintText: '사용할 닉네임을 입력하세요',
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(nicknameController.text.trim()),
              child: const Text('입장'),
            ),
          ],
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
    UserSession.signInAsMember(nickname: 'Google 사용자');
    _enterApp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _DecorBlob(alignment: Alignment.topLeft, color: AppColors.decorBlobPurple),
          const _DecorBlob(alignment: Alignment.bottomRight, color: AppColors.decorBlobPeach),
          SafeArea(
            child: SingleChildScrollView(
              child: ResponsiveCenter(
                maxWidth: 400,
                child: _showAuthOptions ? _buildAuthOptions(context) : _buildInitial(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitial(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 96),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.theater_comedy, size: 40, color: Colors.white),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '라이어게임',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'AI가 개입하는 라이어 게임에 오신 것을 환영합니다',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 40),
        AppButton(
          label: '이메일로 시작하기',
          onPressed: () => setState(() => _showAuthOptions = true),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _handleGuestContinue,
            child: const Text('게스트로 계속하기'),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthOptions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        IconButton(
          onPressed: () => setState(() => _showAuthOptions = false),
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text('라이어게임', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  '로그인하고 게임을 시작하세요',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 24),
              _GoogleAuthButton(onPressed: _handleGoogleAuth),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('또는', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 20),
              AppTextField(
                controller: _emailController,
                label: '이메일',
                hintText: 'you@example.com',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _passwordController,
                label: '비밀번호',
                obscureText: true,
              ),
              const SizedBox(height: 20),
              AppButton(label: '로그인', onPressed: _handleEmailLogin),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: _handleSignUp,
                  child: const Text('계정이 없으신가요? 회원가입'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 메인/로그인 화면 배경에 깔리는 흐릿한 장식용 원.
class _DecorBlob extends StatelessWidget {
  final AlignmentGeometry alignment;
  final Color color;

  const _DecorBlob({required this.alignment, required this.color});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 220,
        height: 220,
        margin: const EdgeInsets.all(-60),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _GoogleAuthButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _GoogleAuthButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black87,
          side: BorderSide(color: Colors.grey.shade300),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 10,
              backgroundColor: Color(0xFF4285F4),
              child: Text('G', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            const Text('Google로 로그인 / 회원가입'),
          ],
        ),
      ),
    );
  }
}
