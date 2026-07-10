import 'package:flutter/material.dart';

import '../../services/user_session.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/responsive_center.dart';
import '../../widgets/section_card.dart';
import '../../widgets/user_avatar.dart';
import '../login/login_screen.dart';

/// 프로필 사진/닉네임/비밀번호를 수정하는 화면.
/// 게스트는 닉네임/사진만 바꿀 수 있고, 대신 계정을 만들 수 있는 진입점을 제공한다.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nicknameController;
  final _passwordController = TextEditingController();
  late int _avatarIndex;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: UserSession.nickname);
    _avatarIndex = UserSession.avatarIndex;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;
    UserSession.nickname = nickname;
    UserSession.avatarIndex = _avatarIndex;
    Navigator.of(context).pop();
  }

  void _goToLoginScreen() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = UserSession.isGuest;
    return Scaffold(
      appBar: AppBar(title: const Text('프로필 수정')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ResponsiveCenter(
            maxWidth: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: UserAvatar(avatarIndex: _avatarIndex, radius: 44)),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(avatarOptions.length, (index) {
                    final selected = index == _avatarIndex;
                    return GestureDetector(
                      onTap: () => setState(() => _avatarIndex = index),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                              : null,
                        ),
                        child: UserAvatar(avatarIndex: index, radius: 20),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
                SectionCard(
                  title: '기본 정보',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTextField(controller: _nicknameController, label: '닉네임'),
                      if (!isGuest) ...[
                        const SizedBox(height: 12),
                        AppTextField(
                          controller: _passwordController,
                          label: '새 비밀번호',
                          hintText: '변경할 비밀번호를 입력하세요',
                          obscureText: true,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                AppButton(label: '저장', onPressed: _handleSave),
                const SizedBox(height: 24),
                if (isGuest)
                  SectionCard(
                    title: '게스트로 이용 중',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('계정을 만들면 다음에도 같은 프로필로 로그인할 수 있어요.'),
                        const SizedBox(height: 12),
                        AppButton(label: '로그인 / 회원가입', onPressed: _goToLoginScreen),
                      ],
                    ),
                  )
                else
                  AppButton(
                    label: '로그아웃',
                    variant: AppButtonVariant.outlined,
                    onPressed: _goToLoginScreen,
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
