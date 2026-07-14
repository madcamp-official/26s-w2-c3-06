import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/pixel_font.dart';

import '../../api/backend_api.dart';
import '../../services/user_session.dart';
import '../../state/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/responsive_center.dart';
import '../../widgets/user_avatar.dart';

/// 친구 목록/요청 화면 — 백엔드 REST(/api/friends) 실연동.
/// 온라인 여부(isOnline)는 서버 소켓 프레젠스 스냅샷으로 내려온다.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _addController = TextEditingController();
  int _tab = 0;
  late Future<List<FriendSummary>> _friendsFuture;
  late Future<List<FriendRequestSummary>> _requestsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _friendsFuture = BackendApi.instance.getFriends();
      _requestsFuture = BackendApi.instance.getPendingFriendRequests();
    });
    ref.invalidate(pendingFriendRequestCountProvider);
  }

  void _snack(String msg) {
    if (mounted) showAppAlert(context, msg);
  }

  Future<void> _handleAddFriend() async {
    final nickname = _addController.text.trim();
    if (nickname.isEmpty) return;
    _addController.clear();
    try {
      await BackendApi.instance.sendFriendRequestByNickname(nickname);
      _snack('"$nickname"님에게 친구 요청을 보냈습니다.');
    } on BackendApiException catch (e) {
      _snack(switch (e.statusCode) {
        404 => '해당 닉네임의 사용자를 찾을 수 없습니다.',
        409 => '이미 친구이거나 요청 중입니다.',
        403 => '게스트 계정과는 친구를 맺을 수 없습니다.',
        _ => '요청 실패: ${e.message}',
      });
    }
  }

  Future<void> _acceptRequest(FriendRequestSummary r) async {
    try {
      await BackendApi.instance.acceptFriendRequest(r.id);
      _snack('${r.requesterNickname}님과 친구가 되었습니다.');
      _reload();
    } catch (_) {
      _snack('수락에 실패했습니다.');
    }
  }

  Future<void> _declineRequest(FriendRequestSummary r) async {
    try {
      await BackendApi.instance.declineFriendRequest(r.id);
      _reload();
    } catch (_) {
      _snack('거절에 실패했습니다.');
    }
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
                Text('닉네임으로 친구 추가',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedForeground)),
                const SizedBox(height: 8),
                // 친구 요청은 회원끼리만 가능하다 — 게스트는 uid가 세션마다 바뀔 수 있어
                // 친구 관계가 쉽게 끊어지므로 입력창 자체를 막고 안내만 보여준다.
                if (UserSession.isGuest)
                  Text(
                    '친구 추가는 회원만 이용할 수 있어요. 로그인/회원가입 후 다시 시도해주세요.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.mutedForeground),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _addController,
                          hintText: '상대방 닉네임 입력...',
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
                        label: '친구 목록',
                        variant: _tab == 0 ? AppButtonVariant.primary : AppButtonVariant.outlined,
                        onPressed: () => setState(() => _tab = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: '받은 요청',
                        variant: _tab == 1 ? AppButtonVariant.primary : AppButtonVariant.outlined,
                        onPressed: () => setState(() => _tab = 1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_tab == 0) _friendsList() else _requestsList(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _friendsList() {
    return FutureBuilder<List<FriendSummary>>(
      future: _friendsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        final friends = snap.data ?? const [];
        if (friends.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('친구가 없습니다', style: TextStyle(color: AppColors.mutedForeground))),
          );
        }
        return Column(children: friends.map((f) => _FriendTile(friend: f)).toList());
      },
    );
  }

  Widget _requestsList() {
    return FutureBuilder<List<FriendRequestSummary>>(
      future: _requestsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        final requests = snap.data ?? const [];
        if (requests.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('받은 요청이 없습니다', style: TextStyle(color: AppColors.mutedForeground))),
          );
        }
        return Column(
          children: requests
              .map((r) => _RequestTile(
                    request: r,
                    onAccept: () => _acceptRequest(r),
                    onDecline: () => _declineRequest(r),
                  ))
              .toList(),
        );
      },
    );
  }
}

int _avatarIndexOf(String key) => key.hashCode.abs() % 8;

class _FriendTile extends StatelessWidget {
  final FriendSummary friend;

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
                UserAvatar(avatarIndex: _avatarIndexOf(friend.uid), radius: 20, imageUrl: friend.avatarUrl),
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
  final FriendRequestSummary request;
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
            UserAvatar(avatarIndex: _avatarIndexOf(request.requesterUid), radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(request.requesterNickname, style: const TextStyle(fontWeight: FontWeight.bold)),
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
