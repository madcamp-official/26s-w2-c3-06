import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/backend_api.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/responsive_center.dart';

final _specialCharPattern = RegExp(r'''[!@#$%^&*(),.?":{}|<>_\-\[\]/\\;+=~`]''');
final _emailFormatPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

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
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool? _nicknameAvailable;
  bool _isCheckingNickname = false;

  // 사전 확인(닉네임 중복확인 버튼)이 "사용 가능"이라고 했더라도, 실제 가입 시도
  // (Firebase/백엔드)에서 뒤늦게 밝혀지는 진짜 중복이 있을 수 있다(레이스 컨디션,
  // 또는 이메일처럼 애초에 사전 확인이 불가능한 경우). 그 결과를 여기 담아 빨간 글씨로
  // 필드 바로 아래에 보여준다 — 회원가입 실패 팝업만 뜨고 "왜"인지 필드에는 안 보이던
  // 문제를 고친 것.
  String? _emailError;
  String? _nicknameError;

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
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
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
      showAppAlert(context, '닉네임 확인 중 오류가 발생했습니다.');
    }
  }

  bool get _canSubmit =>
      !_submitting &&
      _emailFormatPattern.hasMatch(_emailController.text.trim()) &&
      _nicknameAvailable == true &&
      _isPasswordValid(_passwordController.text) &&
      _confirmController.text == _passwordController.text;

  Future<void> _handleSignUp() async {
    if (!_canSubmit) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final nickname = _nicknameController.text.trim();
    setState(() {
      _submitting = true;
      _emailError = null;
      _nicknameError = null;
    });
    try {
      await AuthService.instance.signUpOrLinkWithEmail(
        email: email,
        password: password,
        nickname: nickname,
      );
      // 가입 직후 로컬 DB에 닉네임 즉시 반영(친구 요청 등이 바로 동작하도록).
      try {
        await BackendApi.instance.syncNickname(nickname);
      } on BackendApiException catch (e) {
        // Firebase 계정은 이미 만들어졌다 — 그 사이 다른 사람이 닉네임을 선점한 경우
        // (사전 확인 이후의 레이스 컨디션)만 여기서 걸린다. 계정은 유지한 채 닉네임만
        // 다시 고르게 한다(다음 저장 시도는 프로필 화면에서 가능).
        if (mounted) {
          setState(() {
            _nicknameError = e.statusCode == 409 ? '이미 사용 중인 닉네임입니다.' : '닉네임 저장에 실패했습니다: ${e.message}';
          });
        }
        return;
      }
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
      if (!mounted) return;
      if (e.code == 'email-already-in-use') {
        setState(() => _emailError = '이미 가입된 이메일입니다.');
      } else {
        showAppAlert(context, '가입 실패: ${e.message ?? e.code}');
      }
    } catch (e) {
      if (mounted) {
        showAppAlert(context, '오류: $e');
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
                  AppTextField(
                    controller: _emailController,
                    label: '이메일',
                    hintText: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setState(() => _emailError = null),
                  ),
                  if (_emailError != null) _InlineError(_emailError!),
                  const SizedBox(height: 16),
                  _CheckableField(
                    controller: _nicknameController,
                    label: '닉네임',
                    hintText: '게임에서 사용할 닉네임',
                    isChecking: _isCheckingNickname,
                    available: _nicknameAvailable,
                    onCheck: _checkNickname,
                    onChanged: () => setState(() {
                      _nicknameAvailable = null;
                      _nicknameError = null;
                    }),
                  ),
                  if (_nicknameError != null) _InlineError(_nicknameError!),
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

/// 필드 바로 아래 빨간 글씨로 붙는 에러 한 줄(가입 시도에서 뒤늦게 밝혀진 중복 등).
class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError(this.message);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Icon(Icons.cancel, size: 14, color: AppColors.error),
          const SizedBox(width: 4),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 12, color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _CheckableField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hintText;
  final bool isChecking;
  final bool? available;
  final VoidCallback onCheck;
  final VoidCallback onChanged;

  const _CheckableField({
    required this.controller,
    required this.label,
    required this.hintText,
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
