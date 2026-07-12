import 'package:flutter/material.dart';
import '../../theme/pixel_font.dart';

import '../../services/user_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/responsive_center.dart';
import '../../widgets/user_avatar.dart';
import '../login/login_screen.dart';

/// 프로필 사진/닉네임/비밀번호를 수정하는 화면.
/// 게스트는 닉네임/사진만 바꿀 수 있고, 대신 계정을 만들 수 있는 진입점을 제공한다.
/// 비밀번호 변경은 이메일 가입 계정(AuthProvider.email)에서만 노출된다(구글 계정은 비밀번호가 없음).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nicknameController;
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
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
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleSaveNickname() {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;
    setState(() => UserSession.nickname = nickname);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('닉네임이 저장되었습니다.')));
  }

  void _handleChangePassword() {
    if (_currentPasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('현재 비밀번호를 입력해주세요.')));
      return;
    }
    if (_newPasswordController.text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('새 비밀번호는 8자 이상이어야 합니다.')));
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('새 비밀번호가 일치하지 않습니다.')));
      return;
    }
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('비밀번호가 변경되었습니다.')));
  }

  void _goToLoginScreen() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _handlePickPhoto() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.card,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('프로필 사진 변경', style: Theme.of(sheetContext).textTheme.titleMedium),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(avatarOptions.length, (index) {
                    final selected = index == _avatarIndex;
                    return GestureDetector(
                      onTap: () => Navigator.of(sheetContext).pop(index),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          border: selected ? Border.all(color: AppColors.primary, width: 2) : null,
                        ),
                        child: UserAvatar(avatarIndex: index, radius: 28),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) setState(() => _avatarIndex = picked);
  }

  Future<void> _handleDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: AppColors.destructive, size: 36),
          title: const Text('정말 탈퇴하시겠어요?'),
          content: const Text('탈퇴하면 전적과 프로필 정보가 모두 삭제되며 되돌릴 수 없습니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.destructive),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('탈퇴하기'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!mounted) return;
    _goToLoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = UserSession.isGuest;
    final canChangePassword = UserSession.authProvider == AuthProvider.email;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back)),
        title: Text('PROFILE', style: PixelFont.title(fontSize: 14)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ResponsiveCenter(
            maxWidth: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.accent, border: Border.all(color: AppColors.border, width: 2)),
                        child: UserAvatar(avatarIndex: _avatarIndex, radius: 40),
                      ),
                      Positioned(
                        right: -6,
                        bottom: -6,
                        child: GestureDetector(
                          onTap: _handlePickPhoto,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: AppColors.primary, border: Border.all(color: AppColors.card, width: 2)),
                            child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: AppButton(
                    label: '사진 변경',
                    icon: Icons.camera_alt_outlined,
                    variant: AppButtonVariant.outlined,
                    fullWidth: false,
                    onPressed: _handlePickPhoto,
                  ),
                ),
                const SizedBox(height: 20),
                _FieldSection(
                  label: 'NICKNAME',
                  child: Row(
                    children: [
                      Expanded(child: AppTextField(controller: _nicknameController)),
                      const SizedBox(width: 8),
                      AppButton(label: '저장', icon: Icons.check, fullWidth: false, onPressed: _handleSaveNickname),
                    ],
                  ),
                ),
                if (canChangePassword) ...[
                  const SizedBox(height: 16),
                  _FieldSection(
                    label: 'PASSWORD',
                    description: '이메일 가입 계정 — 비밀번호를 변경할 수 있습니다',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTextField(
                          controller: _currentPasswordController,
                          hintText: '현재 비밀번호',
                          obscureText: !_showCurrent,
                          suffixIcon: IconButton(
                            icon: Icon(_showCurrent ? Icons.visibility_off : Icons.visibility, size: 18),
                            onPressed: () => setState(() => _showCurrent = !_showCurrent),
                          ),
                        ),
                        const SizedBox(height: 10),
                        AppTextField(
                          controller: _newPasswordController,
                          hintText: '새 비밀번호 (8자 이상)',
                          obscureText: !_showNew,
                          suffixIcon: IconButton(
                            icon: Icon(_showNew ? Icons.visibility_off : Icons.visibility, size: 18),
                            onPressed: () => setState(() => _showNew = !_showNew),
                          ),
                        ),
                        const SizedBox(height: 10),
                        AppTextField(
                          controller: _confirmPasswordController,
                          hintText: '새 비밀번호 확인',
                          obscureText: !_showConfirm,
                          suffixIcon: IconButton(
                            icon: Icon(_showConfirm ? Icons.visibility_off : Icons.visibility, size: 18),
                            onPressed: () => setState(() => _showConfirm = !_showConfirm),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: AppButton(
                            label: '비밀번호 변경',
                            icon: Icons.check,
                            fullWidth: false,
                            onPressed: _handleChangePassword,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (isGuest) ...[
                  Text('게스트로 이용 중입니다. 계정을 만들면 다음에도 같은 프로필로 로그인할 수 있어요.',
                      style: TextStyle(color: AppColors.mutedForeground)),
                  const SizedBox(height: 12),
                  AppButton(label: '로그인 / 회원가입', onPressed: _goToLoginScreen),
                ] else ...[
                  AppButton(label: '로그아웃', variant: AppButtonVariant.outlined, onPressed: _goToLoginScreen),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(border: Border.all(color: AppColors.destructive, width: 2)),
                    child: TextButton(
                      onPressed: _handleDeleteAccount,
                      style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
                      child: const Text('계정 탈퇴'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldSection extends StatelessWidget {
  final String label;
  final String? description;
  final Widget child;

  const _FieldSection({required this.label, this.description, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.border, width: 2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.mutedForeground, letterSpacing: 1)),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
