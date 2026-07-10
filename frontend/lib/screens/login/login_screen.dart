import 'package:flutter/material.dart';

import '../../services/user_session.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/responsive_center.dart';
import '../../widgets/section_card.dart';
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 96),
        Icon(
          Icons.theater_comedy,
          size: 72,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          '라이어 게임',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'AI가 개입하는 라이어 게임에 오신 것을 환영합니다',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 40),
        AppButton(
          label: '로그인 / 회원가입',
          onPressed: () => setState(() => _showAuthOptions = true),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: '게스트로 계속하기',
          variant: AppButtonVariant.outlined,
          onPressed: _handleGuestContinue,
        ),
      ],
    );
  }

  Widget _buildAuthOptions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _showAuthOptions = false),
              icon: const Icon(Icons.arrow_back),
            ),
            Text('로그인 / 회원가입', style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '이메일로 로그인',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 16),
              AppButton(label: '로그인', onPressed: _handleEmailLogin),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _handleSignUp,
                  child: const Text('회원가입', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          child: _GoogleAuthButton(onPressed: _handleGoogleAuth),
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
