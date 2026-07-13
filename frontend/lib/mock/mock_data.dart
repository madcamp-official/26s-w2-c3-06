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
    category: '랜덤',
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
/// "랜덤생성"을 고르면 AI가 카테고리 자체를 생성한다(PLAN.md `category: null` 경로).
const mockCategories = <String>['동물', '음식', '스포츠', '영화', '직업', 'K-pop', kAiRandomCategory];

/// "랜덤생성" 칩의 이름. 실제 카테고리가 아니라 "AI가 카테고리까지 생성"을 의미하는
/// 특수 값이라 이름을 상수로 빼서 문자열 오타를 방지한다.
const kAiRandomCategory = '랜덤생성';

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

/// "랜덤생성"을 골랐을 때 AI가 새로 카테고리까지 만들어내는 것을 흉내 내는 풀.
/// 프리셋(`mockWordPairsByCategory`)에는 없는 카테고리들이며, 실제로 골라지면
/// 그 방의 카테고리 목록(`customCategories`)에 추가되어 이후엔 프리셋처럼 다시 고를 수 있다.
const mockAiGeneratedCategoryPool = <String, List<(String, String)>>{
  '우주': [('행성', '위성'), ('로켓', '인공위성')],
  '역사': [('임진왜란', '병자호란'), ('조선', '고려')],
  '악기': [('피아노', '오르간'), ('바이올린', '첼로')],
  '탈것': [('자전거', '오토바이'), ('버스', '기차')],
};

/// 프리셋에 없는 카테고리(자유 입력 등)일 때 쓰는 대체 제시어 풀.
const mockFallbackWordPairs = <(String, String)>[
  ('사과', '배'),
  ('바다', '호수'),
  ('기차', '지하철'),
];

/// 제시어에 대한 AI 설명 흉내용 문구(PLAN.md `explainWordIfUnfamiliar`).
/// "AI 설명보기" 버튼을 눌렀을 때 보여준다. 목록에 없는 단어는 일반 문구로 대체한다.
const _mockWordExplanations = <String, String>{
  '돌고래': '바다에 사는 똑똑한 포유류예요. 무리 지어 다니고 초음파로 소통해요.',
  '범고래': '몸집이 큰 바다 포유류로, 흰색과 검은색 무늬가 특징이에요. "킬러 웨일"이라고도 불려요.',
  '강아지': '사람과 오래 함께해온 반려동물이에요. 충성심이 강하고 후각이 예민해요.',
  '늑대': '개과에 속하는 야생동물로, 무리를 지어 사냥하는 습성이 있어요.',
  '참새': '한국에서 흔히 볼 수 있는 작은 텃새예요. 짹짹 우는 소리가 특징이에요.',
  '비둘기': '도심에서도 흔히 보이는 새로, 방향 감각이 뛰어나 전서구로도 쓰였어요.',
  '떡볶이': '떡을 고추장 양념에 볶은 한국의 대표 분식이에요.',
  '순대': '돼지 창자에 당면 등을 채워 쪄낸 한국 음식이에요.',
  '김밥': '밥과 여러 재료를 김으로 말아 만든 한국식 롤이에요.',
  '유부초밥': '유부 안에 새콤달콤한 밥을 채운 일본식 초밥이에요.',
  '라면': '가늘고 꼬불꼬불한 면을 끓는 물에 익혀 먹는 인스턴트 음식이에요.',
  '우동': '두껍고 쫄깃한 면을 국물에 넣어 먹는 일본식 국수예요.',
  '축구': '11명씩 두 팀이 발로 공을 다뤄 골을 넣는 스포츠예요.',
  '풋살': '축구를 실내 코트에서 5명씩 하는 축소판 버전이에요.',
  '배드민턴': '라켓으로 셔틀콕을 쳐서 네트 너머로 넘기는 스포츠예요.',
  '테니스': '라켓으로 공을 쳐서 네트 너머로 넘기는 스포츠예요.',
  '타이타닉': '1912년 침몰한 여객선을 배경으로 한 유명한 로맨스 영화예요.',
  '포레스트 검프': '순수한 주인공이 미국 현대사를 관통하며 살아가는 이야기를 담은 영화예요.',
  '인셉션': '꿈속에 들어가 생각을 심는다는 설정의 SF 영화예요.',
  '인터스텔라': '인류 생존을 위해 우주로 떠나는 여정을 그린 SF 영화예요.',
  '의사': '환자를 진찰하고 치료하는 의료 전문가예요.',
  '간호사': '환자를 돌보고 의료진을 보조하는 전문가예요.',
  '경찰': '법을 집행하고 시민의 안전을 지키는 공무원이에요.',
  '소방관': '화재를 진압하고 인명을 구조하는 직업이에요.',
  '아이돌': '노래와 춤으로 무대에 서는 대중 가수를 뜻해요.',
  '트로트 가수': '한국 전통 대중가요인 트로트를 부르는 가수예요.',
  '걸그룹': '여성 멤버들로 구성된 아이돌 그룹이에요.',
  '보이그룹': '남성 멤버들로 구성된 아이돌 그룹이에요.',
  '사과': '동그랗고 아삭한 식감의 대표적인 과일이에요.',
  '배': '즙이 많고 단맛이 나는 한국의 대표 과일이에요.',
  '바다': '지구 표면의 넓은 부분을 차지하는 짠물로 이루어진 공간이에요.',
  '호수': '육지로 둘러싸인 민물 또는 짠물의 큰 물웅덩이예요.',
  '기차': '철로 위를 달리는 대중교통 수단이에요.',
  '지하철': '도심 지하를 달리는 전동차 형태의 대중교통이에요.',
};

/// 제시어에 대한 AI 설명을 흉내 낸다. 목데이터에 없는 단어는 일반적인 문구로 대체한다.
String mockExplainWord(String word) {
  return _mockWordExplanations[word] ?? "'$word'는 이번 게임 카테고리와 관련된 단어예요. 다른 플레이어들의 설명을 참고해보세요.";
}

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

/// PLAN.md `GET /api/friends` 응답 계약(`{ uid, nickname, avatarUrl }`) 자체엔 온라인 여부가
/// 없지만(그래서 "참여" 버튼처럼 방 정보에 기대는 UI는 두지 않는다), 접속 여부 표시와
/// 방 초대 가능 여부에는 필요해 [isOnline]을 별도로 둔다. 실제로는 REST가 아니라 소켓
/// 프레즌스로 내려받을 값.
class MockFriend {
  final String nickname;
  final int avatarIndex;
  final bool isOnline;

  const MockFriend({required this.nickname, required this.avatarIndex, this.isOnline = false});
}

/// FriendsScreen "친구 목록" 탭 / RoomScreen "친구 초대" 공용 더미 데이터.
const mockFriends = <MockFriend>[
  MockFriend(nickname: '레이니', avatarIndex: 6, isOnline: true),
  MockFriend(nickname: '하늘이', avatarIndex: 7, isOnline: true),
  MockFriend(nickname: '별빛', avatarIndex: 4),
  MockFriend(nickname: '달토끼', avatarIndex: 5),
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
