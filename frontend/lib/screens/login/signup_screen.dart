import 'package:flutter/material.dart';

import '../../mock/mock_data.dart';
import '../../services/user_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/responsive_center.dart';
import '../lobby/lobby_screen.dart';

final _specialCharPattern = RegExp(r'''[!@#$%^&*(),.?":{}|<>_\-\[\]/\\;+=~`]''');

bool _isPasswordValid(String password) {
  return password.length >= 8 &&
      RegExp(r'[A-Za-z]').hasMatch(password) &&
      RegExp(r'\d').hasMatch(password) &&
      _specialCharPattern.hasMatch(password);
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _userIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool? _emailAvailable;
  bool? _nicknameAvailable;
  bool? _userIdAvailable;
  bool _isCheckingEmail = false;
  bool _isCheckingNickname = false;
  bool _isCheckingUserId = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nicknameController.dispose();
    _userIdController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _checkEmail() async {
    final value = _emailController.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _isCheckingEmail = true;
      _emailAvailable = null;
    });
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final taken = mockTakenEmails.any((e) => e.toLowerCase() == value.toLowerCase());
    setState(() {
      _isCheckingEmail = false;
      _emailAvailable = !taken;
    });
  }

  Future<void> _checkNickname() async {
    final value = _nicknameController.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _isCheckingNickname = true;
      _nicknameAvailable = null;
    });
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final taken = mockTakenNicknames.any((n) => n == value);
    setState(() {
      _isCheckingNickname = false;
      _nicknameAvailable = !taken;
    });
  }

  Future<void> _checkUserId() async {
    final value = _userIdController.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _isCheckingUserId = true;
      _userIdAvailable = null;
    });
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final taken = mockTakenUserIds.any((id) => id.toLowerCase() == value.toLowerCase());
    setState(() {
      _isCheckingUserId = false;
      _userIdAvailable = !taken;
    });
  }

  bool get _canSubmit =>
      _emailAvailable == true &&
      _nicknameAvailable == true &&
      _userIdAvailable == true &&
      _isPasswordValid(_passwordController.text) &&
      _confirmController.text == _passwordController.text;

  void _handleSignUp() {
    if (!_canSubmit) return;
    UserSession.signInAsMember(nickname: _nicknameController.text.trim());
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LobbyScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ResponsiveCenter(
            maxWidth: 440,
            child: Card(
              child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Text('계정 만들기', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 24),
                  _CheckableField(
                    controller: _emailController,
                    label: '이메일',
                    hintText: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    isChecking: _isCheckingEmail,
                    available: _emailAvailable,
                    onCheck: _checkEmail,
                    onChanged: () => setState(() => _emailAvailable = null),
                  ),
                  const SizedBox(height: 16),
                  _CheckableField(
                    controller: _nicknameController,
                    label: '닉네임',
                    hintText: '게임에서 사용할 닉네임',
                    isChecking: _isCheckingNickname,
                    available: _nicknameAvailable,
                    onCheck: _checkNickname,
                    onChanged: () => setState(() => _nicknameAvailable = null),
                  ),
                  const SizedBox(height: 16),
                  _CheckableField(
                    controller: _userIdController,
                    label: '아이디',
                    hintText: '로그인에 사용할 아이디',
                    isChecking: _isCheckingUserId,
                    available: _userIdAvailable,
                    onCheck: _checkUserId,
                    onChanged: () => setState(() => _userIdAvailable = null),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _passwordController,
                    label: '비밀번호',
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '영문, 숫자, 특수문자를 포함해 8자 이상 입력하세요',
                      style: TextStyle(
                        fontSize: 12,
                        color: password.isEmpty
                            ? AppColors.textSecondary
                            : (_isPasswordValid(password)
                                ? AppColors.success
                                : AppColors.error),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _confirmController,
                    label: '비밀번호 확인',
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (confirm.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        confirm == password ? '비밀번호가 일치합니다' : '비밀번호가 일치하지 않습니다',
                        style: TextStyle(
                          fontSize: 12,
                          color: confirm == password ? AppColors.success : AppColors.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  AppButton(
                    label: '가입하기',
                    onPressed: _canSubmit ? _handleSignUp : null,
                  ),
                ],
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckableField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final TextInputType keyboardType;
  final bool isChecking;
  final bool? available;
  final VoidCallback onCheck;
  final VoidCallback onChanged;

  const _CheckableField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.keyboardType = TextInputType.text,
    required this.isChecking,
    required this.available,
    required this.onCheck,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                controller: controller,
                label: label,
                hintText: hintText,
                keyboardType: keyboardType,
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              label: isChecking ? '확인 중' : '중복 확인',
              fullWidth: false,
              variant: AppButtonVariant.outlined,
              onPressed: isChecking ? null : onCheck,
            ),
          ],
        ),
        if (available != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(
                  available! ? Icons.check_circle : Icons.cancel,
                  size: 14,
                  color: available! ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 4),
                Text(
                  available! ? '사용 가능합니다' : '이미 사용 중입니다',
                  style: TextStyle(
                    fontSize: 12,
                    color: available! ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
