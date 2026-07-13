import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../services/user_session.dart';
import '../theme/app_colors.dart';
import 'user_avatar.dart';

/// 채팅 메시지 한 줄. AI 분탕질 메시지는 왼쪽 강조선이 있는 콜아웃으로, 시스템 메시지는
/// 가운데 정렬된 알약 배지로, 일반 채팅/턴 설명은 아바타+말풍선으로 표시한다.
class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    switch (message.type) {
      case ChatMessageType.system:
        return _buildSystemPill(context);
      case ChatMessageType.aiComment:
        return _buildAiCallout(context);
      case ChatMessageType.turnDescription:
      case ChatMessageType.chat:
        return _buildPlayerBubble(context);
    }
  }

  Widget _buildSystemPill(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accent,
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            message.text,
            style: const TextStyle(fontSize: 11, color: AppColors.mutedForeground),
          ),
        ),
      ),
    );
  }

  Widget _buildAiCallout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: const BoxDecoration(
          color: AppColors.accent,
          border: Border(left: BorderSide(color: AppColors.primary, width: 4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('☕', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message.text,
                style: const TextStyle(color: AppColors.primary, fontStyle: FontStyle.italic, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerBubble(BuildContext context) {
    final isMine = message.senderId == 'me';

    final avatar = UserAvatar(
      avatarIndex: message.avatarIndex,
      radius: 13,
      imageBytes: isMine ? UserSession.profileImageBytes : null,
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
