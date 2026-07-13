import 'dart:math';

import 'package:flutter/material.dart';
import '../../theme/pixel_font.dart';

import '../../mock/mock_data.dart';
import '../../models/room_summary.dart';
import '../../services/user_session.dart';
import '../../theme/app_colors.dart';
import '../../utils/breakpoints.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_nav_rail.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/pixel_box.dart';
import '../../widgets/pixel_dialog.dart';
import '../../widgets/pixel_top_bar.dart';
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

  Future<void> _openRoom({
    required String code,
    required bool isHost,
    int maxPlayers = 8,
    String? initialCategory,
  }) async {
    // RoomScreen은 방장이 나갈 때 true를 돌려준다(PLAN.md room:closed — 방장 퇴장 시 방이
    // 통째로 사라짐). 그 경우 공개방 목록에서도 지워야 다른 사람이 사라진 방에 들어가려는
    // 걸 막을 수 있다. 방장이 아닌 사람의 퇴장은 방이 유지되므로 목록도 그대로 둔다.
    final roomClosed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'room'),
        builder: (_) => RoomScreen(
          roomCode: code,
          isHost: isHost,
          maxPlayers: maxPlayers,
          initialCategory: initialCategory,
        ),
      ),
    );
    if (!mounted) return;
    // 방에서 게임을 마치고 돌아오면 갱신된 전적(승률/레벨)이 로비에 바로 반영되도록 다시 그린다.
    setState(() {
      if (roomClosed == true) {
        _publicRooms.removeWhere((r) => r.code == code);
      }
    });
  }

  String _generateRoomCode() {
    final random = Random();
    return (1000 + random.nextInt(9000)).toString();
  }

  /// 방 만들기 다이얼로그 — 공개/비공개, 인원수, 카테고리를 미리 정한다
  /// (PLAN.md `room:create` 계약 `{ nickname, visibility, maxPlayers }` + 카테고리 사전 선택).
  Future<void> _handleCreateRoom() async {
    var isPublic = true;
    var maxPlayers = 8;
    var category = mockCategories.first;

    final confirmed = await showPixelDialog<bool>(
      context: context,
      barrierDismissible: true,
      maxWidth: 360,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('🚪 방 만들기', style: PixelFont.title(fontSize: 13, color: AppColors.primary)),
                const SizedBox(height: 16),
                Text('공개 설정', style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _ChoiceChip(
                        label: '🌍 공개',
                        selected: isPublic,
                        onTap: () => setDialogState(() => isPublic = true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ChoiceChip(
                        label: '🔒 비공개',
                        selected: !isPublic,
                        onTap: () => setDialogState(() => isPublic = false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('인원수 (사람+봇 합산)', style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconButton(
                      onPressed: maxPlayers > 3 ? () => setDialogState(() => maxPlayers--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Expanded(
                      child: Text(
                        '$maxPlayers명',
                        textAlign: TextAlign.center,
                        style: PixelFont.title(fontSize: 14, color: AppColors.foreground),
                      ),
                    ),
                    IconButton(
                      onPressed: maxPlayers < 12 ? () => setDialogState(() => maxPlayers++) : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('카테고리', style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: mockCategories.map((c) {
                    return _ChoiceChip(
                      label: c,
                      selected: c == category,
                      onTap: () => setDialogState(() => category = c),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: '취소',
                        variant: AppButtonVariant.outlined,
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(label: '방 만들기', onPressed: () => Navigator.of(dialogContext).pop(true)),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final code = _generateRoomCode();
    if (isPublic) {
      setState(() {
        _publicRooms.insert(
          0,
          RoomSummary(
            code: code,
            title: '${UserSession.nickname}의 방',
            category: category,
            hostNickname: UserSession.nickname,
            playerCount: 1,
            maxPlayers: maxPlayers,
          ),
        );
      });
    }
    _openRoom(code: code, isHost: true, maxPlayers: maxPlayers, initialCategory: category);
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
    // 다이얼로그 닫힘 애니메이션이 끝나기 전에 dispose()하면 TextField가 dispose된 컨트롤러를
    // 참조하게 되어 에러가 나므로(게스트 로그인 오류와 동일한 원인) 여기서 dispose하지 않는다.
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
    final isDesktop = context.isDesktop;

    return Scaffold(
      body: SafeArea(
        child: isDesktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppNavRail(
                    items: [
                      const AppNavRailItem(icon: Icons.home_outlined, label: '로비', selected: true),
                      AppNavRailItem(
                        icon: Icons.people_outline,
                        label: '친구',
                        badgeCount: pendingRequests,
                        onTap: _openFriends,
                      ),
                      AppNavRailItem(icon: Icons.person_outline, label: '프로필', onTap: _openProfile),
                    ],
                  ),
                  Expanded(child: _buildBody(isDesktop: true)),
                ],
              )
            : Column(
                children: [
                  _Header(pendingRequests: pendingRequests, onFriends: _openFriends, onProfile: _openProfile),
                  Expanded(child: _buildBody(isDesktop: false)),
                ],
              ),
      ),
    );
  }

  Widget _buildBody({required bool isDesktop}) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StatsCard(),
          const SizedBox(height: 12),
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
          _buildRoomList(isDesktop: isDesktop),
        ],
      ),
    );
  }

  /// 모바일은 세로 목록, 데스크탑은 넓은 화면을 활용해 카드가 여러 열로 흐르는 그리드로 표시한다.
  Widget _buildRoomList({required bool isDesktop}) {
    final tiles = _filteredRooms
        .map((room) => _PublicRoomTile(
              room: room,
              onTap: room.inProgress ? null : () => _openRoom(code: room.code, isHost: false),
            ))
        .toList();

    if (!isDesktop) {
      return Column(children: tiles);
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final tile in tiles) SizedBox(width: 320, child: tile)],
    );
  }
}

/// 로비 상단의 내 전적 카드 — 프로필 사진·레벨·승률(PLAN.md "로비 — 내 승률·레벨·프로필 사진 표시").
class _StatsCard extends StatelessWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context) {
    final stats = UserSession.stats;
    final winRateText = stats.overallWinRate == null ? '기록 없음' : '승률 ${(stats.overallWinRate! * 100).round()}%';

    return PixelBox(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          UserAvatar(avatarIndex: UserSession.avatarIndex, radius: 18, imageBytes: UserSession.profileImageBytes),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UserSession.nickname,
                  style: PixelFont.body(fontSize: 13, color: AppColors.foreground, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  'Lv.${stats.level} · 전체 ${stats.totalGames}판 · $winRateText',
                  style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground),
                ),
              ],
            ),
          ),
        ],
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
    return PixelTopBar(
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
          PixelBox(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            color: AppColors.secondary,
            border: const Border.fromBorderSide(BorderSide(color: AppColors.border, width: 2)),
            shadowOffset: const Offset(2, 2),
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
      child: PixelBox(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        color: isPrimary ? AppColors.primary : AppColors.secondary,
        border: Border.all(color: isPrimary ? AppColors.primaryBorder : AppColors.border, width: 3),
        shadowOffset: const Offset(2, 2),
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
          child: PixelBox(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${room.emoji} ${room.title}',
                              style: PixelFont.body(fontSize: 14, color: AppColors.foreground),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
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

/// 방 만들기 다이얼로그의 공개설정/카테고리 선택용 토글 칩.
class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: PixelBox(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: selected ? AppColors.primary : AppColors.secondary,
        border: Border.all(color: selected ? AppColors.primaryBorder : AppColors.border),
        shadowOffset: null,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: PixelFont.body(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : AppColors.foreground,
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
    return PixelBox(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      color: color,
      border: Border.all(color: AppColors.border),
      shadowOffset: null,
      child: Text(text, style: PixelFont.body(fontSize: 11, color: textColor)),
    );
  }
}
