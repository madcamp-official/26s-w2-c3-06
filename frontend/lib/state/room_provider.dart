import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../models/game_phase.dart';
import '../models/game_result.dart';
import '../models/player.dart';
import '../models/room_summary.dart';
import '../models/round_result.dart';
import '../services/room_session_store.dart';
import '../services/socket_service.dart';

GamePhase _phaseFromServerString(String raw) {
  switch (raw) {
    case 'describing':
      return GamePhase.describing;
    case 'discussion':
      return GamePhase.discussion;
    case 'voting':
      return GamePhase.voting;
    case 'resolution':
      return GamePhase.resolution;
    case 'liarGuess':
      return GamePhase.liarGuess;
    case 'ended':
      return GamePhase.ended;
    case 'setup':
    default:
      // setup은 단어 배정 직전의 찰나뿐이라 rejoin 시점엔 거의 관측되지 않는다.
      // 안전하게 describing으로 취급하면, 뒤이어 오는 round:yourWord/turn:started가
      // 곧바로 정확한 상태로 덮어써준다.
      return GamePhase.describing;
  }
}

/// 방/게임 진행 상태. 서버(PLAN Socket.IO 이벤트 계약)가 전적으로 소유하는 상태를
/// 그대로 반영만 한다 — 클라이언트에서 판정·페이즈 전이를 계산하지 않는다.
class RoomViewState {
  final String? roomCode;
  final String? hostId;
  final String? title;
  final String? emoji;
  final String? visibility;

  /// 방 생성 시 호스트가 지정한 최대 인원. room:created/joined 응답엔 없어 호스트가
  /// 생성할 때 로컬로 echo해두고, 참가자는 room:publicList 조회로만 알 수 있어 값이
  /// 없으면(비공개방 참가 등) null로 남는다.
  final int? maxPlayers;

  final List<Player> players;

  /// 방장이 대기방에서 고르고 있는(아직 시작 전) 카테고리/봇 수 — 다른 참가자에게도
  /// 실시간으로 보여주기 위한 것으로, game:draftConfigUpdated로 갱신된다.
  final String? draftCategory;
  final int draftAiBotCount;

  /// 이 방에서 지금까지 사용된 카테고리(방장 입력·AI 랜덤 포함). 대기방 카테고리 칩에
  /// 프리셋과 함께 재사용 선택지로 노출한다. room:created/joined/rejoined 스냅샷으로
  /// 초기화되고, 새 게임 시작 때마다 room:customCategoriesUpdated로 갱신된다.
  final List<String> customCategories;

  /// 봇 포함 전체 참가자(game:started에서 옴). 대기 중(게임 시작 전)엔 비어 있고,
  /// 턴 배너·투표 후보 표시에는 이 목록을 쓴다(players는 사람만 있어 봇을 못 찾음).
  final List<Player> participants;

  final List<ChatMessage> chatLog;
  final GamePhase phase;

  final int? gameNumber;
  final String? category;

  /// 본인에게 배정된 단어. 진짜/가짜 여부는 서버가 절대 알려주지 않는다.
  final String? myWord;

  /// AI가 생소한 단어라고 판단했을 때만 내려오는 부가 설명(round:yourWord.explanation).
  final String? myWordExplanation;

  final String? currentTurnPlayerId;
  final int? turnTimeLimitSec;

  final int? voteTimeLimitSec;
  final int? votesInCount;
  final int? totalVoteCount;

  final RoundResolved? roundResolved;

  /// null이 아니면 "나"에게 역전승 기회가 온 것(liar:guessPrompt는 지목된 소켓에만 전송됨).
  final int? liarGuessTimeLimitSec;

  /// 현재 진행 중인 제한시간 행동(턴 설명/토론/투표/역전승 시도)의 종료 예상 시각.
  /// turn:started/discussion:started/vote:started/liar:guessPrompt 수신 시각 + timeLimitSec로
  /// 프론트가 로컬 계산한 값이라, 위젯이 이걸로 1초 단위 카운트다운을 그린다(CountdownText 참고).
  /// 재접속(rejoin) 시에는 서버가 원래 시작 시각을 다시 안 보내주므로 복원되지 않는다.
  final DateTime? phaseDeadline;

  final RoundFinalResult? finalResult;

  final List<RoomSummary> publicRooms;
  final bool socketConnected;

  const RoomViewState({
    this.roomCode,
    this.hostId,
    this.title,
    this.emoji,
    this.visibility,
    this.maxPlayers,
    this.draftCategory,
    this.draftAiBotCount = 0,
    this.customCategories = const [],
    this.players = const [],
    this.participants = const [],
    this.chatLog = const [],
    this.phase = GamePhase.waiting,
    this.gameNumber,
    this.category,
    this.myWord,
    this.myWordExplanation,
    this.currentTurnPlayerId,
    this.turnTimeLimitSec,
    this.voteTimeLimitSec,
    this.votesInCount,
    this.totalVoteCount,
    this.roundResolved,
    this.liarGuessTimeLimitSec,
    this.phaseDeadline,
    this.finalResult,
    this.publicRooms = const [],
    this.socketConnected = false,
  });

  bool isMyTurn(String? myUid) => myUid != null && currentTurnPlayerId == myUid;

  bool isAccusedLiar(String? myUid) =>
      myUid != null && roundResolved?.votedOutId == myUid && (roundResolved?.wasLiar ?? false);

  /// 봇 포함 전체 참가자 중에서 닉네임을 찾는다. players(사람만)로는 봇을 못 찾는다.
  String nicknameOf(String id) {
    final found = participants.where((p) => p.id == id).firstOrNull ??
        players.where((p) => p.id == id).firstOrNull;
    return found?.nickname ?? id;
  }

  /// ResultScreen에 넘길 표시용 모델. finalResult가 아직 없으면 null.
  GameResult? get gameResult {
    final resolved = roundResolved;
    final result = finalResult;
    if (resolved == null || result == null) return null;
    final accused = resolved.votedOutId == null ? null : nicknameOf(resolved.votedOutId!);
    return GameResult(
      category: category,
      realWord: resolved.realWord,
      liarWord: resolved.liarWord,
      citizensWin: result.citizensWin,
      accusedNickname: accused,
      wasLiar: resolved.wasLiar,
      liarNickname: nicknameOf(resolved.liarId),
      liarGuessCorrect: result.liarGuessCorrect,
      liarGuess: result.liarGuess,
    );
  }

  RoomViewState copyWith({
    String? roomCode,
    String? hostId,
    String? title,
    String? emoji,
    String? visibility,
    int? maxPlayers,
    bool clearMaxPlayers = false,
    String? draftCategory,
    bool clearDraftCategory = false,
    int? draftAiBotCount,
    List<String>? customCategories,
    List<Player>? players,
    List<Player>? participants,
    List<ChatMessage>? chatLog,
    GamePhase? phase,
    int? gameNumber,
    String? category,
    String? myWord,
    String? myWordExplanation,
    bool clearMyWordExplanation = false,
    String? currentTurnPlayerId,
    bool clearCurrentTurnPlayerId = false,
    int? turnTimeLimitSec,
    int? voteTimeLimitSec,
    int? votesInCount,
    int? totalVoteCount,
    RoundResolved? roundResolved,
    bool clearRoundResolved = false,
    int? liarGuessTimeLimitSec,
    bool clearLiarGuessTimeLimitSec = false,
    DateTime? phaseDeadline,
    bool clearPhaseDeadline = false,
    RoundFinalResult? finalResult,
    bool clearFinalResult = false,
    List<RoomSummary>? publicRooms,
    bool? socketConnected,
  }) {
    return RoomViewState(
      roomCode: roomCode ?? this.roomCode,
      hostId: hostId ?? this.hostId,
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      visibility: visibility ?? this.visibility,
      maxPlayers: clearMaxPlayers ? null : (maxPlayers ?? this.maxPlayers),
      draftCategory: clearDraftCategory ? null : (draftCategory ?? this.draftCategory),
      draftAiBotCount: draftAiBotCount ?? this.draftAiBotCount,
      customCategories: customCategories ?? this.customCategories,
      players: players ?? this.players,
      participants: participants ?? this.participants,
      chatLog: chatLog ?? this.chatLog,
      phase: phase ?? this.phase,
      gameNumber: gameNumber ?? this.gameNumber,
      category: category ?? this.category,
      myWord: myWord ?? this.myWord,
      myWordExplanation:
          clearMyWordExplanation ? null : (myWordExplanation ?? this.myWordExplanation),
      currentTurnPlayerId:
          clearCurrentTurnPlayerId ? null : (currentTurnPlayerId ?? this.currentTurnPlayerId),
      turnTimeLimitSec: turnTimeLimitSec ?? this.turnTimeLimitSec,
      voteTimeLimitSec: voteTimeLimitSec ?? this.voteTimeLimitSec,
      votesInCount: votesInCount ?? this.votesInCount,
      totalVoteCount: totalVoteCount ?? this.totalVoteCount,
      roundResolved: clearRoundResolved ? null : (roundResolved ?? this.roundResolved),
      liarGuessTimeLimitSec: clearLiarGuessTimeLimitSec
          ? null
          : (liarGuessTimeLimitSec ?? this.liarGuessTimeLimitSec),
      phaseDeadline: clearPhaseDeadline ? null : (phaseDeadline ?? this.phaseDeadline),
      finalResult: clearFinalResult ? null : (finalResult ?? this.finalResult),
      publicRooms: publicRooms ?? this.publicRooms,
      socketConnected: socketConnected ?? this.socketConnected,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class RoomNotifier extends Notifier<RoomViewState> {
  final _socket = SocketService.instance;

  @override
  RoomViewState build() {
    _wireSocketListeners();
    return const RoomViewState();
  }

  /// 서버가 보낸 timeLimitSec(총 허용 시간)을 수신 시각 기준 종료 시각으로 변환한다.
  /// CountdownText가 이 값으로 1초 단위 카운트다운을 그린다.
  DateTime _deadlineFrom(int timeLimitSec) =>
      DateTime.now().add(Duration(seconds: timeLimitSec));

  void _wireSocketListeners() {
    _socket.onRoomCreated.listen((snapshot) => _applySnapshot(snapshot));
    _socket.onRoomJoined.listen((snapshot) => _applySnapshot(snapshot));
    _socket.onRoomRejoined.listen((snapshot) => _applyRejoin(snapshot));
    _socket.onRoomPublicList.listen((rooms) {
      state = state.copyWith(
        publicRooms: rooms.map((e) => RoomSummary.fromJson(e)).toList(),
      );
    });
    _socket.onRoomPlayerListUpdated.listen((players) {
      state = state.copyWith(players: players);
    });
    _socket.onRoomClosed.listen((_) => reset());
    _socket.onChatMessage.listen((message) {
      state = state.copyWith(chatLog: [...state.chatLog, message]);
    });
    _socket.onDraftConfigUpdated.listen((config) {
      state = state.copyWith(
        draftCategory: config.category,
        clearDraftCategory: config.category == null,
        draftAiBotCount: config.aiBotCount,
      );
    });
    _socket.onCustomCategoriesUpdated.listen((categories) {
      state = state.copyWith(customCategories: categories);
    });
    _socket.onGameStarted.listen((event) {
      state = state.copyWith(
        phase: GamePhase.describing,
        gameNumber: event.gameNumber,
        category: event.category,
        participants: event.participants,
        chatLog: const [],
        clearCurrentTurnPlayerId: true,
        clearRoundResolved: true,
        clearLiarGuessTimeLimitSec: true,
        clearFinalResult: true,
        clearMyWordExplanation: true,
        clearPhaseDeadline: true,
      );
    });
    _socket.onYourWord.listen((yourWord) {
      state = state.copyWith(
        myWord: yourWord.word,
        myWordExplanation: yourWord.explanation,
        clearMyWordExplanation: yourWord.explanation == null,
      );
    });
    _socket.onTurnStarted.listen((event) {
      state = state.copyWith(
        phase: GamePhase.describing,
        currentTurnPlayerId: event.playerId,
        turnTimeLimitSec: event.timeLimitSec,
        phaseDeadline: _deadlineFrom(event.timeLimitSec),
      );
    });
    _socket.onDiscussionStarted.listen((timeLimitSec) {
      // 설명 페이즈 종료 — "현재 턴" 배너/입력창을 내린다.
      state = state.copyWith(
        phase: GamePhase.discussion,
        clearCurrentTurnPlayerId: true,
        phaseDeadline: _deadlineFrom(timeLimitSec),
      );
    });
    _socket.onVoteStarted.listen((timeLimitSec) {
      state = state.copyWith(
        phase: GamePhase.voting,
        voteTimeLimitSec: timeLimitSec,
        votesInCount: 0,
        totalVoteCount: state.participants.length,
        phaseDeadline: _deadlineFrom(timeLimitSec),
      );
    });
    _socket.onVoteProgress.listen((progress) {
      state = state.copyWith(
        votesInCount: progress.votesInCount,
        totalVoteCount: progress.totalCount,
      );
    });
    _socket.onRoundResolved.listen((resolved) {
      state = state.copyWith(
        phase: GamePhase.resolution,
        roundResolved: resolved,
        clearPhaseDeadline: true,
      );
    });
    _socket.onLiarGuessPrompt.listen((timeLimitSec) {
      state = state.copyWith(
        phase: GamePhase.liarGuess,
        liarGuessTimeLimitSec: timeLimitSec,
        phaseDeadline: _deadlineFrom(timeLimitSec),
      );
    });
    _socket.onRoundFinalResult.listen((result) {
      state = state.copyWith(finalResult: result);
    });
    _socket.onGameEnded.listen((_) {
      state = state.copyWith(phase: GamePhase.ended, clearPhaseDeadline: true);
    });
  }

  void _applySnapshot(RoomSnapshot snapshot) {
    state = state.copyWith(
      roomCode: snapshot.roomCode,
      hostId: snapshot.hostId,
      title: snapshot.title,
      emoji: snapshot.emoji,
      visibility: snapshot.visibility,
      players: snapshot.players,
      phase: GamePhase.waiting,
      draftCategory: snapshot.draftConfig.category,
      clearDraftCategory: snapshot.draftConfig.category == null,
      draftAiBotCount: snapshot.draftConfig.aiBotCount,
      customCategories: snapshot.customCategories,
    );
    RoomSessionStore.instance.saveRoomCode(snapshot.roomCode);
  }

  /// room:rejoin 성공 시 방/채팅/게임 진행 상태를 새로고침 이전과 최대한 동일하게 복원한다.
  /// 서버가 이미 공개해도 되는 정보만 골라 보내주므로(gameEngine.toPublicGameState 참고),
  /// 여기서는 그걸 그대로 반영만 한다.
  void _applyRejoin(RoomRejoinedSnapshot snapshot) {
    final game = snapshot.currentGame;
    RoomSessionStore.instance.saveRoomCode(snapshot.roomCode);

    if (game == null) {
      state = state.copyWith(
        roomCode: snapshot.roomCode,
        hostId: snapshot.hostId,
        title: snapshot.title,
        emoji: snapshot.emoji,
        visibility: snapshot.visibility,
        players: snapshot.players,
        participants: const [],
        chatLog: snapshot.chatLog,
        phase: GamePhase.waiting,
        clearCurrentTurnPlayerId: true,
        clearRoundResolved: true,
        clearLiarGuessTimeLimitSec: true,
        clearFinalResult: true,
        clearMyWordExplanation: true,
        draftCategory: snapshot.draftConfig.category,
        clearDraftCategory: snapshot.draftConfig.category == null,
        draftAiBotCount: snapshot.draftConfig.aiBotCount,
        customCategories: snapshot.customCategories,
      );
      return;
    }

    final phase = _phaseFromServerString(game.phase);
    final round = game.currentRound;

    String? currentTurnPlayerId;
    if (phase == GamePhase.describing && round != null) {
      final idx = round.turns.length;
      currentTurnPlayerId =
          idx < game.playerOrder.length ? game.playerOrder[idx] : null;
    }

    RoundResolved? roundResolved;
    if (game.realWord != null && game.liarWord != null && game.liarId != null) {
      roundResolved = RoundResolved(
        votedOutId: game.votedOutId,
        wasLiar: game.wasLiar ?? false,
        realWord: game.realWord!,
        liarWord: game.liarWord!,
        liarId: game.liarId!,
      );
    }

    RoundFinalResult? finalResult;
    if (game.winner != null) {
      finalResult =
          RoundFinalResult(liarGuessCorrect: game.liarGuessCorrect, winner: game.winner!);
    }

    state = state.copyWith(
      roomCode: snapshot.roomCode,
      hostId: snapshot.hostId,
      title: snapshot.title,
      emoji: snapshot.emoji,
      visibility: snapshot.visibility,
      players: snapshot.players,
      participants: game.participants,
      chatLog: snapshot.chatLog,
      phase: phase,
      gameNumber: game.gameNumber,
      category: game.category,
      currentTurnPlayerId: currentTurnPlayerId,
      clearCurrentTurnPlayerId: currentTurnPlayerId == null,
      roundResolved: roundResolved,
      clearRoundResolved: roundResolved == null,
      finalResult: finalResult,
      clearFinalResult: finalResult == null,
      draftCategory: snapshot.draftConfig.category,
      clearDraftCategory: snapshot.draftConfig.category == null,
      draftAiBotCount: snapshot.draftConfig.aiBotCount,
      customCategories: snapshot.customCategories,
    );
    // 게임 중이었다면 서버가 round:yourWord(항상)/liar:guessPrompt(해당자만)를 뒤이어
    // 다시 보내주므로, myWord·liarGuessTimeLimitSec는 기존 리스너가 곧 채워준다.
  }

  void connect(String idToken) {
    state = state.copyWith(socketConnected: true);
    _socket.connect(idToken);
  }

  void disconnectSocket() {
    _socket.disconnect();
    state = state.copyWith(socketConnected: false);
  }

  void createRoom({
    required String nickname,
    required String visibility,
    required int maxPlayers,
    String? title,
    String? emoji,
  }) {
    state = state.copyWith(maxPlayers: maxPlayers);
    _socket.createRoom(
      nickname: nickname,
      visibility: visibility,
      maxPlayers: maxPlayers,
      title: title,
      emoji: emoji,
    );
  }

  /// 현재 방으로 친구 초대(friend:invite). 대상이 온라인이면 room:invited를 받는다.
  void inviteFriend(String toUid) => _socket.inviteFriend(toUid);

  void setReady(bool isReady) => _socket.setReady(isReady);

  void refreshPublicRooms() => _socket.listPublicRooms();

  void joinRoom({required String roomCode, required String nickname}) {
    _socket.joinRoom(roomCode: roomCode, nickname: nickname);
  }

  void rejoinRoom({required String roomCode}) {
    _socket.rejoinRoom(roomCode: roomCode);
  }

  void leaveRoom() {
    _socket.leaveRoom();
    reset();
  }

  void sendChat(String text) => _socket.sendChat(text);

  void configureGame({required String? category, required int aiBotCount}) {
    _socket.configureGame(category: category, aiBotCount: aiBotCount);
  }

  /// 방장이 대기방에서 봇 수/카테고리를 바꿀 때마다 호출 — 다른 참가자 화면에도
  /// 실시간으로 보이도록 서버에 반영을 요청한다(아직 게임을 시작하는 건 아님).
  void updateDraftConfig({required String? category, required int aiBotCount}) {
    _socket.updateDraftConfig(category: category, aiBotCount: aiBotCount);
  }

  void submitDescription(String text) => _socket.submitDescription(text);

  void skipTurn() => _socket.skipTurn();

  void skipDiscussion() => _socket.skipDiscussion();

  void castVote(String votedPlayerId) => _socket.castVote(votedPlayerId);

  void guessWord(String guess) => _socket.guessWord(guess);

  /// 방 나가기/소켓 재연결 등으로 완전히 초기 상태로 되돌릴 때.
  void reset() {
    state = const RoomViewState();
    RoomSessionStore.instance.clear();
  }
}

final roomProvider = NotifierProvider<RoomNotifier, RoomViewState>(RoomNotifier.new);

/// room:error는 1회성 알림(스낵바 등)이라 지속 상태가 아니라 별도 스트림으로 노출.
final roomErrorProvider = StreamProvider<String>((ref) {
  return SocketService.instance.onRoomError;
});

/// room:invited도 1회성 알림이라 별도 스트림으로 노출. 로비가 구독해 초대 스낵바를 띄운다.
final roomInviteProvider = StreamProvider<RoomInvite>((ref) {
  return SocketService.instance.onRoomInvited;
});

/// 예기치 않은 소켓 연결 끊김(네트워크 문제 등) — 방 화면이 구독해 즉시 로비로 나가면서
/// 알림창을 띄우는 데 쓴다. 우리가 직접 재연결하려고 끊은 경우는 SocketService에서 걸러진다.
final socketDisconnectedProvider = StreamProvider<void>((ref) {
  return SocketService.instance.onDisconnected;
});

/// 앱 시작 시(새로고침 포함) 저장된 활성 방 코드가 있는지 확인 — AuthGate가 로비 대신
/// 방으로 바로 복귀를 시도할지 판단하는 데 쓴다.
final savedRoomCodeProvider = FutureProvider<String?>((ref) {
  return RoomSessionStore.instance.readRoomCode();
});
