import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/backend_api.dart';
import '../../mock/mock_data.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/responsive_center.dart';

final _specialCharPattern = RegExp(r'''[!@#$%^&*(),.?":{}|<>_\-\[\]/\\;+=~`]''');

bool _isPasswordValid(String password) {
  return password.length >= 8 &&
      RegExp(r'[A-Za-z]').hasMatch(password) &&
      RegExp(r'\d').hasMatch(password) &&
      _specialCharPattern.hasMatch(password);
}

class SignUpScreen extends ConsumerStatefulWidget {
  /// 게스트 프로필 화면에서 로그인/회원가입으로 들어온 경우 true. 이 경우 가입 성공 시
  /// 이 화면 하나만 닫는 게 아니라, 그 위에 쌓인 LoginScreen까지 함께 닫아 로비로 바로 보낸다.
  final bool pushedFromProfile;

  const SignUpScreen({super.key, this.pushedFromProfile = false});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  bool _submitting = false;
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
  void initState() {
    super.initState();
    // 익명(게스트) 상태에서 회원가입으로 승격하는 경우, 기존 게스트 닉네임을 입력창에 미리 채워
    // 그대로 이어받게 한다. 본인의 현재 닉네임이라 중복확인을 통과한 것으로 간주한다
    // (백엔드 PUT /me가 self uid를 제외하므로 같은 닉네임 유지가 가능).
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.isAnonymous) {
      final guestNickname = user.displayName?.trim() ?? '';
      if (guestNickname.isNotEmpty) {
        _nicknameController.text = guestNickname;
        _nicknameAvailable = true;
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nicknameController.dispose();
    _userIdController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // [MOCK] 백엔드에 이메일 사전 중복확인 엔드포인트가 없다(가입 시 Firebase가 email-already-in-use로
  // 처리). 형식 확인 + mock 목록 대조만 하며, 최종 판정은 _handleSignUp의 가입 시도에서 이뤄진다.
  Future<void> _checkEmail() async {
    final value = _emailController.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _isCheckingEmail = true;
      _emailAvailable = null;
    });
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    final taken = mockTakenEmails.any((e) => e.toLowerCase() == value.toLowerCase());
    setState(() {
      _isCheckingEmail = false;
      _emailAvailable = !taken;
    });
  }

  // 닉네임 중복확인 — 백엔드 GET /api/users/nickname-availability 실연동.
  Future<void> _checkNickname() async {
    final value = _nicknameController.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _isCheckingNickname = true;
      _nicknameAvailable = null;
    });
    try {
      final available = await BackendApi.instance.isNicknameAvailable(value);
      if (!mounted) return;
      setState(() {
        _isCheckingNickname = false;
        _nicknameAvailable = available;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isCheckingNickname = false;
        _nicknameAvailable = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('닉네임 확인 중 오류가 발생했습니다.')),
      );
    }
  }

  // [MOCK] 백엔드는 별도 아이디(userId) 개념이 없다(인증은 이메일+비밀번호, 표시명은 닉네임).
  // 이 필드/중복확인은 UI 데모용 mock이며 서버로 전송되지 않는다.
  Future<void> _checkUserId() async {
    final value = _userIdController.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _isCheckingUserId = true;
      _userIdAvailable = null;
    });
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    final taken = mockTakenUserIds.any((id) => id.toLowerCase() == value.toLowerCase());
    setState(() {
      _isCheckingUserId = false;
      _userIdAvailable = !taken;
    });
  }

  bool get _canSubmit =>
      !_submitting &&
      _emailAvailable == true &&
      _nicknameAvailable == true &&
      _userIdAvailable == true &&
      _isPasswordValid(_passwordController.text) &&
      _confirmController.text == _passwordController.text;

  Future<void> _handleSignUp() async {
    if (!_canSubmit) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final nickname = _nicknameController.text.trim();
    setState(() => _submitting = true);
    try {
      await AuthService.instance.signUpOrLinkWithEmail(
        email: email,
        password: password,
        nickname: nickname,
      );
      // 가입 직후 로컬 DB에 닉네임 즉시 반영(친구 요청 등이 바로 동작하도록).
      await BackendApi.instance.syncNickname(nickname);
      if (!mounted) return;
      // 로그인 상태가 됐으므로 최상위 AuthGate가 로비로 전환·세션 복원한다.
      if (widget.pushedFromProfile) {
        // 게스트 프로필 위에 LoginScreen→SignUpScreen 순으로 쌓여 있으므로, 전부 닫고
        // 맨 아래(로비)로 돌아간다 — 안 그러면 갱신된 로비가 가려진 채 남는다.
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('가입 실패: ${e.message ?? e.code}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
