import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat_message.dart';
import '../../models/game_phase.dart';
import '../../models/player.dart';
import '../../widgets/hover_tap.dart';
import '../../services/auth_service.dart';
import '../../state/room_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/pixel_font.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/countdown_text.dart';
import '../../widgets/pixel_box.dart';
import '../../widgets/user_avatar.dart';

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
  final _scrollController = ScrollController();
  final _customCategoryController = TextEditingController();

  // 방장 대기방 드래프트(로컬 입력 → game:draftConfig로 서버에 실시간 공유).
  int _botCount = 0;
  String? _selectedChip;
  bool _aiRandom = false;
  bool _leaving = false;
  int _lastChatLen = 0;
  bool _hostDraftSeeded = false;

  String? get _myUid => AuthService.instance.currentUser?.uid;

  @override
  void dispose() {
    _chatController.dispose();
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
    _leaving = true;
    ref.read(roomProvider.notifier).leaveRoom();
    if (mounted) Navigator.of(context).pop();
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
    ref.read(roomProvider.notifier).configureGame(category: category, aiBotCount: _botCount);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(roomProvider);
    final myUid = _myUid;

    // 방이 닫혔거나(방장 퇴장) 우리가 나간 경우 roomCode가 사라진다 → 로비로 복귀.
    ref.listen<String?>(roomProvider.select((v) => v.roomCode), (prev, next) {
      if (prev != null && next == null && mounted && !_leaving) {
        Navigator.of(context).pop();
      }
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _header(s),
              Expanded(child: _chatFeed(s)),
              _contextPanel(s, isHost),
              _inputBar(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(RoomViewState s) {
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
          HoverTap(
            onTap: _leave,
            child: const Icon(Icons.exit_to_app, color: AppColors.mutedForeground),
          ),
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
        child: ChatBubble(message: _displayMessage(s.chatLog[i], s)),
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
        return _describingPanel(s);
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
          // 참가자 준비 상태
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: s.players
                .map((p) => Chip(
                      avatar: Icon(p.isReady ? Icons.check_circle : Icons.hourglass_empty,
                          size: 14, color: p.isReady ? AppColors.success : AppColors.mutedForeground),
                      label: Text('${p.nickname}${p.id == s.hostId ? ' 👑' : ''}',
                          style: PixelFont.body(fontSize: 11, color: AppColors.foreground)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          if (me != null)
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
            AppButton(label: '게임 시작 ▶', onPressed: canStart ? _startGame : null),
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
          if (s.myWordExplanation != null) ...[
            const SizedBox(height: 4),
            Text(s.myWordExplanation!, style: PixelFont.body(fontSize: 11, color: AppColors.foreground)),
          ],
        ],
      ),
    );
  }

  Widget _describingPanel(RoomViewState s) {
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
              Text(myTurn ? '내 차례! 제시어를 설명하세요' : '$turnNick님이 설명 중...',
                  style: PixelFont.body(fontSize: 12, color: myTurn ? AppColors.primary : AppColors.foreground)),
              if (s.phaseDeadline != null)
                CountdownText(
                  deadline: s.phaseDeadline!,
                  style: PixelFont.title(fontSize: 12, color: AppColors.foreground),
                ),
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
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: candidates.map((p) {
              return HoverTap(
                onTap: () => ref.read(roomProvider.notifier).castVote(p.id),
                child: PixelBox(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(avatarIndex: _avatarIndexFor(p.id, s), radius: 10),
                      const SizedBox(width: 6),
                      Text(p.nickname, style: PixelFont.body(fontSize: 11, color: AppColors.foreground)),
                    ],
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
              result.winner == 'citizens' ? '🎉 시민 팀 승리!' : '😈 라이어 팀 승리!',
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
            onPressed: () {
              final g = guessController.text.trim();
              if (g.isNotEmpty) ref.read(roomProvider.notifier).guessWord(g);
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
