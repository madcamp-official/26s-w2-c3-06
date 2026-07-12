/// 채팅 메시지의 종류. PLAN.md 계약(type: 'chat'|'turnDescription'|'aiComment'|'system')과 맞춘다.
enum ChatMessageType { chat, turnDescription, aiComment, system }

class ChatMessage {
  final String id;

  /// 실제 발화자 id('ai', 'system', 또는 Player.id).
  final String senderId;

  /// 화면 표시용 닉네임. 서버 계약엔 없지만(클라가 플레이어 목록으로 매핑) 목데이터 단계에선 편의상 함께 들고 다닌다.
  final String senderNickname;

  /// 아바타 렌더링용 인덱스 (플레이어 목록에서의 순번). AI/system 메시지는 사용하지 않는다.
  final int avatarIndex;
  final String text;
  final ChatMessageType type;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderNickname,
    this.avatarIndex = 0,
    required this.text,
    this.type = ChatMessageType.chat,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
