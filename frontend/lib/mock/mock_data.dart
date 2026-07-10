import '../models/chat_message.dart';
import '../models/game_result.dart';
import '../models/player.dart';
import '../models/room_summary.dart';

/// LobbyScreen에 표시할 더미 공개방 목록.
const mockPublicRooms = <RoomSummary>[
  RoomSummary(
    code: '1024',
    title: '초보환영 라이어방',
    hostNickname: '방장곰',
    playerCount: 3,
    maxPlayers: 8,
  ),
  RoomSummary(
    code: '3391',
    title: '친목 라이어게임',
    hostNickname: '토끼',
    playerCount: 5,
    maxPlayers: 6,
  ),
  RoomSummary(
    code: '7710',
    title: 'AI 분탕질 즐기는 방',
    hostNickname: '고양이',
    playerCount: 2,
    maxPlayers: 8,
  ),
];

/// RoomScreen의 참가자 목록 더미 데이터.
/// [selfIsHost]가 true면 방을 새로 만든 경우(내가 방장), false면 코드로 입장한 경우다.
List<Player> buildMockPlayers({required bool selfIsHost}) {
  if (selfIsHost) {
    return const [
      Player(id: 'me', nickname: '나', isHost: true, isReady: true),
      Player(id: 'p2', nickname: '토끼', isReady: true),
      Player(id: 'p3', nickname: '고양이'),
      Player(id: 'bot1', nickname: 'AI 봇 1', isBot: true, isReady: true),
    ];
  }
  return const [
    Player(id: 'host1', nickname: '방장곰', isHost: true, isReady: true),
    Player(id: 'p2', nickname: '토끼', isReady: true),
    Player(id: 'me', nickname: '나'),
    Player(id: 'bot1', nickname: 'AI 봇 1', isBot: true, isReady: true),
  ];
}

/// RoomScreen 대기실 채팅 더미 데이터.
const mockRoomChat = <ChatMessage>[
  ChatMessage(
    id: 'sys1',
    sender: 'system',
    text: '토끼님이 입장했습니다.',
    type: ChatMessageType.system,
  ),
  ChatMessage(id: 'c1', sender: '방장곰', text: '카테고리는 음식으로 할게요!'),
  ChatMessage(id: 'c2', sender: '토끼', text: '좋아요 ㅎㅎ'),
];

/// GameScreen 진행 중 채팅 더미 데이터. AI 분탕질 메시지를 함께 섞어둔다.
const mockGameChat = <ChatMessage>[
  ChatMessage(id: 'g1', sender: '방장곰', text: '이건 보통 둥글고 빨간색이에요.'),
  ChatMessage(
    id: 'g2',
    sender: 'AI',
    text: '음... 그거 초록색 아니었나요? 🤔',
    type: ChatMessageType.ai,
  ),
  ChatMessage(id: 'g3', sender: '토끼', text: '저는 껍질을 깎아서 먹어요.'),
  ChatMessage(
    id: 'g4',
    sender: 'AI',
    text: '껍질째 먹는 사람도 많던데, 다들 확실한가요?',
    type: ChatMessageType.ai,
  ),
];

/// VoteScreen에 표시할 투표 후보(자신 제외) 더미 목록.
const mockVoteCandidates = <String>['방장곰', '토끼', '고양이', 'AI 봇 1'];

/// ResultScreen에 표시할 더미 게임 결과.
const mockGameResult = GameResult(
  category: '과일',
  liarNickname: '토끼',
  realWord: '사과',
  fakeWord: '배',
  citizensWin: true,
  summary: '투표로 라이어를 지목하고 정체를 밝혔습니다.',
);
