import 'package:flutter/material.dart';
import '../../theme/pixel_font.dart';

import '../../mock/mock_data.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/responsive_center.dart';
import '../../widgets/user_avatar.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _addController = TextEditingController();
  int _tab = 0;
  final List<MockFriendRequest> _requests = List.of(mockFriendRequests);

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _handleAddFriend() {
    final id = _addController.text.trim();
    if (id.isEmpty) return;
    _addController.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$id"님에게 친구 요청을 보냈습니다.')));
  }

  void _acceptRequest(MockFriendRequest request) {
    setState(() => _requests.remove(request));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${request.nickname}님과 친구가 되었습니다.')));
  }

  void _declineRequest(MockFriendRequest request) {
    setState(() => _requests.remove(request));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back)),
        title: Text('FRIENDS', style: PixelFont.title(fontSize: 14)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ResponsiveCenter(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('아이디로 친구 추가', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedForeground)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _addController,
                        hintText: '상대방 아이디 입력...',
                        onSubmitted: (_) => _handleAddFriend(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppButton(icon: Icons.person_add_alt_1, label: '', fullWidth: false, onPressed: _handleAddFriend),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: '친구 목록 (${mockFriends.length})',
                        variant: _tab == 0 ? AppButtonVariant.primary : AppButtonVariant.outlined,
                        onPressed: () => setState(() => _tab = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: '요청 (${_requests.length})',
                        variant: _tab == 1 ? AppButtonVariant.primary : AppButtonVariant.outlined,
                        onPressed: () => setState(() => _tab = 1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_tab == 0) ...[
                  ...mockFriends.map((f) => _FriendTile(friend: f)),
                  if (mockFriends.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('친구가 없습니다', style: TextStyle(color: AppColors.mutedForeground)),
                      ),
                    ),
                ] else ...[
                  _SectionLabel('받은 요청 (${_requests.length})'),
                  ..._requests.map((r) => _RequestTile(
                        request: r,
                        onAccept: () => _acceptRequest(r),
                        onDecline: () => _declineRequest(r),
                      )),
                  if (_requests.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('받은 요청이 없습니다', style: TextStyle(color: AppColors.mutedForeground)),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
    );
  }
}

class _FriendTile extends StatelessWidget {
  final MockFriend friend;

  const _FriendTile({required this.friend});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.border)),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                UserAvatar(avatarIndex: friend.avatarIndex, radius: 20),
                // 접속중인 친구만 초록 점으로 표시한다.
                if (friend.isOnline)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.card, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(friend.nickname, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    friend.isOnline ? '온라인' : '오프라인',
                    style: TextStyle(fontSize: 12, color: friend.isOnline ? AppColors.success : AppColors.mutedForeground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final MockFriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _RequestTile({required this.request, required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.border, width: 2)),
        child: Row(
          children: [
            UserAvatar(avatarIndex: request.avatarIndex, radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.nickname, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(request.receivedAt, style: TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
                ],
              ),
            ),
            IconButton(
              onPressed: onAccept,
              icon: const Icon(Icons.check, color: AppColors.success),
              style: IconButton.styleFrom(backgroundColor: AppColors.success.withValues(alpha: 0.12)),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: onDecline,
              icon: const Icon(Icons.close, color: AppColors.destructive),
              style: IconButton.styleFrom(backgroundColor: AppColors.destructive.withValues(alpha: 0.12)),
            ),
          ],
        ),
      ),
    );
  }
}
