/// 채팅 메시지의 종류. PLAN.md 계약(type: 'chat'|'turnDescription'|'aiComment'|'system')과 맞춘다.
enum ChatMessageType { chat, turnDescription, aiComment, system }

ChatMessageType _chatTypeFromString(String raw) {
  switch (raw) {
    case 'turnDescription':
      return ChatMessageType.turnDescription;
    case 'aiComment':
      return ChatMessageType.aiComment;
    case 'system':
      return ChatMessageType.system;
    case 'chat':
    default:
      return ChatMessageType.chat;
  }
}

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

  /// 게임 시작/종료처럼 특별히 눈에 띄어야 하는 시스템 안내 메시지인지. 서버 계약(`type`)과는
  /// 별개로 클라이언트 표시용으로만 쓰는 필드다.
  final bool highlight;

  ChatMessage({
    required this.id,
    required this.senderId,
    this.senderNickname = '',
    this.avatarIndex = 0,
    required this.text,
    this.type = ChatMessageType.chat,
    this.highlight = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isAi => senderId == 'ai';
  bool get isSystem => senderId == 'system';

  /// 서버 chat:message 페이로드(`{ id, senderId, type, text, timestamp }`)를 그대로 파싱한다.
  /// senderNickname/avatarIndex 같은 표시용 값은 서버 계약에 없어(참가자 목록으로 매핑) 비워 두고,
  /// 화면에서 senderId를 닉네임으로 해석한다. game 시작/종료 등 강조 여부(highlight)도 화면에서 판단.
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      type: _chatTypeFromString(json['type'] as String),
      text: json['text'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    );
  }
}
