import 'package:flutter/material.dart';

import '../../mock/mock_data.dart';
import '../../models/room_summary.dart';
import '../../services/user_session.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/responsive_center.dart';
import '../../widgets/section_card.dart';
import '../../widgets/user_avatar.dart';
import '../profile/profile_screen.dart';
import '../room/room_screen.dart';

/// 로비 상단에 표시할 내 전적 요약(백엔드 연동 전까지 쓰는 더미 값).
const _mockLevel = 5;
const _mockWinRate = 0.62;
const _mockTotalGames = 24;

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _codeController = TextEditingController();
  List<RoomSummary> _publicRooms = List.of(mockPublicRooms);
  bool _isRefreshing = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() {
      _publicRooms = List.of(mockPublicRooms);
      _isRefreshing = false;
    });
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

  void _handleJoinByCode() {
    final code = _codeController.text.trim();
    if (code.length != 4) return;
    _openRoom(code: code, isHost: false);
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('라이어게임'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GestureDetector(
              onTap: _openProfile,
              child: UserAvatar(avatarIndex: UserSession.avatarIndex, radius: 18),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
        child: ResponsiveCenter(
          maxWidth: 960,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              final roomList = _buildRoomListPanel(context);
              final statsPanel = _buildStatsPanel(context);
              if (!isWide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [statsPanel, const SizedBox(height: 16), roomList],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: roomList),
                  const SizedBox(width: 16),
                  SizedBox(width: 280, child: statsPanel),
                ],
              );
            },
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildStatsPanel(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              UserAvatar(avatarIndex: UserSession.avatarIndex, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(UserSession.nickname, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Lv.$_mockLevel',
                        style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text('${(_mockWinRate * 100).round()}%', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('승률', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Container(width: 1, height: 32, color: Colors.black.withValues(alpha: 0.08)),
                Expanded(
                  child: Column(
                    children: [
                      Text('$_mockTotalGames', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('총 게임', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppButton(label: '방 만들기', icon: Icons.add, onPressed: _handleCreateRoom),
          const SizedBox(height: 12),
          Text('코드로 입장', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _codeController,
                  hintText: '4자리 코드',
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                ),
              ),
              const SizedBox(width: 8),
              AppButton(label: '입장', fullWidth: false, onPressed: _handleJoinByCode),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoomListPanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('공개방 목록', style: Theme.of(context).textTheme.titleLarge),
            ),
            IconButton(
              onPressed: _isRefreshing ? null : _handleRefresh,
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _publicRooms.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final room = _publicRooms[index];
            return _PublicRoomTile(
              room: room,
              colorIndex: index,
              onTap: () => _openRoom(code: room.code, isHost: false),
            );
          },
        ),
      ],
    );
  }
}

class _PublicRoomTile extends StatelessWidget {
  final RoomSummary room;
  final int colorIndex;
  final VoidCallback onTap;

  const _PublicRoomTile({required this.room, required this.colorIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isFull = room.playerCount >= room.maxPlayers;
    return Card(
      child: ListTile(
        leading: UserAvatar(avatarIndex: colorIndex, radius: 20),
        title: Text(room.title),
        subtitle: Text('방장 ${room.hostNickname} · ${room.playerCount}/${room.maxPlayers}명'),
        trailing: FilledButton(
          onPressed: isFull ? null : onTap,
          child: Text(isFull ? '가득 참' : '입장'),
        ),
      ),
    );
  }
}
