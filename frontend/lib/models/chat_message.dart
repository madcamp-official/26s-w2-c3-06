/// 채팅 메시지의 종류. AI 분탕질 메시지는 다른 스타일로 표시하기 위해 구분한다.
enum ChatMessageType { player, ai, system }

class ChatMessage {
  final String id;
  final String sender;
  final String text;
  final ChatMessageType type;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    this.type = ChatMessageType.player,
  });
}
