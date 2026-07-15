import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../api/backend_config.dart';
import '../models/chat_message.dart';
import '../models/player.dart';
import '../models/public_game_state.dart';
import '../models/round_result.dart';

/// PLAN "Socket.IO 이벤트 계약 (MVP)"의 client↔server 이벤트를 그대로 감싼 래퍼.
/// 서버가 페이즈 전이·타이머를 전적으로 소유하므로, 이 클래스는 emit/on 배선만 하고
/// 게임 규칙 판단은 하지 않는다(room_provider가 수신 이벤트로 상태만 갱신).
class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();

  io.Socket? _socket;

  final _roomCreatedCtrl = StreamController<RoomSnapshot>.broadcast();
  final _roomJoinedCtrl = StreamController<RoomSnapshot>.broadcast();
  final _roomRejoinedCtrl = StreamController<RoomRejoinedSnapshot>.broadcast();
  final _roomPublicListCtrl = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _roomPlayerListUpdatedCtrl = StreamController<List<Player>>.broadcast();
  final _roomErrorCtrl = StreamController<String>.broadcast();
  final _roomClosedCtrl = StreamController<void>.broadcast();
  final _roomInvitedCtrl = StreamController<RoomInvite>.broadcast();
  final _chatMessageCtrl = StreamController<ChatMessage>.broadcast();
  final _draftConfigUpdatedCtrl = StreamController<DraftConfig>.broadcast();
  final _customCategoriesUpdatedCtrl = StreamController<List<String>>.broadcast();
  final _gameStartedCtrl = StreamController<GameStarted>.broadcast();
  final _yourWordCtrl = StreamController<YourWord>.broadcast();
  final _turnStartedCtrl = StreamController<TurnStarted>.broadcast();
  final _discussionStartedCtrl = StreamController<int>.broadcast();
  final _discussionAdjustStateCtrl = StreamController<DiscussionAdjustState>.broadcast();
  final _voteStartedCtrl = StreamController<int>.broadcast();
  final _voteProgressCtrl = StreamController<VoteProgress>.broadcast();
  final _roundResolvedCtrl = StreamController<RoundResolved>.broadcast();
  final _liarGuessPromptCtrl = StreamController<int>.broadcast();
  final _roundFinalResultCtrl = StreamController<RoundFinalResult>.broadcast();
  final _gameEndedCtrl = StreamController<void>.broadcast();
  final _connectErrorCtrl = StreamController<String>.broadcast();
  final _disconnectedCtrl = StreamController<void>.broadcast();
  final _llmMockCtrl = StreamController<bool>.broadcast();

  Stream<RoomSnapshot> get onRoomCreated => _roomCreatedCtrl.stream;
  Stream<RoomSnapshot> get onRoomJoined => _roomJoinedCtrl.stream;
  Stream<RoomRejoinedSnapshot> get onRoomRejoined => _roomRejoinedCtrl.stream;
  Stream<List<Map<String, dynamic>>> get onRoomPublicList => _roomPublicListCtrl.stream;
  Stream<List<Player>> get onRoomPlayerListUpdated => _roomPlayerListUpdatedCtrl.stream;
  Stream<String> get onRoomError => _roomErrorCtrl.stream;
  Stream<void> get onRoomClosed => _roomClosedCtrl.stream;
  Stream<RoomInvite> get onRoomInvited => _roomInvitedCtrl.stream;
  Stream<ChatMessage> get onChatMessage => _chatMessageCtrl.stream;
  Stream<DraftConfig> get onDraftConfigUpdated => _draftConfigUpdatedCtrl.stream;
  Stream<List<String>> get onCustomCategoriesUpdated => _customCategoriesUpdatedCtrl.stream;
  Stream<GameStarted> get onGameStarted => _gameStartedCtrl.stream;
  Stream<YourWord> get onYourWord => _yourWordCtrl.stream;
  Stream<TurnStarted> get onTurnStarted => _turnStartedCtrl.stream;
  Stream<int> get onDiscussionStarted => _discussionStartedCtrl.stream;
  Stream<DiscussionAdjustState> get onDiscussionAdjustState => _discussionAdjustStateCtrl.stream;
  Stream<int> get onVoteStarted => _voteStartedCtrl.stream;
  Stream<VoteProgress> get onVoteProgress => _voteProgressCtrl.stream;
  Stream<RoundResolved> get onRoundResolved => _roundResolvedCtrl.stream;
  Stream<int> get onLiarGuessPrompt => _liarGuessPromptCtrl.stream;
  Stream<RoundFinalResult> get onRoundFinalResult => _roundFinalResultCtrl.stream;
  Stream<void> get onGameEnded => _gameEndedCtrl.stream;
  Stream<String> get onConnectError => _connectErrorCtrl.stream;
  /// 예기치 않게 연결이 끊겼을 때만 발생(우리가 새로 연결하려고 직접 끊은 경우는 제외 —
  /// connect() 참고: 콜백이 잡고 있던 소켓이 더 이상 _socket이 아니면 무시한다).
  Stream<void> get onDisconnected => _disconnectedCtrl.stream;
  /// 백엔드가 실제 LLM 대신 mock 응답으로 동작 중인지(연결마다 서버가 한 번 알려줌).
  Stream<bool> get onLlmMode => _llmMockCtrl.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Firebase ID 토큰으로 handshake. 소켓은 세션당 하나만 유지한다.
  void connect(String idToken) {
    disconnect();

    final socket = io.io(
      BackendConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': idToken})
          .build(),
    );
    _socket = socket;

    socket.onConnectError((data) => _connectErrorCtrl.add(data?.toString() ?? 'connect_error'));
    socket.onError((data) => _connectErrorCtrl.add(data?.toString() ?? 'error'));
    // 우리가 connect()/disconnect()로 직접 끊은 경우엔 그사이 _socket이 null이거나 새
    // 소켓으로 이미 바뀌어 있으므로, 이 클로저가 잡고 있는 socket과 다르면 무시한다.
    socket.onDisconnect((_) {
      if (_socket != socket) return;
      _disconnectedCtrl.add(null);
    });

    socket.on('llm:mode', (data) => _llmMockCtrl.add(_map(data)['mock'] as bool? ?? false));
    socket.on('room:created', (data) => _roomCreatedCtrl.add(RoomSnapshot.fromJson(_map(data))));
    socket.on('room:joined', (data) => _roomJoinedCtrl.add(RoomSnapshot.fromJson(_map(data))));
    socket.on(
      'room:rejoined',
      (data) => _roomRejoinedCtrl.add(RoomRejoinedSnapshot.fromJson(_map(data))),
    );
    socket.on('room:publicList', (data) {
      final rooms = (_map(data)['rooms'] as List).cast<Map<String, dynamic>>();
      _roomPublicListCtrl.add(rooms);
    });
    socket.on('room:playerListUpdated', (data) {
      final players = (_map(data)['players'] as List)
          .map((e) => Player.fromJson(e as Map<String, dynamic>))
          .toList();
      _roomPlayerListUpdatedCtrl.add(players);
    });
    socket.on('room:error', (data) => _roomErrorCtrl.add(_map(data)['message'] as String? ?? '알 수 없는 오류'));
    socket.on('room:closed', (_) => _roomClosedCtrl.add(null));
    socket.on('room:invited', (data) => _roomInvitedCtrl.add(RoomInvite.fromJson(_map(data))));

    socket.on('chat:message', (data) => _chatMessageCtrl.add(ChatMessage.fromJson(_map(data))));
    socket.on(
      'game:draftConfigUpdated',
      (data) => _draftConfigUpdatedCtrl.add(DraftConfig.fromJson(_map(data))),
    );
    socket.on(
      'room:customCategoriesUpdated',
      (data) => _customCategoriesUpdatedCtrl.add((_map(data)['customCategories'] as List).cast<String>()),
    );
    socket.on('game:started', (data) => _gameStartedCtrl.add(GameStarted.fromJson(_map(data))));
    socket.on('round:yourWord', (data) => _yourWordCtrl.add(YourWord.fromJson(_map(data))));
    socket.on('turn:started', (data) => _turnStartedCtrl.add(TurnStarted.fromJson(_map(data))));
    socket.on(
      'discussion:started',
      (data) => _discussionStartedCtrl.add(_map(data)['timeLimitSec'] as int),
    );
    socket.on(
      'discussion:myAdjustState',
      (data) => _discussionAdjustStateCtrl.add(DiscussionAdjustState.fromJson(_map(data))),
    );
    socket.on('vote:started', (data) => _voteStartedCtrl.add(_map(data)['timeLimitSec'] as int));
    socket.on('vote:progress', (data) => _voteProgressCtrl.add(VoteProgress.fromJson(_map(data))));
    socket.on('round:resolved', (data) => _roundResolvedCtrl.add(RoundResolved.fromJson(_map(data))));
    socket.on('liar:guessPrompt', (data) => _liarGuessPromptCtrl.add(_map(data)['timeLimitSec'] as int));
    socket.on(
      'round:finalResult',
      (data) => _roundFinalResultCtrl.add(RoundFinalResult.fromJson(_map(data))),
    );
    socket.on('game:ended', (_) => _gameEndedCtrl.add(null));

    socket.connect();
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  Map<String, dynamic> _map(dynamic data) => Map<String, dynamic>.from(data as Map);

  // ── Client → Server ──

  void createRoom({
    required String nickname,
    required String visibility,
    required int maxPlayers,
    String? title,
    String? emoji,
  }) {
    _socket?.emit('room:create', {
      'nickname': nickname,
      'visibility': visibility,
      'maxPlayers': maxPlayers,
      if (title != null) 'title': title,
      if (emoji != null) 'emoji': emoji,
    });
  }

  /// 현재 방으로 친구를 초대한다(방장/참가자 공용). 대상이 온라인이면 room:invited를 받는다.
  void inviteFriend(String toUid) {
    _socket?.emit('friend:invite', {'toUid': toUid});
  }

  void listPublicRooms() {
    _socket?.emit('room:listPublic', {});
  }

  void joinRoom({required String roomCode, required String nickname}) {
    _socket?.emit('room:join', {'roomCode': roomCode, 'nickname': nickname});
  }

  /// 새로고침 등으로 소켓이 끊겼다가 다시 붙었을 때, 이전에 있던 방으로 복귀를 시도한다.
  void rejoinRoom({required String roomCode}) {
    _socket?.emit('room:rejoin', {'roomCode': roomCode});
  }

  void leaveRoom() {
    _socket?.emit('room:leave', {});
  }

  void setReady(bool isReady) {
    _socket?.emit('player:ready', {'isReady': isReady});
  }

  void sendChat(String text) {
    _socket?.emit('chat:send', {'text': text});
  }

  /// 방장이 대기방에서 봇 수/카테고리를 바꿀 때마다 호출 — 다른 참가자 화면에 실시간
  /// 반영하기 위한 것으로, game:configure(실제 시작)와는 별개다.
  void updateDraftConfig({required String? category, required int aiBotCount}) {
    _socket?.emit('game:draftConfig', {'category': category, 'aiBotCount': aiBotCount});
  }

  /// [category]가 null이면 AI가 카테고리까지 랜덤 생성(PLAN 계약).
  void configureGame({required String? category, required int aiBotCount}) {
    _socket?.emit('game:configure', {'category': category, 'aiBotCount': aiBotCount});
  }

  void submitDescription(String text) {
    _socket?.emit('turn:submitDescription', {'text': text});
  }

  /// 토론 시간을 ±10초 조절한다. 방장 전용이 아니라 누구나 호출할 수 있다.
  void adjustDiscussionTime(int deltaSec) {
    _socket?.emit('discussion:adjustTime', {'deltaSec': deltaSec});
  }

  void castVote(String votedPlayerId) {
    _socket?.emit('vote:cast', {'votedPlayerId': votedPlayerId});
  }

  void guessWord(String guess) {
    _socket?.emit('liar:guessWord', {'guess': guess});
  }

  void dispose() {
    disconnect();
    _roomCreatedCtrl.close();
    _roomJoinedCtrl.close();
    _roomRejoinedCtrl.close();
    _roomPublicListCtrl.close();
    _roomPlayerListUpdatedCtrl.close();
    _roomErrorCtrl.close();
    _roomClosedCtrl.close();
    _roomInvitedCtrl.close();
    _chatMessageCtrl.close();
    _draftConfigUpdatedCtrl.close();
    _customCategoriesUpdatedCtrl.close();
    _gameStartedCtrl.close();
    _yourWordCtrl.close();
    _turnStartedCtrl.close();
    _discussionStartedCtrl.close();
    _voteStartedCtrl.close();
    _voteProgressCtrl.close();
    _roundResolvedCtrl.close();
    _liarGuessPromptCtrl.close();
    _roundFinalResultCtrl.close();
    _gameEndedCtrl.close();
    _connectErrorCtrl.close();
    _disconnectedCtrl.close();
  }
}

/// 방장이 대기방에서 고르고 있는(아직 시작 전) 봇 수/카테고리. game:draftConfigUpdated로
/// 실시간 브로드캐스트되며, room:created/joined/rejoined 스냅샷에도 현재 값이 포함된다.
class DraftConfig {
  final String? category;
  final int aiBotCount;

  const DraftConfig({required this.category, required this.aiBotCount});

  factory DraftConfig.fromJson(Map<String, dynamic> json) {
    return DraftConfig(
      category: json['category'] as String?,
      aiBotCount: json['aiBotCount'] as int? ?? 0,
    );
  }
}

/// room:invited 페이로드: `{ roomCode, title, emoji, fromUid, fromNickname }`.
/// 친구가 자기 방으로 초대했을 때 온라인 상태인 대상 소켓에 도착한다. 로비에서 수신해
/// 알림을 띄우고, 수락 시 해당 roomCode로 입장한다.
class RoomInvite {
  final String roomCode;
  final String title;
  final String emoji;
  final String fromUid;
  final String fromNickname;

  const RoomInvite({
    required this.roomCode,
    required this.title,
    required this.emoji,
    required this.fromUid,
    required this.fromNickname,
  });

  factory RoomInvite.fromJson(Map<String, dynamic> json) {
    return RoomInvite(
      roomCode: json['roomCode'] as String,
      title: (json['title'] as String?) ?? '',
      emoji: (json['emoji'] as String?) ?? '🎮',
      fromUid: (json['fromUid'] as String?) ?? '',
      fromNickname: (json['fromNickname'] as String?) ?? '',
    );
  }
}

/// room:created/room:joined 페이로드:
/// `{ roomCode, hostId, visibility, players, customCategories, draftConfig }`.
class RoomSnapshot {
  final String roomCode;
  final String hostId;
  final String title;
  final String emoji;
  final String visibility;
  final int maxPlayers;
  final List<Player> players;

  /// 이 방에서 지금까지 사용된 카테고리(방장 입력·AI 랜덤 포함). 다음 게임 선택지로 제시한다.
  final List<String> customCategories;
  final DraftConfig draftConfig;

  const RoomSnapshot({
    required this.roomCode,
    required this.hostId,
    this.title = '',
    this.emoji = '🎮',
    required this.visibility,
    required this.maxPlayers,
    required this.players,
    required this.customCategories,
    required this.draftConfig,
  });

  factory RoomSnapshot.fromJson(Map<String, dynamic> json) {
    return RoomSnapshot(
      roomCode: json['roomCode'] as String,
      hostId: json['hostId'] as String,
      title: (json['title'] as String?) ?? '',
      emoji: (json['emoji'] as String?) ?? '🎮',
      visibility: json['visibility'] as String,
      maxPlayers: (json['maxPlayers'] as num?)?.toInt() ?? 0,
      players: (json['players'] as List)
          .map((e) => Player.fromJson(e as Map<String, dynamic>))
          .toList(),
      customCategories: (json['customCategories'] as List?)?.cast<String>() ?? const [],
      draftConfig: DraftConfig.fromJson(Map<String, dynamic>.from(json['draftConfig'] as Map)),
    );
  }
}

/// room:rejoined 페이로드:
/// `{ roomCode, hostId, visibility, players, customCategories, chatLog, currentGame, draftConfig }`.
/// currentGame은 대기 중(게임 시작 전)이면 null.
class RoomRejoinedSnapshot {
  final String roomCode;
  final String hostId;
  final String title;
  final String emoji;
  final String visibility;
  final int maxPlayers;
  final List<Player> players;
  final List<String> customCategories;
  final List<ChatMessage> chatLog;
  final PublicGameState? currentGame;
  final DraftConfig draftConfig;

  const RoomRejoinedSnapshot({
    required this.roomCode,
    required this.hostId,
    this.title = '',
    this.emoji = '🎮',
    required this.visibility,
    required this.maxPlayers,
    required this.players,
    required this.customCategories,
    required this.chatLog,
    this.currentGame,
    required this.draftConfig,
  });

  factory RoomRejoinedSnapshot.fromJson(Map<String, dynamic> json) {
    return RoomRejoinedSnapshot(
      roomCode: json['roomCode'] as String,
      hostId: json['hostId'] as String,
      title: (json['title'] as String?) ?? '',
      emoji: (json['emoji'] as String?) ?? '🎮',
      visibility: json['visibility'] as String,
      maxPlayers: (json['maxPlayers'] as num?)?.toInt() ?? 0,
      players: (json['players'] as List)
          .map((e) => Player.fromJson(e as Map<String, dynamic>))
          .toList(),
      customCategories: (json['customCategories'] as List?)?.cast<String>() ?? const [],
      chatLog: (json['chatLog'] as List)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentGame: json['currentGame'] == null
          ? null
          : PublicGameState.fromJson(Map<String, dynamic>.from(json['currentGame'] as Map)),
      draftConfig: DraftConfig.fromJson(Map<String, dynamic>.from(json['draftConfig'] as Map)),
    );
  }
}

/// game:started 페이로드: `{ gameNumber, category, participants }`.
/// `participants`는 봇 포함 전체 참가자(id/nickname/isBot) — room:playerListUpdated는
/// 사람만 추적하므로 투표 후보·턴 배너에 봇을 표시하려면 이 목록이 필요하다.
class GameStarted {
  final int gameNumber;
  final String category;
  final List<Player> participants;

  const GameStarted({
    required this.gameNumber,
    required this.category,
    required this.participants,
  });

  factory GameStarted.fromJson(Map<String, dynamic> json) {
    return GameStarted(
      gameNumber: json['gameNumber'] as int,
      category: json['category'] as String,
      participants: (json['participants'] as List)
          .map((e) => Player.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// round:yourWord 페이로드: `{ word, explanation? }`.
/// `explanation`은 서버가 모든 제시어에 대해 난이도와 무관하게 미리 생성해 함께 내려주는
/// 부가 설명이다(생성 실패 시에만 생략). 클라이언트는 "AI 설명보기"로 원할 때 펼쳐 본다.
class YourWord {
  final String word;
  final String? explanation;

  const YourWord({required this.word, this.explanation});

  factory YourWord.fromJson(Map<String, dynamic> json) {
    return YourWord(
      word: json['word'] as String,
      explanation: json['explanation'] as String?,
    );
  }
}

/// turn:started 페이로드: `{ playerId, timeLimitSec }`.
class TurnStarted {
  final String playerId;
  final int timeLimitSec;

  const TurnStarted({required this.playerId, required this.timeLimitSec});

  factory TurnStarted.fromJson(Map<String, dynamic> json) {
    return TurnStarted(
      playerId: json['playerId'] as String,
      timeLimitSec: json['timeLimitSec'] as int,
    );
  }
}

/// discussion:myAdjustState 페이로드: `{ canShorten, canExtend }`. 방 전체가 아니라
/// 내 소켓에만 오는 개인화된 상태 — 토론 단축/연장 버튼을 각각 한 번씩만 쓸 수 있어서다.
class DiscussionAdjustState {
  final bool canShorten;
  final bool canExtend;

  const DiscussionAdjustState({required this.canShorten, required this.canExtend});

  factory DiscussionAdjustState.fromJson(Map<String, dynamic> json) {
    return DiscussionAdjustState(
      canShorten: json['canShorten'] as bool? ?? true,
      canExtend: json['canExtend'] as bool? ?? true,
    );
  }
}

/// vote:progress 페이로드: `{ votesInCount, totalCount }` (식별정보 없이 진행률만).
class VoteProgress {
  final int votesInCount;
  final int totalCount;

  const VoteProgress({required this.votesInCount, required this.totalCount});

  factory VoteProgress.fromJson(Map<String, dynamic> json) {
    return VoteProgress(
      votesInCount: json['votesInCount'] as int,
      totalCount: json['totalCount'] as int,
    );
  }
}
