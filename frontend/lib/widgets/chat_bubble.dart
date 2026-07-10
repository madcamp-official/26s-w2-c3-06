import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../theme/app_colors.dart';

/// 채팅 메시지 한 줄. AI 분탕질 메시지는 다른 색/아이콘으로 구분해 표시한다.
class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    switch (message.type) {
      case ChatMessageType.system:
        return _buildSystemMessage(context);
      case ChatMessageType.ai:
        return _buildBubble(
          context,
          backgroundColor: AppColors.aiAccent.withValues(alpha: 0.12),
          borderColor: AppColors.aiAccent,
          leading: const Icon(Icons.smart_toy, size: 16, color: AppColors.aiAccent),
          senderLabel: 'AI 분탕질',
          senderColor: AppColors.aiAccent,
          textStyle: const TextStyle(fontStyle: FontStyle.italic),
        );
      case ChatMessageType.player:
        return _buildBubble(
          context,
          backgroundColor: Colors.white,
          borderColor: Colors.grey.shade300,
          leading: null,
          senderLabel: message.sender,
          senderColor: AppColors.textPrimary,
          textStyle: null,
        );
    }
  }

  Widget _buildSystemMessage(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Text(
          message.text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildBubble(
    BuildContext context, {
    required Color backgroundColor,
    required Color borderColor,
    required Widget? leading,
    required String senderLabel,
    required Color senderColor,
    required TextStyle? textStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 6)],
                Text(
                  senderLabel,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: senderColor),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(message.text, style: textStyle),
          ],
        ),
      ),
    );
  }
}
