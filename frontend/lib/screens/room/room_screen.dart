import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../mock/mock_data.dart';
import '../../models/chat_message.dart';
import '../../models/player.dart';
import '../../theme/app_colors.dart';
import '../../theme/pixel_font.dart';
import '../../utils/breakpoints.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_nav_rail.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/pixel_dialog.dart';
import '../../widgets/responsive_center.dart';
import '../../widgets/user_avatar.dart';

/// 대기 → 설명 → (전원 설명 완료) → 투표 → 결과 → (역전승 시도) → 종료(대기로 복귀)까지
/// 하나의 화면(단일 채팅 피드 + 하단 컨텍스트 패널)으로 표현한다.
enum _Phase { waiting, describing, allDone, voting, liarGuessWait }

const _turnSeconds = 30;

class RoomScreen extends StatefulWidget {
  final String roomCode;
  final bool isHost;

  const RoomScreen({super.key, required this.roomCode, this.isHost = false});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  final _random = Random();
  final _scrollController = ScrollController();

  late List<Player> _humanPlayers;
  final List<ChatMessage> _messages = [];
  final _chatController = TextEditingController();
  final _customCategoryController = TextEditingController();

  int _botCount = 0;
  String? _selectedCategory;
  final List<String> _customCategories = [];
  final Set<String> _usedWordPairs = {};

  _Phase _phase = _Phase.waiting;

  List<Player> _participants = [];
  List<String> _turnOrder = [];
  int _currentTurnIndex = 0;
  String? _realWord;
  String? _liarWord;
  String? _liarId;
  final Map<String, String> _votes = {};
  String? _votedOutId;

  Timer? _tickTimer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _humanPlayers = List.of(buildMockPlayers(selfIsHost: widget.isHost));
    _selectedCategory = mockCategories.first;
    final other = _humanPlayers.firstWhere((p) => p.id != 'me');
    _addSystemMessage('🎉 방에 입장했습니다!');
    _addChatMessage(other.id, '다들 준비됐어요? 😄');
    _addAiFlavorMessage('오늘 라이어가 누구일지 저만 알고 있답니다 👀');
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _scrollController.dispose();
    _chatController.dispose();
    _customCategoryController.dispose();
    super.dispose();
  }

  // ─── 참가자 ───────────────────────────────────────────────

  List<Player> get _bots => List.generate(
        _botCount,
        (index) => Player(id: 'bot${index + 1}', nickname: 'AI 봇 ${index + 1}', isBot: true, isReady: true),
      );

  List<Player> get _allPlayers => [..._humanPlayers, ..._bots];

  int _avatarIndexFor(String id) {
    final pool = _participants.isNotEmpty ? _participants : _allPlayers;
    final index = pool.indexWhere((p) => p.id == id);
    return index == -1 ? 0 : index;
  }

  String _nicknameFor(String id) {
    if (id == 'ai') return 'AI';
    if (id == 'system') return '시스템';
    final pool = _participants.isNotEmpty ? _participants : _allPlayers;
    return pool.firstWhere((p) => p.id == id, orElse: () => Player(id: id, nickname: id)).nickname;
  }

  void _toggleReady(String playerId) {
    if (_phase != _Phase.waiting) return;
    final index = _humanPlayers.indexWhere((p) => p.id == playerId);
    if (index == -1) return;
    setState(() {
      _humanPlayers[index] = _humanPlayers[index].copyWith(isReady: !_humanPlayers[index].isReady);
    });
  }

  void _changeBotCount(int delta) {
    if (_phase != _Phase.waiting) return;
    setState(() => _botCount = (_botCount + delta).clamp(0, 4));
  }

  // ─── 카테고리 설정 ─────────────────────────────────────────

  List<String> get _availableCategories => [...mockCategories, ..._customCategories];

  void _selectCategory(String category) {
    if (!widget.isHost || _phase != _Phase.waiting) return;
    setState(() => _selectedCategory = category);
  }

  void _addCustomCategory() {
    final name = _customCategoryController.text.trim();
    if (name.isEmpty || _availableCategories.contains(name)) return;
    setState(() {
      _customCategories.add(name);
      _selectedCategory = name;
      _customCategoryController.clear();
    });
  }

  // ─── 시작 조건 ────────────────────────────────────────────

  bool get _canStartGame =>
      widget.isHost &&
      _allPlayers.length >= 3 &&
      _allPlayers.every((p) => p.isReady) &&
      _selectedCategory != null;

  // ─── 채팅 ────────────────────────────────────────────────

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _addSystemMessage(String text) {
    _messages.add(ChatMessage(
      id: 'sys-${_messages.length}-${DateTime.now().microsecondsSinceEpoch}',
      senderId: 'system',
      senderNickname: '시스템',
      text: text,
      type: ChatMessageType.system,
    ));
    _scrollToBottom();
  }

  void _addAiFlavorMessage(String text) {
    _messages.add(ChatMessage(
      id: 'ai-${_messages.length}-${DateTime.now().microsecondsSinceEpoch}',
      senderId: 'ai',
      senderNickname: 'AI',
      text: text,
      type: ChatMessageType.aiComment,
    ));
    _scrollToBottom();
  }

  void _addChatMessage(String senderId, String text, {ChatMessageType type = ChatMessageType.chat}) {
    _messages.add(ChatMessage(
      id: 'msg-${_messages.length}-${DateTime.now().microsecondsSinceEpoch}',
      senderId: senderId,
      senderNickname: _nicknameFor(senderId),
      avatarIndex: _avatarIndexFor(senderId),
      text: text,
      type: type,
    ));
    _scrollToBottom();
  }

  bool get _isMyTurn =>
      _currentTurnIndex < _turnOrder.length && _turnOrder[_currentTurnIndex] == 'me';

  /// 설명 페이즈 중에는 현재 차례인 플레이어만 채팅(=설명)을 보낼 수 있다.
  /// 그 외 페이즈(대기/전원설명완료)에서는 자유 채팅이 가능하다.
  bool get _canChat {
    switch (_phase) {
      case _Phase.waiting:
      case _Phase.allDone:
        return true;
      case _Phase.describing:
        return _isMyTurn;
      case _Phase.voting:
      case _Phase.liarGuessWait:
        return false;
    }
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty || !_canChat) return;
    _chatController.clear();
    if (_phase == _Phase.describing) {
      _submitTurnDescription('me', text);
    } else {
      setState(() => _addChatMessage('me', text));
    }
  }

  // ─── 게임 시작 ────────────────────────────────────────────

  void _startGame() {
    if (!_canStartGame) return;
    final category = _selectedCategory!;
    final pairPool = mockWordPairsByCategory[category] ?? mockFallbackWordPairs;
    final unused = pairPool.where((p) => !_usedWordPairs.contains('$category:${p.$1}')).toList();
    final options = unused.isNotEmpty ? unused : pairPool;
    final pair = options[_random.nextInt(options.length)];
    _usedWordPairs.add('$category:${pair.$1}');

    final participants = List.of(_allPlayers);
    final liar = participants[_random.nextInt(participants.length)];
    final order = participants.map((p) => p.id).toList()..shuffle(_random);

    setState(() {
      _messages.clear();
      _participants = participants;
      _realWord = pair.$1;
      _liarWord = pair.$2;
      _liarId = liar.id;
      _turnOrder = order;
      _currentTurnIndex = 0;
      _votes.clear();
      _votedOutId = null;
      _phase = _Phase.describing;
    });
    _addSystemMessage('🎮 게임이 시작되었습니다!');
    final myWord = 'me' == liar.id ? pair.$2 : pair.$1;
    setState(() {
      _messages.add(ChatMessage(
        id: 'myword',
        senderId: 'system',
        senderNickname: '시스템',
        text: '🔑 당신의 제시어: $myWord',
        type: ChatMessageType.system,
      ));
    });
    _beginTurn();
  }

  // ─── 설명 페이즈 ──────────────────────────────────────────

  void _beginTurn() {
    if (_currentTurnIndex >= _turnOrder.length) {
      _tickTimer?.cancel();
      setState(() => _phase = _Phase.allDone);
      _addSystemMessage('모든 플레이어가 설명했습니다.');
      // 전원 설명이 끝나면 잠시 후 투표창이 자동으로 열린다.
      Timer(const Duration(milliseconds: 1200), () {
        if (!mounted || _phase != _Phase.allDone) return;
        _openVoteDialog();
      });
      return;
    }
    final playerId = _turnOrder[_currentTurnIndex];
    setState(() => _secondsLeft = _turnSeconds);
    _addSystemMessage('💬 ${_nicknameFor(playerId)}의 차례입니다.');
    _startTick(onExpire: () => _submitTurnDescription(playerId, ''));

    if (playerId != 'me') {
      final delay = Duration(seconds: 1 + _random.nextInt(_turnSeconds - 2));
      Timer(delay, () {
        if (!mounted || _phase != _Phase.describing) return;
        if (_currentTurnIndex >= _turnOrder.length || _turnOrder[_currentTurnIndex] != playerId) return;
        _submitTurnDescription(playerId, _mockDescriptionFor(playerId));
      });
    }
  }

  String _mockDescriptionFor(String playerId) {
    final word = playerId == _liarId ? _liarWord! : _realWord!;
    return '이건 $word(이)랑 관련 있는 거예요.';
  }

  void _skipTurn() {
    if (_currentTurnIndex >= _turnOrder.length) return;
    _submitTurnDescription(_turnOrder[_currentTurnIndex], '');
  }

  void _submitTurnDescription(String playerId, String text) {
    if (_phase != _Phase.describing) return;
    if (_currentTurnIndex >= _turnOrder.length || _turnOrder[_currentTurnIndex] != playerId) return;
    _tickTimer?.cancel();

    final described = text.isNotEmpty;
    setState(() {
      if (described) {
        _addChatMessage(playerId, text, type: ChatMessageType.turnDescription);
      } else {
        _addSystemMessage('${_nicknameFor(playerId)}님이 시간 안에 설명하지 못했습니다.');
      }
    });

    // AI 분탕 코멘트는 실제로 채팅(설명)을 친 경우에만 붙는다. 시간 초과로 건너뛴 턴에는 달지 않는다.
    if (described) {
      Timer(const Duration(milliseconds: 800), () {
        if (!mounted || _phase != _Phase.describing) return;
        setState(() {
          final template = mockAiCommentTemplates[_random.nextInt(mockAiCommentTemplates.length)];
          _addAiFlavorMessage(template.replaceAll('{nickname}', _nicknameFor(playerId)));
        });
        Timer(const Duration(milliseconds: 500), () {
          if (!mounted || _phase != _Phase.describing) return;
          setState(() => _currentTurnIndex++);
          _beginTurn();
        });
      });
    } else {
      Timer(const Duration(milliseconds: 400), () {
        if (!mounted || _phase != _Phase.describing) return;
        setState(() => _currentTurnIndex++);
        _beginTurn();
      });
    }
  }

  // ─── 투표 페이즈 ──────────────────────────────────────────

  Future<void> _openVoteDialog() async {
    setState(() {
      _phase = _Phase.voting;
      _votes.clear();
    });
    for (final p in _participants.where((p) => p.id != 'me')) {
      final delay = Duration(seconds: 1 + _random.nextInt(4));
      Timer(delay, () {
        if (!mounted || _phase != _Phase.voting || _votes.containsKey(p.id)) return;
        final candidates = _participants.where((c) => c.id != p.id).toList();
        _votes[p.id] = candidates[_random.nextInt(candidates.length)].id;
      });
    }

    final candidates = _participants.where((p) => p.id != 'me').toList();
    String? selected;

    await showPixelDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('💧 VOTE', style: PixelFont.title(fontSize: 16)),
                const SizedBox(height: 12),
                const Text('라이어를 지목하세요. 한 명만 선택할 수 있습니다.'),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: candidates.map((p) {
                    final isSelected = selected == p.id;
                    return GestureDetector(
                      onTap: () => setDialogState(() => selected = p.id),
                      child: Container(
                        width: 84,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : AppColors.secondary,
                          border: Border.all(color: isSelected ? AppColors.primaryBorder : AppColors.border, width: 2),
                        ),
                        child: Column(
                          children: [
                            UserAvatar(avatarIndex: _avatarIndexFor(p.id), radius: 20),
                            const SizedBox(height: 6),
                            Text(
                              p.nickname,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : AppColors.foreground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: '취소',
                        variant: AppButtonVariant.outlined,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: '투표 확정',
                        onPressed: selected == null
                            ? null
                            : () {
                                _votes['me'] = selected!;
                                Navigator.of(dialogContext).pop();
                              },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (!_votes.containsKey('me')) {
      setState(() => _phase = _Phase.allDone);
      return;
    }
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _resolveVote();
  }

  void _resolveVote() {
    final tally = <String, int>{};
    for (final votedId in _votes.values) {
      tally[votedId] = (tally[votedId] ?? 0) + 1;
    }
    String? votedOutId;
    if (tally.isNotEmpty) {
      final maxCount = tally.values.reduce(max);
      final topChoices = tally.entries.where((e) => e.value == maxCount).map((e) => e.key).toList();
      votedOutId = topChoices[_random.nextInt(topChoices.length)];
    }
    final wasLiar = votedOutId != null && votedOutId == _liarId;
    setState(() => _votedOutId = votedOutId);

    showPixelDialog(
      context: context,
      builder: (dialogContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('👉', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 12),
            Text(
              votedOutId == null ? '아무도 지목되지 않았습니다' : '${_nicknameFor(votedOutId)}님이\n지목되었습니다!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: wasLiar ? AppColors.destructive.withValues(alpha: 0.12) : AppColors.success.withValues(alpha: 0.12),
                border: Border.all(color: wasLiar ? AppColors.destructive : AppColors.success),
              ),
              child: Column(
                children: [
                  Text(
                    wasLiar ? '🎭 라이어 지목 성공!' : '🛡️ 라이어가 살아남았습니다',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    wasLiar
                        ? '${_nicknameFor(votedOutId!)}는 라이어입니다. 제시어를 맞추면 라이어의 역전승! 틀리면 시민팀의 승리입니다.'
                        : '${votedOutId != null ? _nicknameFor(votedOutId) : '지목된 사람'}는 라이어가 아니었습니다. 라이어의 승리로 게임이 종료됩니다.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (wasLiar && votedOutId == 'me')
              _LiarGuessForm(
                onSubmit: (guess) {
                  Navigator.of(dialogContext).pop();
                  _submitLiarGuess(guess);
                },
              )
            else
              AppButton(
                label: '결과 확인 ➡',
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  if (wasLiar) {
                    setState(() => _phase = _Phase.liarGuessWait);
                    if (votedOutId != 'me') {
                      Timer(Duration(seconds: 2 + _random.nextInt(3)), () {
                        if (!mounted) return;
                        final guess = _random.nextBool() ? _realWord! : '오답';
                        _submitLiarGuess(guess);
                      });
                    }
                  } else {
                    _finishGame(winner: 'liar', liarGuess: null, liarGuessCorrect: null);
                  }
                },
              ),
          ],
        );
      },
    );
  }

  // ─── 역전승 ──────────────────────────────────────────────

  bool _isCorrectGuess(String guess) {
    String normalize(String s) => s.trim().toLowerCase().replaceAll(' ', '');
    final g = normalize(guess);
    final real = normalize(_realWord!);
    return g.isNotEmpty && (g == real || g.contains(real) || real.contains(g));
  }

  void _submitLiarGuess(String guess) {
    final correct = _isCorrectGuess(guess);
    _finishGame(winner: correct ? 'liar' : 'citizens', liarGuess: guess, liarGuessCorrect: correct);
  }

  // ─── 게임 종료 (결과 모달) ──────────────────────────────────

  void _finishGame({required String winner, required String? liarGuess, required bool? liarGuessCorrect}) {
    final citizensWin = winner == 'citizens';
    final scores = <String, int>{
      for (final p in _participants) p.id: (p.id == _liarId) == !citizensWin ? 100 : -50,
    };
    var countdown = citizensWin ? 3 : 2;

    showPixelDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Timer(const Duration(seconds: 1), () {
              if (countdown <= 1) {
                if (Navigator.of(dialogContext, rootNavigator: false).canPop()) {
                  Navigator.of(dialogContext).pop();
                }
                return;
              }
              setDialogState(() => countdown--);
            });

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(citizensWin ? '🎉' : '😈', style: const TextStyle(fontSize: 48)),
                  const SizedBox(height: 8),
                  Text(
                    citizensWin ? 'CITIZENS WIN!' : 'LIAR WINS!',
                    style: PixelFont.title(fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    citizensWin ? '🐾 시민팀의 승리!' : '🦊 라이어의 승리!',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _WordCard(label: '시민 제시어', word: _realWord!, color: AppColors.success),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _WordCard(label: '라이어 제시어', word: _liarWord!, color: AppColors.destructive),
                      ),
                    ],
                  ),
                  if (liarGuess != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.accent, border: Border.all(color: AppColors.border)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('라이어의 역전승 시도', style: TextStyle(fontSize: 11, color: AppColors.mutedForeground)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text('"$liarGuess"', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: liarGuessCorrect! ? AppColors.success : AppColors.destructive,
                                ),
                                child: Text(
                                  liarGuessCorrect ? '정답' : '오답',
                                  style: const TextStyle(color: Colors.white, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text('라이어: ${_nicknameFor(_liarId!)} 🦊', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _participants.map((p) {
                      final delta = scores[p.id]!;
                      final positive = delta > 0;
                      return Container(
                        width: 84,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: positive ? AppColors.success.withValues(alpha: 0.15) : AppColors.destructive.withValues(alpha: 0.15),
                          border: Border.all(color: positive ? AppColors.success : AppColors.destructive),
                        ),
                        child: Column(
                          children: [
                            UserAvatar(avatarIndex: _avatarIndexFor(p.id), radius: 16),
                            const SizedBox(height: 4),
                            Text(p.nickname, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                            Text(
                              positive ? '+$delta' : '$delta',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: positive ? AppColors.success : AppColors.destructive,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text('$countdown초 후 대기방으로 자동 이동합니다', style: TextStyle(fontSize: 12, color: AppColors.mutedForeground)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: '🔄 대기방으로',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: '로비 나가기',
                          variant: AppButtonVariant.outlined,
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      if (!mounted) return;
      _returnToWaiting();
    });
  }

  void _returnToWaiting() {
    setState(() {
      _addSystemMessage('게임이 종료되었습니다.');
      _phase = _Phase.waiting;
      for (var i = 0; i < _humanPlayers.length; i++) {
        _humanPlayers[i] = _humanPlayers[i].copyWith(isReady: false);
      }
    });
  }

  // ─── 타이머 ──────────────────────────────────────────────

  void _startTick({required VoidCallback onExpire}) {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
        onExpire();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  // ─── 방 나가기 (대기 상태에서만 유효) ──────────────────────

  Future<void> _handleLeaveRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('방 나가기'),
          content: const Text('정말 이 방에서 나가시겠어요?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('나가기')),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ─── UI ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isWaiting = _phase == _Phase.waiting;
    final isDesktop = context.isDesktop;
    return Scaffold(
      appBar: AppBar(
        title: Text(isWaiting ? '🎮 레이니의 방' : '🎮 GAME'),
        actions: [
          // 데스크탑에서는 나가기 버튼이 좌측 내비게이션 바로 이동한다.
          if (isWaiting && !isDesktop)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: AppButton(label: '방 나가기', fullWidth: false, variant: AppButtonVariant.outlined, onPressed: _handleLeaveRoom),
            )
          else if (_phase == _Phase.describing)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$_secondsLeft', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary)),
                  SizedBox(
                    width: 100,
                    child: LinearProgressIndicator(
                      value: _secondsLeft / _turnSeconds,
                      backgroundColor: AppColors.secondary,
                      color: AppColors.primary,
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isDesktop)
              AppNavRail(
                items: [
                  if (isWaiting) AppNavRailItem(icon: Icons.logout, label: '나가기', onTap: _handleLeaveRoom),
                ],
              ),
            Expanded(
              child: ResponsiveCenter(
                maxWidth: 1000,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: isDesktop ? 200 : 160, child: _buildPlayerSidebar(context)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildMainArea(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerSidebar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PLAYERS (${_allPlayers.length})', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.mutedForeground)),
          const SizedBox(height: 8),
          ..._allPlayers.asMap().entries.map((entry) {
            final player = entry.value;
            final isCurrentTurn = _phase == _Phase.describing &&
                _currentTurnIndex < _turnOrder.length &&
                _turnOrder[_currentTurnIndex] == player.id;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: GestureDetector(
                onTap: player.id == 'me' ? () => _toggleReady('me') : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: isCurrentTurn ? AppColors.primary.withValues(alpha: 0.15) : null,
                    border: isCurrentTurn ? Border.all(color: AppColors.primary) : null,
                  ),
                  child: Row(
                    children: [
                      player.isBot
                          ? const Icon(Icons.smart_toy, size: 22, color: AppColors.mutedForeground)
                          : UserAvatar(avatarIndex: entry.key, radius: 12),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          player.nickname,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_phase == _Phase.waiting)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: player.isReady ? AppColors.success : AppColors.secondary,
                          ),
                          child: Text(
                            player.isReady ? '준비' : '대기',
                            style: TextStyle(fontSize: 9, color: player.isReady ? Colors.white : AppColors.mutedForeground),
                          ),
                        )
                      else if (player.isHost)
                        const Text('🦊', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMainArea(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_phase == _Phase.describing)
          Align(
            alignment: Alignment.centerLeft,
            child: Text('NOW TURN', style: TextStyle(fontSize: 10, color: AppColors.mutedForeground)),
          )
        else if (_phase == _Phase.allDone)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            color: AppColors.primary,
            child: const Text('ALL DONE!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.border)),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) => ChatBubble(message: _messages[index]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Opacity(
                opacity: _canChat ? 1 : 0.5,
                child: AppTextField(
                  controller: _chatController,
                  hintText: _canChat
                      ? (_phase == _Phase.describing ? '설명을 입력하세요...' : '채팅 메시지 입력...')
                      : (_phase == _Phase.describing ? '지금은 당신의 차례가 아닙니다' : '지금은 채팅할 수 없습니다'),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(onPressed: _canChat ? _sendMessage : null, icon: const Icon(Icons.send)),
          ],
        ),
        const SizedBox(height: 8),
        _buildBottomBar(context),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    switch (_phase) {
      case _Phase.waiting:
        return _buildWaitingBar(context);
      case _Phase.describing:
        return Row(
          children: [
            Expanded(
              child: Text(
                '${_nicknameFor(_turnOrder[_currentTurnIndex])}이(가) 설명 중입니다...',
                style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
              ),
            ),
            if (widget.isHost) AppButton(label: '다음 차례 ▶', fullWidth: false, onPressed: _skipTurn),
          ],
        );
      case _Phase.allDone:
        return Row(
          children: [
            const Expanded(child: Text('모든 플레이어가 설명했습니다.', style: TextStyle(fontSize: 12))),
            AppButton(label: '투표 시작', fullWidth: false, onPressed: _openVoteDialog),
          ],
        );
      case _Phase.voting:
        return const Text('투표 진행 중...', style: TextStyle(fontSize: 12));
      case _Phase.liarGuessWait:
        return Text(
          '${_votedOutId != null ? _nicknameFor(_votedOutId!) : ''}님이 역전승에 도전 중입니다...',
          style: const TextStyle(fontSize: 12),
        );
    }
  }

  Widget _buildWaitingBar(BuildContext context) {
    final readyCount = _allPlayers.where((p) => p.isReady).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.isHost ? 'CATEGORY (방장만 변경 가능)' : 'CATEGORY',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.mutedForeground),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ..._availableCategories.map((category) {
              final selected = category == _selectedCategory;
              return GestureDetector(
                onTap: () => _selectCategory(category),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.secondary,
                    border: Border.all(color: selected ? AppColors.primaryBorder : AppColors.border),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppColors.foreground, fontWeight: FontWeight.bold),
                  ),
                ),
              );
            }),
            if (widget.isHost)
              SizedBox(
                width: 120,
                child: AppTextField(
                  controller: _customCategoryController,
                  hintText: '직접 입력...',
                  onSubmitted: (_) => _addCustomCategory(),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('AI 플레이어 봇', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              onPressed: widget.isHost ? () => _changeBotCount(-1) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('$_botCount', style: Theme.of(context).textTheme.titleMedium),
            IconButton(
              onPressed: widget.isHost ? () => _changeBotCount(1) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '$readyCount/${_allPlayers.length} 명 준비 완료',
                style: TextStyle(fontSize: 12, color: AppColors.mutedForeground),
              ),
            ),
            if (widget.isHost)
              AppButton(label: '시작하기', fullWidth: false, onPressed: _canStartGame ? _startGame : null)
            else
              AppButton(
                label: _humanPlayers.firstWhere((p) => p.id == 'me').isReady ? '준비 완료' : '준비하기',
                fullWidth: false,
                variant: _humanPlayers.firstWhere((p) => p.id == 'me').isReady
                    ? AppButtonVariant.primary
                    : AppButtonVariant.outlined,
                onPressed: () => _toggleReady('me'),
              ),
          ],
        ),
      ],
    );
  }
}

class _WordCard extends StatelessWidget {
  final String label;
  final String word;
  final Color color;

  const _WordCard({required this.label, required this.word, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), border: Border.all(color: color)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: AppColors.mutedForeground)),
          const SizedBox(height: 4),
          Text(word, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}

class _LiarGuessForm extends StatefulWidget {
  final ValueChanged<String> onSubmit;

  const _LiarGuessForm({required this.onSubmit});

  @override
  State<_LiarGuessForm> createState() => _LiarGuessFormState();
}

class _LiarGuessFormState extends State<_LiarGuessForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('제시어 입력', style: TextStyle(fontSize: 11, color: AppColors.mutedForeground)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _controller,
                hintText: '제시어를 입력하세요...',
                onSubmitted: widget.onSubmit,
              ),
            ),
            const SizedBox(width: 8),
            AppButton(label: '제출', fullWidth: false, onPressed: () => widget.onSubmit(_controller.text.trim())),
          ],
        ),
      ],
    );
  }
}
