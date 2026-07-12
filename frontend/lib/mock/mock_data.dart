import '../models/player.dart';
import '../models/room_summary.dart';

/// LobbyScreen에 표시할 더미 공개방 목록.
const mockPublicRooms = <RoomSummary>[
  RoomSummary(
    code: '1024',
    title: '레이니의 방',
    emoji: '🎮',
    category: '동물',
    hostNickname: '레이니',
    playerCount: 4,
    maxPlayers: 8,
  ),
  RoomSummary(
    code: '3391',
    title: '수상한 사람들 🕵',
    emoji: '👥',
    category: '음식',
    hostNickname: '김민준',
    playerCount: 6,
    maxPlayers: 8,
  ),
  RoomSummary(
    code: '7710',
    title: '라이어를 찾아라!',
    emoji: '🔍',
    category: '스포츠',
    hostNickname: '이서연',
    playerCount: 3,
    maxPlayers: 6,
    inProgress: true,
  ),
  RoomSummary(
    code: '5820',
    title: '파티파티',
    emoji: '🌟',
    category: '자유',
    hostNickname: '박지호',
    playerCount: 5,
    maxPlayers: 8,
  ),
];

/// RoomScreen의 참가자(사람) 목록 더미 데이터. AI 봇은 방장이 지정한 수만큼 화면에서 동적으로 추가된다.
/// [selfIsHost]가 true면 방을 새로 만든 경우(내가 방장), false면 코드로 입장한 경우다.
/// 'me'를 제외한 시뮬레이션 플레이어는 항상 준비 완료 상태로 시작한다
/// (실제로 토글할 수 있는 건 'me'뿐이라, 그렇지 않으면 영영 준비되지 않는 인원이 생긴다).
List<Player> buildMockPlayers({required bool selfIsHost}) {
  if (selfIsHost) {
    return const [
      // 방장은 "준비" 버튼이 따로 없고 "시작하기"만 쓰므로 기본으로 준비 완료 상태다.
      Player(id: 'me', nickname: '나', isHost: true, isReady: true),
      Player(id: 'p2', nickname: '토끼', isReady: true),
      Player(id: 'p3', nickname: '고양이', isReady: true),
    ];
  }
  return const [
    Player(id: 'host1', nickname: '방장곰', isHost: true, isReady: true),
    Player(id: 'p2', nickname: '토끼', isReady: true),
    Player(id: 'me', nickname: '나'),
  ];
}

/// RoomScreen에서 고를 수 있는 기본(하드코딩) 카테고리 목록. 방장이 이 방에서 직접 추가한
/// 카테고리는 RoomScreen 내부 상태에만 보관되고 방 종료 시 함께 사라진다.
const mockCategories = <String>['동물', '음식', '스포츠', '영화', '직업', 'K-pop'];

/// 카테고리별 (진짜 제시어, 가짜 제시어) 후보 목록. 실제로는 AI가 생성하지만,
/// 백엔드 연동 전까지는 이 목데이터 중 아직 이번 게임에서 안 쓴 쌍을 무작위로 골라 흉내 낸다.
const mockWordPairsByCategory = <String, List<(String, String)>>{
  '동물': [('돌고래', '범고래'), ('강아지', '늑대'), ('참새', '비둘기')],
  '음식': [('떡볶이', '순대'), ('김밥', '유부초밥'), ('라면', '우동')],
  '스포츠': [('축구', '풋살'), ('배드민턴', '테니스')],
  '영화': [('타이타닉', '포레스트 검프'), ('인셉션', '인터스텔라')],
  '직업': [('의사', '간호사'), ('경찰', '소방관')],
  'K-pop': [('아이돌', '트로트 가수'), ('걸그룹', '보이그룹')],
};

/// 프리셋에 없는 카테고리(자유 입력·AI 랜덤)일 때 쓰는 대체 제시어 풀.
const mockFallbackWordPairs = <(String, String)>[
  ('사과', '배'),
  ('바다', '호수'),
  ('기차', '지하철'),
];

/// AI 훈수 코멘트 흉내용 문구 풀. `{nickname}`은 방금 설명한 플레이어 닉네임으로 치환한다.
const mockAiCommentTemplates = <String>[
  '그게 맞는 설명이긴 한데... 뭔가 이상해',
  '흠 흠 흠 👀',
  '{nickname}님 설명 좀 애매한데요?',
  '어? 그거 앞에서 나온 설명이랑 비슷하지 않나요?',
  '{nickname}님, 그거 진짜 아는 거 맞아요?',
];

/// 회원가입 중복 확인용 더미 목록 (이미 가입되어 있다고 가정하는 값들).
const mockTakenEmails = <String>['test@example.com', 'liar@game.com'];
const mockTakenNicknames = <String>['방장곰', '토끼', '고양이'];
const mockTakenUserIds = <String>['admin', 'liarking'];

class MockFriend {
  final String nickname;
  final int avatarIndex;
  final bool isOnline;
  final String? roomName; // 온라인이면서 방에 있을 때만
  final String? statusText; // 오프라인일 때 "n시간 전" 등

  const MockFriend({
    required this.nickname,
    required this.avatarIndex,
    required this.isOnline,
    this.roomName,
    this.statusText,
  });
}

/// FriendsScreen "친구 목록" 탭 더미 데이터.
const mockFriends = <MockFriend>[
  MockFriend(nickname: '레이니', avatarIndex: 6, isOnline: true, roomName: '레이니의 방'),
  MockFriend(nickname: '하늘이', avatarIndex: 7, isOnline: true),
  MockFriend(nickname: '별빛', avatarIndex: 4, isOnline: false, statusText: '오프라인'),
  MockFriend(nickname: '달토끼', avatarIndex: 5, isOnline: false, statusText: '오프라인'),
];

class MockFriendRequest {
  final String nickname;
  final int avatarIndex;
  final String receivedAt;

  const MockFriendRequest({required this.nickname, required this.avatarIndex, required this.receivedAt});
}

/// FriendsScreen "요청" 탭 더미 데이터.
const mockFriendRequests = <MockFriendRequest>[
  MockFriendRequest(nickname: '초코', avatarIndex: 0, receivedAt: '방금 전'),
  MockFriendRequest(nickname: '바람이', avatarIndex: 2, receivedAt: '1시간 전'),
];
