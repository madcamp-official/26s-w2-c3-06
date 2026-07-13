import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/backend_api.dart';
import '../../models/chat_message.dart';
import '../../models/game_phase.dart';
import '../../models/game_result.dart';
import '../../models/player.dart';
import '../../models/round_result.dart';
import '../../widgets/hover_tap.dart';
import '../../services/auth_service.dart';
import '../../services/user_session.dart';
import '../../state/room_provider.dart';
import '../../widgets/pixel_dialog.dart';
import '../../theme/app_colors.dart';
import '../../theme/pixel_font.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/app_nav_rail.dart';
import '../../widgets/countdown_text.dart';
import '../../widgets/pixel_box.dart';
import '../../widgets/user_avatar.dart';
import '../../utils/breakpoints.dart';

/// 대기 → 설명 → 토론 → 투표 → 결과 → (역전승) → 종료(대기 복귀)를 하나의 화면으로 표현한다.
/// 모든 페이즈 전이·타이머·판정은 서버가 소유하고(PLAN "Socket.IO 이벤트 계약"), 이 화면은
/// roomProvider가 반영한 상태를 그리고 사용자 액션을 소켓으로 위임만 한다(로컬 시뮬레이션 없음).
class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key});

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

const _presetCategories = <String>['음식', '동물', '영화', '스포츠', '직업', '나라'];
const _minParticipants = 3;

class _RoomScreenState extends ConsumerState<RoomScreen> {
  final _chatController = TextEditingController();
  final _chatFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _customCategoryController = TextEditingController();

  // 방장 대기방 드래프트(로컬 입력 → game:draftConfig로 서버에 실시간 공유).
  int _botCount = 0;
  String? _selectedChip;
  bool _aiRandom = false;
  bool _leaving = false;
  int _lastChatLen = 0;
  bool _hostDraftSeeded = false;

  // AI 응답을 기다리는 동안(게임 시작·라이어 역전승 판정) 버튼이 눌렸고 처리 중임을
  // 명확히 보여주기 위한 로딩 플래그. 서버가 다음 페이즈로 넘기거나 room:error를
  // 보내면 리셋한다(phase/roomError 리스너 참고).
  bool _startingGame = false;
  bool _submittingGuess = false;

  // 제시어에 딸린 AI 설명은 받자마자 바로 노출하지 않고, "설명 보기"를 눌러야 펼쳐지게 한다.
  bool _showWordExplanation = false;

  // 투표 탭에 아무 시각적 피드백이 없어 "버튼이 안 눌린다"고 느껴지던 문제 — 내가 누른
  // 후보를 로컬에 기억해 선택 표시하고 재탭을 막는다(서버도 어차피 idempotent).
  String? _myVote;

  // 참가자 아바타(채팅·투표 후보 등)는 프리셋 이모지가 아니라 실제 프로필 사진을 보여준다.
  // uid별로 한 번만 조회해 캐싱하고, 봇(id가 bot-로 시작)은 DB에 없는 게 정상이라 건너뛴다.
  final Map<String, String?> _avatarUrlCache = {};
  final Set<String> _avatarUrlFetching = {};

  String? _avatarUrlFor(String uid) {
    if (_avatarUrlCache.containsKey(uid)) return _avatarUrlCache[uid];
    if (uid.startsWith('bot-') || _avatarUrlFetching.contains(uid)) return null;
    _avatarUrlFetching.add(uid);
    BackendApi.instance.getUserProfile(uid).then((profile) {
      if (!mounted) return;
      setState(() => _avatarUrlCache[uid] = profile.avatarUrl);
    }).catchError((_) {
      if (mounted) setState(() => _avatarUrlCache[uid] = null);
    });
    return null;
  }

  String? get _myUid => AuthService.instance.currentUser?.uid;

  @override
  void dispose() {
    _chatController.dispose();
    _chatFocusNode.dispose();
    _scrollController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _leave() async {
    if (_leaving) return;
    final isHost = ref.read(roomProvider).hostId == _myUid;
    final confirmed = await showPixelDialog<bool>(
      context: context,
      barrierDismissible: true,
      maxWidth: 320,
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🚪 방 나가기', style: PixelFont.title(fontSize: 13, color: AppColors.primary)),
            const SizedBox(height: 12),
            Text(
              isHost ? '방장이 나가면 방이 사라집니다. 정말 나가시겠어요?' : '정말 이 방에서 나가시겠어요?',
              style: PixelFont.body(fontSize: 12, color: AppColors.foreground),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: '취소',
                    variant: AppButtonVariant.outlined,
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton(label: '나가기', onPressed: () => Navigator.of(dialogContext).pop(true)),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true || _leaving) return;
    _leaving = true;
    ref.read(roomProvider.notifier).leaveRoom();
    _returnToLobby();
  }

  /// 로비(첫 라우트)까지 확실히 돌아간다 — 열려 있는 다이얼로그/바텀시트가 있어도
  /// 일반 pop() 한 번으로는 그 위젯만 닫힐 수 있어 popUntil로 처리한다.
  void _returnToLobby() {
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// 최종 결과(지목된 사람·라이어 여부·실제/라이어 제시어·역전승 여부)를 채팅 로그에
  /// 묻히지 않도록 큰 알림창으로 한 번에 보여준다.
  Future<void> _showResultDialog(GameResult r) async {
    final citizensWin = r.citizensWin;
    String accusedText;
    if (r.accusedNickname == null) {
      accusedText = '아무도 지목되지 않았어요';
    } else {
      accusedText = '${r.accusedNickname} (라이어 ${r.wasLiar ? '⭕ 맞음' : '❌ 아님'})';
    }
    String liarGuessText;
    if (r.liarGuessCorrect == null) {
      liarGuessText = '역전승 시도 없음';
    } else if (r.liarGuessCorrect == true) {
      liarGuessText = r.liarGuess == null ? '✅ 성공 — 라이어 역전승!' : '✅ 성공 — "${r.liarGuess}" 정답!';
    } else {
      liarGuessText = r.liarGuess == null ? '❌ 실패' : '❌ 실패 — "${r.liarGuess}"라고 썼어요';
    }

    await showPixelDialog<void>(
      context: context,
      maxWidth: 380,
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(citizensWin ? '🐾' : '🦊', style: const TextStyle(fontSize: 48)),
            ),
            const SizedBox(height: 4),
            Text(
              citizensWin ? '시민팀의 승리!' : '라이어팀의 승리!',
              textAlign: TextAlign.center,
              style: PixelFont.title(fontSize: 18, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            _ResultRow(label: '지목된 사람', value: accusedText),
            _ResultRow(label: '실제 제시어', value: r.realWord),
            _ResultRow(label: '라이어 제시어', value: r.liarWord),
            _ResultRow(label: '라이어 역전승', value: liarGuessText),
            const SizedBox(height: 22),
            AppButton(label: '확인', onPressed: () => Navigator.of(dialogContext).pop()),
          ],
        );
      },
    );
  }

  /// 방장 전용 "친구 초대" — 접속 중인 친구 목록을 보여주고, 탭하면 friend:invite를 보낸다.
  /// 상대가 온라인이면 room:invited를 받아 로비에서 알림+입장 버튼을 보게 된다.
  Future<void> _openInviteFriendsSheet() async {
    List<FriendSummary> friends;
    try {
      friends = await BackendApi.instance.getFriends();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('친구 목록을 불러오지 못했습니다.')));
      }
      return;
    }
    final online = friends.where((f) => f.isOnline).toList();
    if (!mounted) return;

    await showPixelDialog<void>(
      context: context,
      barrierDismissible: true,
      maxWidth: 340,
      builder: (dialogContext) {
        final invited = <String>{};
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('👥 친구 초대', style: PixelFont.title(fontSize: 13, color: AppColors.primary)),
                const SizedBox(height: 6),
                Text('접속 중인 친구만 초대할 수 있어요',
                    style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
                const SizedBox(height: 14),
                if (online.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text('지금 접속 중인 친구가 없어요',
                        style: PixelFont.body(fontSize: 12, color: AppColors.mutedForeground)),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      child: Column(
                        children: online.map((f) {
                          final done = invited.contains(f.uid);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                UserAvatar(avatarIndex: 0, radius: 16, imageUrl: f.avatarUrl),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(f.nickname,
                                      style: PixelFont.body(fontSize: 13, color: AppColors.foreground)),
                                ),
                                AppButton(
                                  label: done ? '초대됨' : '초대',
                                  dense: true,
                                  fullWidth: false,
                                  variant: done ? AppButtonVariant.outlined : AppButtonVariant.primary,
                                  onPressed: done
                                      ? null
                                      : () {
                                          ref.read(roomProvider.notifier).inviteFriend(f.uid);
                                          setDialogState(() => invited.add(f.uid));
                                        },
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                AppButton(
                  label: '닫기',
                  variant: AppButtonVariant.outlined,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _sendChatOrDescription(RoomViewState s) {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    final notifier = ref.read(roomProvider.notifier);
    if (s.phase == GamePhase.describing && s.isMyTurn(_myUid)) {
      notifier.submitDescription(text);
    } else {
      notifier.sendChat(text);
    }
    _chatController.clear();
    // 엔터로 전송한 뒤에도 계속 이어서 칠 수 있도록 입력창 포커스를 다시 잡아준다
    // (웹에서는 onSubmitted 처리 중 포커스가 풀리는 경우가 있어 명시적으로 복원).
    _chatFocusNode.requestFocus();
  }

  // ── 방장 드래프트 반영 ──
  void _pushDraft() {
    final custom = _customCategoryController.text.trim();
    final category = _aiRandom ? null : (custom.isNotEmpty ? custom : _selectedChip);
    ref.read(roomProvider.notifier).updateDraftConfig(category: category, aiBotCount: _botCount);
  }

  void _startGame() {
    final custom = _customCategoryController.text.trim();
    final category = _aiRandom ? null : (custom.isNotEmpty ? custom : _selectedChip);
    setState(() => _startingGame = true);
    ref.read(roomProvider.notifier).configureGame(category: category, aiBotCount: _botCount);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(roomProvider);
    final myUid = _myUid;

    // 방이 닫혔거나(방장 퇴장) 우리가 나간 경우 roomCode가 사라진다 → 로비로 복귀.
    // 다이얼로그 등이 떠 있어도 확실히 로비까지 돌아가도록 popUntil로 맨 처음 라우트까지 닫는다.
    ref.listen<String?>(roomProvider.select((v) => v.roomCode), (prev, next) {
      if (prev != null && next == null && !_leaving) {
        _returnToLobby();
      }
    });
    // 새 투표 페이즈가 시작될 때마다 이전 라운드의 선택 표시를 지운다.
    // 게임이 실제로 시작/종료되면 "게임 시작"/"제출" 버튼의 로딩 표시도 함께 내린다.
    ref.listen<GamePhase>(roomProvider.select((v) => v.phase), (prev, next) {
      if (next == GamePhase.voting && prev != GamePhase.voting) {
        setState(() => _myVote = null);
      }
      if (next == GamePhase.describing && _startingGame) {
        setState(() => _startingGame = false);
      }
      if (next == GamePhase.ended && _submittingGuess) {
        setState(() => _submittingGuess = false);
      }
    });
    // 새 게임(또는 새 제시어)을 받으면 지난 라운드에서 펼쳐뒀던 설명 표시를 접는다.
    ref.listen<String?>(roomProvider.select((v) => v.myWord), (prev, next) {
      if (next != prev && _showWordExplanation) {
        setState(() => _showWordExplanation = false);
      }
    });
    // 최종 결과(지목된 사람·라이어 여부·실제/라이어 제시어·역전승 여부)가 다 갖춰지면
    // 채팅으로 흘려보내지 않고 큰 알림창으로 한 번에 보여준다.
    ref.listen<RoundFinalResult?>(roomProvider.select((v) => v.finalResult), (prev, next) {
      if (prev == null && next != null) {
        final result = ref.read(roomProvider).gameResult;
        if (result != null) _showResultDialog(result);
      }
    });
    // 게임 시작·역전승 제출 실패(room:error) 시에도 로딩 표시를 내리고 이유를 보여준다.
    ref.listen<AsyncValue<String>>(roomErrorProvider, (prev, next) {
      next.whenData((message) {
        if (!mounted) return;
        setState(() {
          _startingGame = false;
          _submittingGuess = false;
        });
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      });
    });

    if (s.chatLog.length != _lastChatLen) {
      _lastChatLen = s.chatLog.length;
      _autoScroll();
    }

    final isHost = myUid != null && s.hostId == myUid;

    // 방장 대기방 컨트롤(봇 수·카테고리 칩)을 서버 draft 값으로 최초 1회 시드한다
    // (재입장/복귀 시 서버가 들고 있던 값을 로컬 입력에 반영). 자유 입력 카테고리는 칩 밖이라 텍스트 필드로.
    if (isHost && !_hostDraftSeeded && s.hostId != null) {
      _hostDraftSeeded = true;
      _botCount = s.draftAiBotCount;
      final cat = s.draftCategory;
      if (cat == null) {
        _aiRandom = false;
        _selectedChip = null;
      } else if (_presetCategories.contains(cat) || s.customCategories.contains(cat)) {
        _selectedChip = cat;
      } else {
        _customCategoryController.text = cat;
      }
    }

    final isDesktop = context.isDesktop;
    // 데스크탑에서는 나가기/초대 버튼이 헤더가 아니라 좌측 내비게이션 바로 이동한다
    // (frontend 브랜치의 데스크탑 레이아웃 참고, lobby_screen과 동일한 패턴).
    final body = Column(
      children: [
        _header(s, isHost, showActions: !isDesktop),
        Expanded(child: _chatFeed(s)),
        _contextPanel(s, isHost),
        _inputBar(s),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppNavRail(
                      items: [
                        if (isHost && _canInviteFriends)
                          AppNavRailItem(
                            icon: Icons.person_add_alt_1,
                            label: '초대',
                            onTap: _openInviteFriendsSheet,
                          ),
                        AppNavRailItem(icon: Icons.exit_to_app, label: '나가기', onTap: _leave),
                      ],
                    ),
                    Expanded(child: body),
                  ],
                )
              : body,
        ),
      ),
    );
  }

  // 친구 초대는 방장이면서 회원(게스트가 아님)일 때만 가능하다 — 게스트는 친구 목록이
  // 아이디 기반이라 애초에 친구 기능 자체를 쓸 수 없다(로비의 게스트 친구 제한과 동일 규칙).
  bool get _canInviteFriends => !UserSession.isGuest;

  Widget _header(RoomViewState s, bool isHost, {required bool showActions}) {
    final emoji = (s.emoji?.isNotEmpty ?? false) ? s.emoji! : '🎮';
    final title = (s.title?.isNotEmpty ?? false) ? s.title! : '방 ${s.roomCode ?? ''}';
    return PixelBox(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: PixelFont.title(fontSize: 11, color: AppColors.foreground)),
                Text(
                  '코드 ${s.roomCode ?? '----'} · ${s.players.length}명',
                  style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground),
                ),
              ],
            ),
          ),
          if (showActions) ...[
            if (isHost && _canInviteFriends) ...[
              HoverTap(
                onTap: _openInviteFriendsSheet,
                child: const Icon(Icons.person_add_alt_1, color: AppColors.mutedForeground),
              ),
              const SizedBox(width: 14),
            ],
            HoverTap(
              onTap: _leave,
              child: const Icon(Icons.exit_to_app, color: AppColors.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chatFeed(RoomViewState s) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      itemCount: s.chatLog.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ChatBubble(
          message: _displayMessage(s.chatLog[i], s),
          myUid: _myUid,
          senderAvatarUrl: () {
            final m = s.chatLog[i];
            if (m.isAi || m.isSystem) return null;
            return _avatarUrlFor(m.senderId);
          }(),
        ),
      ),
    );
  }

  /// 서버 메시지는 senderNickname/avatarIndex가 비어 있으므로 참가자 목록으로 해석해 채워 준다.
  ChatMessage _displayMessage(ChatMessage m, RoomViewState s) {
    final nickname = m.isAi ? 'AI' : (m.isSystem ? '시스템' : s.nicknameOf(m.senderId));
    return ChatMessage(
      id: m.id,
      senderId: m.senderId,
      senderNickname: nickname,
      avatarIndex: _avatarIndexFor(m.senderId, s),
      text: m.text,
      type: m.type,
      highlight: m.highlight,
      timestamp: m.timestamp,
    );
  }

  int _avatarIndexFor(String id, RoomViewState s) {
    final pool = s.participants.isNotEmpty ? s.participants : s.players;
    final idx = pool.indexWhere((p) => p.id == id);
    return idx == -1 ? 0 : idx;
  }

  // ── 페이즈별 하단 컨텍스트 패널 ──
  Widget _contextPanel(RoomViewState s, bool isHost) {
    switch (s.phase) {
      case GamePhase.waiting:
      case GamePhase.ended:
        return _waitingPanel(s, isHost);
      case GamePhase.describing:
        return _describingPanel(s, isHost);
      case GamePhase.discussion:
        return _discussionPanel(s, isHost);
      case GamePhase.voting:
        return _votingPanel(s);
      case GamePhase.resolution:
        return _resolutionPanel(s);
      case GamePhase.liarGuess:
        return _liarGuessPanel(s);
    }
  }

  Widget _panelBox({required Widget child}) => PixelBox(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        padding: const EdgeInsets.all(12),
        child: child,
      );

  Widget _waitingPanel(RoomViewState s, bool isHost) {
    final myUid = _myUid;
    final me = s.players.where((p) => p.id == myUid).cast<Player?>().firstWhere((_) => true, orElse: () => null);
    final allReady = s.players.isNotEmpty && s.players.every((p) => p.isReady);
    final botCount = isHost ? _botCount : s.draftAiBotCount;
    final enough = s.players.length + botCount >= _minParticipants;
    final canStart = isHost && allReady && enough;

    final chipCategories = <String>[
      ..._presetCategories,
      ...s.customCategories.where((c) => !_presetCategories.contains(c)),
    ];
    final selectedChip = isHost ? _selectedChip : s.draftCategory;
    final aiRandom = isHost ? _aiRandom : s.draftCategory == null;

    return _panelBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.phase == GamePhase.ended)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('게임 종료 — 새 게임을 시작할 수 있어요',
                  style: PixelFont.body(fontSize: 12, color: AppColors.primary)),
            ),
          // 참가자 준비 상태 — 아바타 + 닉네임 + 준비/대기 뱃지의 작은 세로형 카드(frontend 브랜치 스타일).
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: s.players.map((p) {
              final isHostPlayer = p.id == s.hostId;
              return SizedBox(
                width: 48,
                child: Column(
                  children: [
                    UserAvatar(avatarIndex: _avatarIndexFor(p.id, s), radius: 16, imageUrl: _avatarUrlFor(p.id)),
                    const SizedBox(height: 2),
                    Text(
                      p.nickname,
                      style: PixelFont.body(fontSize: 10, color: AppColors.foreground, height: 1.0),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (isHostPlayer)
                      Text('👑 방장', style: PixelFont.body(fontSize: 9, height: 1.0, color: AppColors.primary))
                    else
                      Text(
                        p.isReady ? '✓준비' : '대기',
                        style: PixelFont.body(
                          fontSize: 9,
                          height: 1.0,
                          color: p.isReady ? AppColors.readyBadgeText : AppColors.waitingBadgeText,
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // 방장은 서버가 참여 즉시 준비 완료로 고정해두므로(봇과 동일 규칙) 준비 토글을
          // 보여주지 않는다. 방장이 아닌 참가자만 직접 준비 상태를 토글한다.
          if (me != null && !isHost)
            AppButton(
              label: me.isReady ? '준비 완료 ✓' : '준비하기',
              variant: me.isReady ? AppButtonVariant.outlined : AppButtonVariant.primary,
              dense: true,
              onPressed: () => ref.read(roomProvider.notifier).setReady(!me.isReady),
            ),
          if (isHost) ...[
            const SizedBox(height: 10),
            Text('AI 봇 수: $botCount', style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () {
                    setState(() => _botCount = (_botCount - 1).clamp(0, 8));
                    _pushDraft();
                  },
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_botCount', style: PixelFont.title(fontSize: 13, color: AppColors.foreground)),
                IconButton(
                  onPressed: () {
                    setState(() => _botCount = (_botCount + 1).clamp(0, 8));
                    _pushDraft();
                  },
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            Text('카테고리', style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: chipCategories.map((c) {
                return ChoiceChip(
                  label: Text(c, style: PixelFont.body(fontSize: 11, color: AppColors.foreground)),
                  selected: !aiRandom && c == selectedChip,
                  onSelected: (_) {
                    setState(() {
                      _aiRandom = false;
                      _selectedChip = c;
                      _customCategoryController.clear();
                    });
                    _pushDraft();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            AppTextField(
              controller: _customCategoryController,
              hintText: '직접 입력',
              onChanged: (v) {
                setState(() {
                  if (v.trim().isNotEmpty) {
                    _selectedChip = null;
                    _aiRandom = false;
                  }
                });
                _pushDraft();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('AI 랜덤 생성', style: PixelFont.body(fontSize: 12, color: AppColors.foreground)),
              value: aiRandom,
              onChanged: (v) {
                setState(() => _aiRandom = v);
                _pushDraft();
              },
            ),
            const SizedBox(height: 6),
            if (!allReady)
              Text('모든 참가자가 준비 완료해야 시작할 수 있어요.',
                  style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground))
            else if (!enough)
              Text('참가자(사람+봇)가 최소 $_minParticipants명 이상이어야 해요.',
                  style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
            const SizedBox(height: 6),
            AppButton(
              label: '게임 시작 ▶',
              loading: _startingGame,
              onPressed: canStart && !_startingGame ? _startGame : null,
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text('방장이 게임을 시작하길 기다리는 중...',
                style: PixelFont.body(fontSize: 12, color: AppColors.mutedForeground)),
          ],
        ],
      ),
    );
  }

  Widget _myWordCard(RoomViewState s) {
    if (s.myWord == null) return const SizedBox.shrink();
    final hasExplanation = s.myWordExplanation != null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('내 제시어', style: PixelFont.body(fontSize: 10, color: AppColors.mutedForeground)),
          Text(s.myWord!, style: PixelFont.title(fontSize: 14, color: AppColors.primary)),
          if (hasExplanation) ...[
            const SizedBox(height: 4),
            HoverTap(
              onTap: () => setState(() => _showWordExplanation = !_showWordExplanation),
              child: Text(
                _showWordExplanation ? '설명 숨기기 ▲' : 'AI 설명 보기 ▼',
                style: PixelFont.body(fontSize: 10, color: AppColors.primary),
              ),
            ),
            if (_showWordExplanation) ...[
              const SizedBox(height: 4),
              Text(s.myWordExplanation!, style: PixelFont.body(fontSize: 11, color: AppColors.foreground)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _describingPanel(RoomViewState s, bool isHost) {
    final myTurn = s.isMyTurn(_myUid);
    final turnNick = s.currentTurnPlayerId == null ? '' : s.nicknameOf(s.currentTurnPlayerId!);
    return _panelBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _myWordCard(s),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(myTurn ? '내 차례! 제시어를 설명하세요' : '$turnNick님이 설명 중...',
                    style: PixelFont.body(fontSize: 12, color: myTurn ? AppColors.primary : AppColors.foreground)),
              ),
              if (s.phaseDeadline != null)
                CountdownText(
                  deadline: s.phaseDeadline!,
                  style: PixelFont.title(fontSize: 12, color: AppColors.foreground),
                ),
              // 방장이 진행이 느릴 때 현재 턴(사람/봇 무관)을 강제로 넘길 수 있다.
              if (isHost) ...[
                const SizedBox(width: 8),
                AppButton(
                  label: '다음 차례 ▶',
                  fullWidth: false,
                  dense: true,
                  variant: AppButtonVariant.outlined,
                  onPressed: () => ref.read(roomProvider.notifier).skipTurn(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _discussionPanel(RoomViewState s, bool isHost) {
    return _panelBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _myWordCard(s),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('자유 토론 중',
                  style: PixelFont.body(fontSize: 12, color: AppColors.foreground)),
              if (s.phaseDeadline != null)
                CountdownText(
                  deadline: s.phaseDeadline!,
                  style: PixelFont.title(fontSize: 12, color: AppColors.foreground),
                ),
            ],
          ),
          if (isHost) ...[
            const SizedBox(height: 8),
            AppButton(
              label: '투표로 넘어가기',
              variant: AppButtonVariant.outlined,
              dense: true,
              onPressed: () => ref.read(roomProvider.notifier).skipDiscussion(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _votingPanel(RoomViewState s) {
    final myUid = _myUid;
    final candidates = s.participants.where((p) => p.id != myUid).toList();
    return _panelBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('라이어를 투표하세요',
                  style: PixelFont.body(fontSize: 12, color: AppColors.primary)),
              if (s.phaseDeadline != null)
                CountdownText(
                  deadline: s.phaseDeadline!,
                  style: PixelFont.title(fontSize: 12, color: AppColors.foreground),
                ),
            ],
          ),
          if (s.votesInCount != null && s.totalVoteCount != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('투표 ${s.votesInCount}/${s.totalVoteCount}',
                  style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
            ),
          if (_myVote != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('투표 완료! 다른 사람들을 기다리는 중...',
                  style: PixelFont.body(fontSize: 11, color: AppColors.primary)),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: candidates.map((p) {
              final selected = _myVote == p.id;
              final voted = _myVote != null;
              return Opacity(
                opacity: voted && !selected ? 0.5 : 1,
                child: HoverTap(
                  onTap: voted
                      ? null
                      : () {
                          setState(() => _myVote = p.id);
                          ref.read(roomProvider.notifier).castVote(p.id);
                        },
                  child: PixelBox(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    color: selected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.card,
                    border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        UserAvatar(
                          avatarIndex: _avatarIndexFor(p.id, s),
                          radius: 10,
                          imageUrl: p.isBot ? null : _avatarUrlFor(p.id),
                        ),
                        const SizedBox(width: 6),
                        Text(p.nickname, style: PixelFont.body(fontSize: 11, color: AppColors.foreground)),
                        if (selected) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.check_circle, size: 14, color: AppColors.primary),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _resolutionPanel(RoomViewState s) {
    final r = s.roundResolved;
    final result = s.finalResult;
    return _panelBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('투표 결과', style: PixelFont.title(fontSize: 12, color: AppColors.primary)),
          const SizedBox(height: 6),
          if (r != null) ...[
            Text(
              r.votedOutId == null
                  ? '지목된 사람이 없습니다.'
                  : '${s.nicknameOf(r.votedOutId!)}님이 지목됨 — ${r.wasLiar ? '라이어였습니다!' : '라이어가 아니었습니다.'}',
              style: PixelFont.body(fontSize: 12, color: AppColors.foreground),
            ),
            const SizedBox(height: 4),
            Text('진짜: ${r.realWord} / 라이어: ${r.liarWord}',
                style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
          ],
          if (result != null) ...[
            const SizedBox(height: 6),
            Text(
              result.winner == 'citizens' ? '🐾 시민팀의 승리!' : '🦊 라이어의 승리!',
              style: PixelFont.title(fontSize: 13, color: AppColors.primary),
            ),
          ],
          const SizedBox(height: 6),
          Text('결과를 확인하는 중... 잠시 후 대기방으로 돌아갑니다.',
              style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
        ],
      ),
    );
  }

  Widget _liarGuessPanel(RoomViewState s) {
    final isMe = s.liarGuessTimeLimitSec != null;
    if (!isMe) {
      return _panelBox(
        child: Text('라이어가 진짜 제시어를 맞히는 중...',
            style: PixelFont.body(fontSize: 12, color: AppColors.foreground)),
      );
    }
    final guessController = TextEditingController();
    return _panelBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('역전 기회! 진짜 제시어를 맞히세요',
                  style: PixelFont.body(fontSize: 12, color: AppColors.primary)),
              if (s.phaseDeadline != null)
                CountdownText(
                  deadline: s.phaseDeadline!,
                  style: PixelFont.title(fontSize: 12, color: AppColors.foreground),
                ),
            ],
          ),
          const SizedBox(height: 6),
          AppTextField(controller: guessController, hintText: '진짜 제시어'),
          const SizedBox(height: 6),
          AppButton(
            label: '제출',
            dense: true,
            loading: _submittingGuess,
            onPressed: _submittingGuess
                ? null
                : () {
                    final g = guessController.text.trim();
                    if (g.isEmpty) return;
                    setState(() => _submittingGuess = true);
                    ref.read(roomProvider.notifier).guessWord(g);
                  },
          ),
        ],
      ),
    );
  }

  Widget _inputBar(RoomViewState s) {
    // 대기/종료 페이즈엔 하단 컨텍스트 패널에 컨트롤이 있으니 자유 채팅만 노출.
    final describingMyTurn = s.phase == GamePhase.describing && s.isMyTurn(_myUid);
    final hint = describingMyTurn ? '제시어 설명 입력...' : '메시지 입력...';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: AppTextField(
              controller: _chatController,
              focusNode: _chatFocusNode,
              hintText: hint,
              onSubmitted: (_) => _sendChatOrDescription(s),
            ),
          ),
          const SizedBox(width: 8),
          HoverTap(
            onTap: () => _sendChatOrDescription(s),
            child: PixelBox(
              padding: const EdgeInsets.all(10),
              color: AppColors.primary,
              child: const Icon(Icons.send, size: 18, color: AppColors.primaryForeground),
            ),
          ),
        ],
      ),
    );
  }
}

/// 최종 결과 알림창의 "라벨: 값" 한 줄.
class _ResultRow extends StatelessWidget {
  final String label;
  final String value;

  const _ResultRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: PixelFont.body(fontSize: 12, color: AppColors.mutedForeground)),
          ),
          Expanded(
            child: Text(
              value,
              style: PixelFont.body(fontSize: 13, color: AppColors.foreground, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
