import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/pixel_font.dart';

import '../../api/backend_api.dart';
import '../../services/auth_service.dart';
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
  Uint8List? _profileImageBytes;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: UserSession.nickname);
    _avatarIndex = UserSession.avatarIndex;
    _profileImageBytes = UserSession.profileImageBytes;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _handleSaveNickname() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;
    try {
      // 닉네임 중복 확인 후 Firebase displayName + 로컬 DB 동기화(서버 @unique 제약).
      final available = await BackendApi.instance.isNicknameAvailable(nickname);
      if (!available) {
        _snack('이미 사용 중인 닉네임입니다.');
        return;
      }
      await AuthService.instance.updateNickname(nickname);
      await BackendApi.instance.syncNickname(nickname);
      setState(() => UserSession.nickname = nickname);
      _snack('닉네임이 저장되었습니다.');
    } on BackendApiException catch (e) {
      _snack(e.statusCode == 409 ? '이미 사용 중인 닉네임입니다.' : '닉네임 저장에 실패했습니다.');
    } catch (e) {
      _snack('오류: $e');
    }
  }

  Future<void> _handleChangePassword() async {
    if (_newPasswordController.text.length < 8) {
      _snack('새 비밀번호는 8자 이상이어야 합니다.');
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      _snack('새 비밀번호가 일치하지 않습니다.');
      return;
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email;
      // 비밀번호 변경은 최근 로그인 필요 — 현재 비밀번호로 재인증 후 변경.
      if (email != null && _currentPasswordController.text.isNotEmpty) {
        final cred = EmailAuthProvider.credential(email: email, password: _currentPasswordController.text);
        await user!.reauthenticateWithCredential(cred);
      }
      await user?.updatePassword(_newPasswordController.text);
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      _snack('비밀번호가 변경되었습니다.');
    } on FirebaseAuthException catch (e) {
      _snack('변경 실패: ${e.message ?? e.code}');
    }
  }

  void _goToLoginScreen() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _handleLogout() async {
    await AuthService.instance.signOut();
    if (!mounted) return;
    _goToLoginScreen();
  }

  Future<void> _handlePickPhoto() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    // 즉시 로컬 미리보기 반영 후, Firebase Storage(avatars/{uid})에 업로드하고 URL을 백엔드에 기록.
    setState(() => _profileImageBytes = bytes);
    UserSession.profileImageBytes = bytes;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final storageRef = FirebaseStorage.instance.ref('avatars/$uid');
      await storageRef.putData(bytes, SettableMetadata(contentType: file.mimeType ?? 'image/jpeg'));
      final url = await storageRef.getDownloadURL();
      await BackendApi.instance.updateAvatarUrl(url);
      _snack('프로필 사진이 변경되었습니다.');
    } catch (e) {
      _snack('사진 업로드에 실패했습니다: $e');
    }
  }

  Future<void> _handleRemovePhoto() async {
    setState(() => _profileImageBytes = null);
    UserSession.profileImageBytes = null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await BackendApi.instance.updateAvatarUrl(null);
      await FirebaseStorage.instance.ref('avatars/$uid').delete().catchError((_) {});
    } catch (_) {
      // 삭제 실패는 조용히 무시(다음 저장 시 덮어써짐).
    }
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
    try {
      // 백엔드가 Firebase 계정 삭제까지 함께 처리(전적/프로필/친구 cascade 삭제).
      await BackendApi.instance.deleteMyAccount();
      await AuthService.instance.signOut();
    } catch (e) {
      _snack('탈퇴 처리 중 오류: $e');
      return;
    }
    if (!mounted) return;
    _goToLoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user?.isAnonymous ?? UserSession.isGuest;
    // 비밀번호 변경은 이메일/비밀번호(provider 'password') 계정에서만 노출(구글 계정은 비밀번호 없음).
    final canChangePassword = user?.providerData.any((p) => p.providerId == 'password') ?? false;

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
                        child: UserAvatar(avatarIndex: _avatarIndex, radius: 40, imageBytes: _profileImageBytes),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        label: '사진 변경',
                        icon: Icons.photo_library_outlined,
                        variant: AppButtonVariant.outlined,
                        fullWidth: false,
                        onPressed: _handlePickPhoto,
                      ),
                      if (_profileImageBytes != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _handleRemovePhoto,
                          style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
                          child: const Text('사진 삭제'),
                        ),
                      ],
                    ],
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
                  AppButton(label: '로그아웃', variant: AppButtonVariant.outlined, onPressed: _handleLogout),
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
