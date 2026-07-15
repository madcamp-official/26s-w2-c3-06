import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../services/user_session.dart';
import '../theme/app_colors.dart';
import 'user_avatar.dart';

/// 채팅 메시지 한 줄. 시스템 메시지는 가운데 정렬된 알약 배지로, 일반 채팅/턴 설명은
/// 아바타+말풍선으로 표시한다.
class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  /// 현재 로그인한 유저의 uid. 내 메시지를 오른쪽 정렬로 표시하는 데 쓴다.
  final String? myUid;

  /// 발신자의 실제 프로필 사진 URL(서버 저장분). null이면 UserAvatar가 기본 아이콘을 보여준다.
  final String? senderAvatarUrl;

  const ChatBubble({super.key, required this.message, this.myUid, this.senderAvatarUrl});

  @override
  Widget build(BuildContext context) {
    switch (message.type) {
      case ChatMessageType.system:
        return _buildSystemPill(context);
      case ChatMessageType.turnDescription:
      case ChatMessageType.chat:
        return _buildPlayerBubble(context);
    }
  }

  Widget _buildSystemPill(BuildContext context) {
    // 게임 시작/종료 같은 주요 안내는 진한 배지로 강조하고, 입장/차례/시간초과 같은
    // 일상적인 안내는 테두리·배경 없이 옅은 글자로만 표시해 더 뒤로 물러나 보이게 한다.
    final highlight = message.highlight;
    if (!highlight) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Center(
          child: Text(
            message.text,
            style: TextStyle(fontSize: 10, color: AppColors.mutedForeground.withValues(alpha: 0.6)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Text(
          message.text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildPlayerBubble(BuildContext context) {
    // senderId는 서버가 실어 보내는 실제 uid('ai'/'system' 제외)라, 리터럴 'me'와는 절대
    // 같을 수 없어 내 메시지가 항상 왼쪽으로 뜨던 버그가 있었다. 실제 내 uid와 비교한다.
    final isMine = myUid != null && message.senderId == myUid;

    final avatar = UserAvatar(
      avatarIndex: message.avatarIndex,
      radius: 13,
      imageBytes: isMine ? UserSession.profileImageBytes : null,
      imageUrl: senderAvatarUrl,
      isBot: message.senderId.startsWith('bot-'),
    );
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMine ? AppColors.primary.withValues(alpha: 0.12) : AppColors.card,
        border: Border.all(color: isMine ? AppColors.primary : AppColors.border),
      ),
      child: Text(message.text, style: const TextStyle(fontSize: 13)),
    );
    final nameLabel = Text(
      message.senderNickname,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.mutedForeground),
    );

    final column = Flexible(
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [nameLabel, const SizedBox(height: 2), bubble],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: isMine
            ? [column, const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), column],
      ),
    );
  }
}
