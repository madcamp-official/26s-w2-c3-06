import 'package:flutter/material.dart';
import '../../theme/pixel_font.dart';

import '../../mock/mock_data.dart';
import '../../models/room_summary.dart';
import '../../services/user_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/pixel_dialog.dart';
import '../../widgets/user_avatar.dart';
import '../friends/friends_screen.dart';
import '../login/login_screen.dart';
import '../profile/profile_screen.dart';
import '../room/room_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _searchController = TextEditingController();
  final List<RoomSummary> _publicRooms = List.of(mockPublicRooms);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RoomSummary> get _filteredRooms {
    final query = _searchController.text.trim();
    if (query.isEmpty) return _publicRooms;
    return _publicRooms.where((r) => r.title.contains(query) || r.category.contains(query)).toList();
  }

  void _openRoom({required String code, required bool isHost}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'room'),
        builder: (_) => RoomScreen(roomCode: code, isHost: isHost),
      ),
    );
  }

  void _handleCreateRoom() {
    _openRoom(code: '8421', isHost: true);
  }

  Future<void> _handleJoinByCode() async {
    final controller = TextEditingController();
    final code = await showPixelDialog<String>(
      context: context,
      barrierDismissible: true,
      maxWidth: 320,
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🔑 코드 입장', style: PixelFont.title(fontSize: 11, color: AppColors.primary)),
            const SizedBox(height: 16),
            AppTextField(
              controller: controller,
              hintText: '4자리 코드',
              keyboardType: TextInputType.number,
              maxLength: 4,
              onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
            ),
            const SizedBox(height: 12),
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
                    label: '입장',
                    onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (code == null || code.length != 4) return;
    if (!mounted) return;
    _openRoom(code: code, isHost: false);
  }

  Future<void> _openFriends() async {
    if (UserSession.isGuest) {
      await showPixelDialog(
        context: context,
        barrierDismissible: true,
        maxWidth: 320,
        builder: (dialogContext) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('👥 친구 기능', style: PixelFont.title(fontSize: 12, color: AppColors.primary)),
              const SizedBox(height: 12),
              Text(
                '게스트는 친구 기능을 이용할 수 없습니다.',
                style: TextStyle(color: AppColors.mutedForeground),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: '닫기',
                      variant: AppButtonVariant.outlined,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppButton(
                      label: '회원가입',
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FriendsScreen()));
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pendingRequests = mockFriendRequests.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              pendingRequests: pendingRequests,
              onFriends: _openFriends,
              onProfile: _openProfile,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('LOBBY', style: PixelFont.title(fontSize: 12, color: AppColors.foreground)),
                        ),
                        _HeaderPixelButton(
                          label: '코드 입장',
                          icon: Icons.vpn_key_outlined,
                          isPrimary: false,
                          onTap: _handleJoinByCode,
                        ),
                        const SizedBox(width: 7),
                        _HeaderPixelButton(
                          label: '방 만들기',
                          icon: Icons.add,
                          isPrimary: true,
                          onTap: _handleCreateRoom,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _searchController,
                      hintText: '방 이름 / 카테고리 검색',
                      prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.mutedForeground),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    ..._filteredRooms.map((room) => _PublicRoomTile(
                          room: room,
                          onTap: room.inProgress ? null : () => _openRoom(code: room.code, isHost: false),
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int pendingRequests;
  final VoidCallback onFriends;
  final VoidCallback onProfile;

  const _Header({required this.pendingRequests, required this.onFriends, required this.onProfile});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.accent,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 3)),
        boxShadow: [BoxShadow(color: AppColors.hardShadow, offset: Offset(0, 3), blurRadius: 0)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('🤖 AI LIAR GAME', style: PixelFont.title(fontSize: 11, color: AppColors.foreground)),
          ),
          _IconBox(
            onTap: onFriends,
            badgeCount: pendingRequests,
            child: const Icon(Icons.people_outline, size: 18, color: AppColors.foreground),
          ),
          const SizedBox(width: 8),
          _IconBox(
            onTap: onProfile,
            child: UserAvatar(avatarIndex: UserSession.avatarIndex, radius: 12, imageBytes: UserSession.profileImageBytes),
          ),
        ],
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final int badgeCount;

  const _IconBox({required this.onTap, required this.child, this.badgeCount = 0});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.secondary,
              border: Border.fromBorderSide(BorderSide(color: AppColors.border, width: 2)),
              boxShadow: [BoxShadow(color: AppColors.hardShadow, offset: Offset(2, 2), blurRadius: 0)],
            ),
            child: child,
          ),
          if (badgeCount > 0)
            Positioned(
              right: -6,
              top: -6,
              child: Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.notificationBadge,
                  border: Border.all(color: AppColors.background, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badgeCount',
                  style: PixelFont.body(fontSize: 9, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// LOBBY 헤더 줄의 컴팩트한 픽셀 버튼("코드 입장"/"방 만들기") — 일반 AppButton보다 작은 패딩.
class _HeaderPixelButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const _HeaderPixelButton({required this.label, required this.icon, required this.isPrimary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.primary : AppColors.secondary,
          border: Border.all(color: isPrimary ? AppColors.primaryBorder : AppColors.border, width: 3),
          boxShadow: const [BoxShadow(color: AppColors.hardShadow, offset: Offset(2, 2), blurRadius: 0)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isPrimary ? Colors.white : AppColors.foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: PixelFont.body(fontSize: 12, color: isPrimary ? Colors.white : AppColors.foreground),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicRoomTile extends StatelessWidget {
  final RoomSummary room;
  final VoidCallback? onTap;

  const _PublicRoomTile({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isFull = room.playerCount >= room.maxPlayers;
    final disabled = onTap == null || isFull;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: disabled ? 0.6 : 1,
        child: GestureDetector(
          onTap: disabled ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border.fromBorderSide(BorderSide(color: AppColors.border, width: 3)),
              boxShadow: [BoxShadow(color: AppColors.hardShadow, offset: Offset(4, 4), blurRadius: 0)],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${room.emoji} ${room.title}',
                            style: PixelFont.body(fontSize: 14, color: AppColors.foreground),
                          ),
                          const SizedBox(width: 7),
                          _Tag(text: room.category, color: AppColors.secondary, textColor: AppColors.mutedForeground),
                          if (room.inProgress) ...[
                            const SizedBox(width: 6),
                            const _Tag(text: '🔴 진행중', color: AppColors.destructive, textColor: Colors.white),
                          ],
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.person, size: 10, color: AppColors.mutedForeground),
                          const SizedBox(width: 3),
                          Text(
                            '${room.playerCount}/${room.maxPlayers}',
                            style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '방장: ${room.hostNickname}',
                            style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!disabled) const Icon(Icons.chevron_right, size: 16, color: AppColors.mutedForeground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;

  const _Tag({required this.text, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(color: color, border: Border.all(color: AppColors.border)),
      child: Text(text, style: PixelFont.body(fontSize: 11, color: textColor)),
    );
  }
}
