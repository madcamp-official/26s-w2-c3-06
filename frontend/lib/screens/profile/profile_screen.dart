import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/pixel_font.dart';

import '../../api/backend_api.dart';
import '../../widgets/hover_tap.dart';
import '../../services/auth_service.dart';
import '../../services/user_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/responsive_center.dart';
import '../../widgets/user_avatar.dart';
import '../login/login_screen.dart';

/// 프로필 사진/닉네임을 수정하는 화면.
/// 게스트는 닉네임/사진만 바꿀 수 있고, 대신 계정을 만들 수 있는 진입점을 제공한다.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _nicknameController;
  late int _avatarIndex;
  Uint8List? _profileImageBytes;
  String? _avatarUrl;
  UserStats? _stats;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: UserSession.nickname);
    _avatarIndex = UserSession.avatarIndex;
    _profileImageBytes = UserSession.profileImageBytes;
    // 서버에 저장된 프로필 사진 URL 복원(로컬 미리보기가 없을 때 표시).
    BackendApi.instance.getMyProfile().then((p) {
      if (mounted) setState(() => _avatarUrl = p.avatarUrl);
    }).catchError((_) {});
    // 레벨 배지·진행바 표시용(PLAN "XP·레벨 프론트 표시").
    BackendApi.instance.getMyStats().then((s) {
      if (mounted) setState(() => _stats = s);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _handleSaveNickname() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) return;
    try {
      // 중복 판정은 syncNickname(PUT /me)의 권위 응답에 맡긴다 — 본인 uid를 제외해 자기
      // 닉네임 유지가 가능하고 실제 중복이면 409를 준다. (공개 사전확인 엔드포인트는 self를
      // 제외하지 못해 자기 닉네임도 '중복'으로 막을 수 있어 여기선 쓰지 않는다.)
      // DB가 수락한 뒤에만 Firebase displayName을 바꿔 둘이 어긋나지 않게 한다.
      await BackendApi.instance.syncNickname(nickname);
      await AuthService.instance.updateNickname(nickname);
      setState(() => UserSession.nickname = nickname);
      _snack('닉네임이 저장되었습니다.');
    } on BackendApiException catch (e) {
      _snack(e.statusCode == 409 ? '이미 사용 중인 닉네임입니다.' : '닉네임 저장에 실패했습니다.');
    } catch (e) {
      _snack('오류: $e');
    }
  }

  /// 최상위(AuthGate)로 되돌아간다. 로그아웃/탈퇴 후 호출하면 AuthGate가 인증 상태 변화를
  /// 감지해 로그인 화면을 보여준다(개별 화면이 LoginScreen을 직접 push하지 않는다).
  void _backToRoot() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _handleLogout() async {
    await AuthService.instance.signOut();
    if (!mounted) return;
    _backToRoot();
  }

  /// 게스트가 "로그인 / 회원가입"을 눌렀을 때. 로그아웃(세션 파괴) 없이 로그인 화면을
  /// 그대로 push한다 — 뒤로가기를 누르면 로그아웃 없이 원래 쓰던 게스트 계정으로 계속
  /// 이용할 수 있고, 실제로 로그인/가입을 완료해야만 그 계정으로 전환된다.
  void _handleGuestUpgrade() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen(pushedFromProfile: true)),
    );
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
    setState(() {
      _profileImageBytes = null;
      _avatarUrl = null;
    });
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
    _backToRoot();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user?.isAnonymous ?? UserSession.isGuest;

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
                        child: UserAvatar(
                          avatarIndex: _avatarIndex,
                          radius: 40,
                          imageBytes: _profileImageBytes,
                          imageUrl: _avatarUrl,
                        ),
                      ),
                      Positioned(
                        right: -6,
                        bottom: -6,
                        child: HoverTap(
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
                if (_stats != null) ...[
                  const SizedBox(height: 14),
                  _LevelBadge(stats: _stats!),
                ],
                // 사진 변경은 아바타 우하단 카메라 버튼으로 하고, 여기선 삭제만 노출한다.
                if (_profileImageBytes != null) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: _handleRemovePhoto,
                      style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
                      child: const Text('사진 삭제'),
                    ),
                  ),
                ],
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
                const SizedBox(height: 24),
                if (isGuest) ...[
                  Text('게스트로 이용 중입니다. 계정을 만들면 다음에도 같은 프로필로 로그인할 수 있어요.',
                      style: TextStyle(color: AppColors.mutedForeground)),
                  const SizedBox(height: 12),
                  AppButton(label: '로그인 / 회원가입', onPressed: _handleGuestUpgrade),
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

/// 레벨 배지 + 레벨 내 진행바. PLAN "XP·레벨 프론트 표시" 참고 — 진행도는
/// UserStats.levelProgress(서버와 동일한 레벨 임계값 공식)로 계산한다.
class _LevelBadge extends StatelessWidget {
  final UserStats stats;

  const _LevelBadge({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: AppColors.primary, border: Border.all(color: AppColors.primaryBorder)),
            child: Text('Lv.${stats.level}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12)),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: stats.levelProgress,
                minHeight: 6,
                backgroundColor: AppColors.border.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '다음 레벨까지 ${stats.xpToNextLevel} XP',
            style: TextStyle(fontSize: 10, color: AppColors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _FieldSection extends StatelessWidget {
  final String label;
  final Widget child;

  const _FieldSection({required this.label, required this.child});

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
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
