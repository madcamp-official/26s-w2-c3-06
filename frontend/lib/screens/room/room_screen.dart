import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../../widgets/app_alert.dart';
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

const _presetCategories = <String>[
  '음식', '동물', '영화', '스포츠', '직업', '나라',
  '반려동물', '해양동물', '곤충', '공룡', '학교', '놀이공원', '편의점',
  '병원', '도서관', '지하철역', '호텔',
  '가전제품', '악기',
  '디즈니', '마블', '한국영화', '해외영화',
  '위인', '색깔', '랜드마크',
  '가수', '걸그룹',
  '빵', '자동차브랜드', '라면', '과자',
  '사자성어', '취미',
];
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

  // 메시지 입력창 위 페이즈 컨텍스트 박스(카테고리/타이머/투표 등)를 채팅을 더 넓게 보고
  // 싶을 때 직접 접었다 펼 수 있게 하는 토글 상태(_contextPanelToggle 참고).
  bool _contextPanelCollapsed = false;

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

  // 후보 선택(변경 가능)과 별개로, "투표 확정"을 눌러야 서버 집계에 확정으로 반영된다.
  // 확정 후 후보를 바꾸면 서버 쪽 확정도 취소되므로 여기서도 함께 false로 되돌린다.
  bool _myVoteConfirmed = false;

  // 이 화면의 팝업은 항상 한 번에 하나만 떠 있어야 한다 — 새 팝업을 열어야 하는데 이미
  // 하나가 떠 있으면(예: 역전 기회 입력 중에 시간 만료로 결과가 먼저 와버린 경우) 팝업 위에
  // 팝업을 쌓지 않고 이전 것을 먼저 닫는다. 모든 다이얼로그는 showPixelDialog를 직접 부르지
  // 말고 이 헬퍼(_showManagedDialog)를 거쳐야 한다.
  bool _dialogOpen = false;
  // 팝업이 다른 팝업에 의해 강제로 닫히면(아래 pop()) 그 await가 그제서야 완료되면서
  // _dialogOpen = false를 실행하는데, 이게 그 사이 새로 열린 팝업보다 늦게 실행되면
  // 방금 연 팝업의 "열려있음" 표시를 잘못 지워버린다(라이어가 맞았어요 → 역전 기회 →
  // 게임 결과처럼 팝업이 3개 연달아 이어질 때 세 번째가 두 번째를 못 닫는 원인이었다).
  // 매 호출마다 토큰을 발급해 "내가 아직 최신 팝업일 때만" 플래그를 지우게 해서 막는다.
  int _dialogToken = 0;

  // 턴이 바뀔 때 확인 버튼을 눌러야 닫히는 팝업을 띄우면 설명 페이즈 내내 계속 끊기므로,
  // 화면 상단에 잠깐 떴다 스스로 사라지는 배너를 직접 오버레이로 띄운다.
  OverlayEntry? _turnToastEntry;

  void _showTurnToast(String text, {required bool isMine}) {
    _turnToastEntry?.remove();
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 0,
        right: 0,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: PixelBox(
              color: isMine ? AppColors.primary : AppColors.card,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  text,
                  style: PixelFont.title(fontSize: 13, color: isMine ? Colors.white : AppColors.foreground),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _turnToastEntry = entry;
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () {
      if (_turnToastEntry == entry) {
        entry.remove();
        _turnToastEntry = null;
      }
    });
  }

  Future<T?> _showManagedDialog<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = false,
    double maxWidth = 460,
  }) async {
    // 채팅 입력 중에 팝업이 뜨면(투표 시작·결과 등) 다이얼로그가 닫힐 때 네비게이터가
    // 채팅 입력창으로 포커스를 "프로그램적으로" 복원하는데, 웹에서는 이 경로가 브라우저
    // input 요소와 연결이 끊긴 유령 포커스를 만들 수 있다(flutter#98786 — 새로고침 전까지
    // 타이핑이 안 먹던 버그의 원인). 팝업을 열기 전에 미리 포커스를 풀어 복원 대상 자체를
    // 없앤다. 닫힌 뒤에는 사용자가 입력창을 탭하면 새 포커스로 정상 연결된다.
    _chatFocusNode.unfocus();
    if (_dialogOpen && mounted) {
      Navigator.of(context).pop();
    }
    _dialogOpen = true;
    final myToken = ++_dialogToken;
    final result = await showPixelDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      maxWidth: maxWidth,
      builder: builder,
    );
    if (myToken == _dialogToken) _dialogOpen = false;
    return result;
  }

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
    _turnToastEntry?.remove();
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
    final confirmed = await _showManagedDialog<bool>(
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

  /// 예기치 않게 소켓 연결이 끊겼을 때 — 확인을 눌러야 닫히는 알림창을 띄운 뒤 로비로 나간다.
  Future<void> _showDisconnectedDialog() async {
    await _showManagedDialog<void>(
      maxWidth: 320,
      builder: (dialogContext) {
        return dialogEnterToConfirm(
          onConfirm: () => Navigator.of(dialogContext).pop(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('⚠️ 연결 끊김', style: PixelFont.title(fontSize: 13, color: AppColors.destructive)),
              const SizedBox(height: 12),
              Text(
                '서버와의 연결이 끊어졌어요. 로비로 돌아갑니다.',
                style: PixelFont.body(fontSize: 12, color: AppColors.foreground),
              ),
              const SizedBox(height: 18),
              AppButton(label: '확인', onPressed: () => Navigator.of(dialogContext).pop()),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    ref.read(roomProvider.notifier).reset();
    _returnToLobby();
  }

  /// 최종 결과(지목된 사람·라이어 여부·실제/라이어 제시어·역전승 여부)를 채팅 로그에
  /// 묻히지 않도록 큰 알림창으로 한 번에 보여준다.
  Future<void> _showResultDialog(GameResult r) async {
    final citizensWin = r.citizensWin;
    String accusedText;
    if (r.accusedNickname == null) {
      accusedText = '아무도 지목되지 않았어요';
    } else {
      accusedText = '${r.accusedNickname} (라이어 ${r.wasLiar ? '⭕' : '❌'})';
    }
    String liarGuessText;
    if (r.liarGuessCorrect == null) {
      liarGuessText = '역전승 시도 없음';
    } else if (r.liarGuessCorrect == true) {
      liarGuessText = r.liarGuess == null ? '✅ 성공 — 라이어 역전승!' : '✅ 성공 — "${r.liarGuess}" 정답!';
    } else {
      liarGuessText = r.liarGuess == null ? '❌ 실패' : '❌ 실패 — "${r.liarGuess}"라고 썼어요';
    }

    await _showManagedDialog<void>(
      maxWidth: 380,
      builder: (dialogContext) {
        return dialogEnterToConfirm(
          onConfirm: () => Navigator.of(dialogContext).pop(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                citizensWin ? '시민팀의 승리!' : '라이어팀의 승리!',
                textAlign: TextAlign.center,
                style: PixelFont.title(fontSize: 18, color: AppColors.primary),
              ),
              const SizedBox(height: 20),
              _ResultRow(label: '지목된 사람', value: accusedText),
              // 지목된 사람이 라이어가 아니었다면(오지목·무지목) 진짜 라이어가 누구였는지
              // 이 결과 창 말고는 알 방법이 없으므로 항상 함께 공개한다.
              if (!r.wasLiar) _ResultRow(label: '진짜 라이어', value: r.liarNickname),
              _ResultRow(label: '실제 제시어', value: r.realWord),
              _ResultRow(label: '라이어 제시어', value: r.liarWord),
              _ResultRow(label: '라이어 역전승', value: liarGuessText),
              const SizedBox(height: 22),
              AppButton(label: '확인', onPressed: () => Navigator.of(dialogContext).pop()),
            ],
          ),
        );
      },
    );
  }

  /// 투표 후보를 화면 가운데 팝업으로 고르게 한다. 후보를 눌러도 바로 제출되지 않고
  /// 팝업 안에서 자유롭게 바꿔 고를 수 있으며, "투표 확인"을 눌러야 실제로 castVote가
  /// 나간다 — 서버도 제한시간 안에서는 재투표(덮어쓰기)를 허용하므로, 이 팝업을 다시 열어
  /// (투표 변경하기) 마음이 바뀐 선택으로 다시 제출할 수 있다.
  Future<void> _openVoteDialog(RoomViewState s) async {
    final myUid = _myUid;
    // 후보는 나 자신을 제외하고, 서버가 지금 유효하다고 알려준 목록(voteCandidateIds)
    // 안에서만 고를 수 있다 — 동점 재투표면 직전 동점자로 제한된다.
    final candidates = s.participants
        .where((p) => p.id != myUid && s.voteCandidateIds.contains(p.id))
        .toList();
    String? draft = _myVote;

    final confirmed = await _showManagedDialog<String>(
      maxWidth: 380,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('🗳️ VOTE', style: PixelFont.title(fontSize: 16, color: AppColors.primary)),
                const SizedBox(height: 8),
                Text(
                  '라이어를 지목하세요. 한 명만 선택할 수 있습니다.',
                  style: PixelFont.body(fontSize: 12, color: AppColors.mutedForeground),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  // 2.6이던 값은 화면 폭이 좁은 실기기에서 셀 높이가 아바타+닉네임보다 작아져
                  // "bottom overflowed" 나던 원인이었다 — 셀을 더 세로로 넉넉하게 준다.
                  childAspectRatio: 1.8,
                  children: candidates.map((p) {
                    final selected = draft == p.id;
                    return HoverTap(
                      onTap: () => setDialogState(() => draft = p.id),
                      child: PixelBox(
                        // 알파 블렌딩된 주황 틴트가 실기기에서 어둡게 보인다는 피드백이 있어,
                        // 알파 없이 밝은 불투명 색(accent)을 채우고 테두리/글자로 주황을 유지한다.
                        color: selected ? AppColors.accent : AppColors.card,
                        border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            UserAvatar(
                              avatarIndex: _avatarIndexFor(p.id, s),
                              radius: 14,
                              imageUrl: p.isBot ? null : _avatarUrlFor(p.id),
                              isBot: p.isBot,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p.nickname,
                              style: PixelFont.body(
                                fontSize: 11,
                                color: selected ? AppColors.primary : AppColors.foreground,
                                fontWeight: selected ? FontWeight.bold : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: '취소',
                        variant: AppButtonVariant.outlined,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: '투표 확인',
                        accentColor: AppColors.destructive,
                        onPressed: draft == null ? null : () => Navigator.of(dialogContext).pop(draft),
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

    if (confirmed == null || !mounted) return;
    // 이 다이얼로그는 확정 전에만 열 수 있으므로(_myVoteConfirmed면 버튼 자체가 비활성)
    // 여기 도달했다는 건 아직 확정 전이라는 뜻이다.
    setState(() => _myVote = confirmed);
    ref.read(roomProvider.notifier).castVote(confirmed);
  }

  /// 투표가 집계되자마자(라이어 여부와 무관하게) 누가 지목됐는지 팝업으로 알린다.
  /// 실제/라이어 제시어는 아직 공개하지 않는다 — 지목된 사람이 진짜 라이어라면 바로 이어질
  /// 역전 기회에서 스스로 진짜 제시어를 맞혀야 하므로, 여기서 미리 흘리면 그 긴장이 사라진다.
  Future<void> _showVoteResultDialog(RoomViewState s, RoundResolved r) async {
    final accusedNickname = r.votedOutId == null ? null : s.nicknameOf(r.votedOutId!);
    final subtitle = accusedNickname == null
        ? '아무도 과반의 지목을 받지 못했어요.'
        : (r.wasLiar ? '실제 라이어가 맞았습니다! 역전 기회가 주어집니다.' : '라이어가 아니었습니다...');

    await _showManagedDialog<void>(
      maxWidth: 360,
      builder: (dialogContext) {
        return dialogEnterToConfirm(
          onConfirm: () => Navigator.of(dialogContext).pop(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('🗳️ 투표 결과', style: PixelFont.title(fontSize: 16, color: AppColors.primary)),
              const SizedBox(height: 16),
              if (accusedNickname != null) ...[
                Center(
                  child: UserAvatar(
                    avatarIndex: _avatarIndexFor(r.votedOutId!, s),
                    radius: 24,
                    imageUrl: _avatarUrlFor(r.votedOutId!),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$accusedNickname님이 라이어로 지목됐습니다',
                  textAlign: TextAlign.center,
                  style: PixelFont.title(fontSize: 14, color: AppColors.foreground),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: PixelFont.body(fontSize: 12, color: AppColors.mutedForeground),
              ),
              const SizedBox(height: 20),
              AppButton(label: '확인', onPressed: () => Navigator.of(dialogContext).pop()),
            ],
          ),
        );
      },
    );
  }

  /// 지목된 사람이 실제 라이어일 때만 그 사람의 소켓에 도착하는 역전 기회 팝업 — 진짜
  /// 제시어를 맞히면 라이어 역전승. 시간이 다 되면 서버가 스스로 게임을 끝내고 finalResult를
  /// 보내는데, 그때 이 팝업이 아직 열려 있으면 _showManagedDialog가 대신 닫아준다.
  Future<void> _showLiarGuessDialog(int timeLimitSec) async {
    final deadline = DateTime.now().add(Duration(seconds: timeLimitSec));
    final guessController = TextEditingController();

    await _showManagedDialog<void>(
      barrierDismissible: false,
      maxWidth: 380,
      builder: (dialogContext) {
        void submit() {
          final g = guessController.text.trim();
          if (g.isEmpty) return;
          setState(() => _submittingGuess = true);
          ref.read(roomProvider.notifier).guessWord(g);
          Navigator.of(dialogContext).pop();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('🔄 역전 기회!', style: PixelFont.title(fontSize: 16, color: AppColors.primary)),
                CountdownText(deadline: deadline, style: PixelFont.title(fontSize: 14, color: AppColors.foreground)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '당신이 라이어로 지목됐습니다. 진짜 제시어를 맞히면 역전승할 수 있어요!',
              style: PixelFont.body(fontSize: 12, color: AppColors.mutedForeground),
            ),
            const SizedBox(height: 16),
            AppTextField(controller: guessController, hintText: '진짜 제시어', onSubmitted: (_) => submit()),
            const SizedBox(height: 12),
            AppButton(label: '제출', onPressed: submit),
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
        showAppAlert(context, '친구 목록을 불러오지 못했습니다.');
      }
      return;
    }
    final online = friends.where((f) => f.isOnline).toList();
    if (!mounted) return;

    await _showManagedDialog<void>(
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
    if (kIsWeb) {
      _refocusChat();
    } else {
      _chatFocusNode.requestFocus();
    }
  }

  /// 웹에서 hasFocus인 채로 브라우저 input 연결만 끊긴 유령 포커스 상태(flutter#98786)를
  /// 복구/예방한다 — 이미 포커스가 있으면 requestFocus()가 no-op이 돼 연결이 재수립되지
  /// 않으므로, 완전히 풀었다가 다음 프레임에 다시 잡아 실제 포커스 변화를 강제한다.
  void _refocusChat() {
    _chatFocusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chatFocusNode.requestFocus();
    });
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

  /// 카테고리를 한 번에 다 나열하지 않고, 이 버튼으로 목록을 펼쳐 그중에서 고르게 한다.
  Future<void> _openCategoryPicker() async {
    final chipCategories = <String>[
      ..._presetCategories,
      ...ref.read(roomProvider).customCategories.where((c) => !_presetCategories.contains(c)),
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      // 카테고리가 60개 넘게 늘어나면서 시트 안에 다 안 들어가 스크롤이 필요해졌다 —
      // isScrollControlled로 시트가 기본 절반 높이 제한을 넘어설 수 있게 하고, 그리드만
      // Expanded+스크롤 가능하게 해서 제목/직접입력/확인 버튼은 항상 보이게 고정한다.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void select({String? chip, bool aiRandom = false}) {
              setState(() {
                _aiRandom = aiRandom;
                _selectedChip = chip;
                if (chip != null || aiRandom) _customCategoryController.clear();
              });
              setSheetState(() {});
              _pushDraft();
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('카테고리 선택', style: PixelFont.title(fontSize: 13, color: AppColors.primary)),
                    const SizedBox(height: 12),
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 4,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 1.3,
                        children: [
                      ...chipCategories.map((c) {
                        final selected = !_aiRandom && _selectedChip == c;
                        return HoverTap(
                          onTap: () => select(chip: c),
                          child: PixelBox(
                            color: selected ? AppColors.primary : AppColors.card,
                            border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: 2),
                            child: Center(
                              child: Text(
                                c,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: PixelFont.body(
                                  fontSize: 11,
                                  color: selected ? Colors.white : AppColors.foreground,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      HoverTap(
                        onTap: () => select(aiRandom: true),
                        child: PixelBox(
                          color: _aiRandom ? AppColors.primary : AppColors.card,
                          border: Border.all(color: _aiRandom ? AppColors.primary : AppColors.border, width: 2),
                          child: Center(
                            child: Text(
                              '🎲 랜덤',
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: PixelFont.body(
                                fontSize: 11,
                                color: _aiRandom ? Colors.white : AppColors.foreground,
                              ),
                            ),
                          ),
                        ),
                      ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
                        setSheetState(() {});
                        _pushDraft();
                      },
                      onSubmitted: (_) => Navigator.of(sheetContext).pop(),
                    ),
                    const SizedBox(height: 12),
                    AppButton(label: '확인', onPressed: () => Navigator.of(sheetContext).pop()),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
        setState(() {
          _myVote = null;
          _myVoteConfirmed = false;
        });
        // 투표 페이즈 진입 시 화면 가운데 팝업으로 바로 투표를 띄운다.
        _openVoteDialog(ref.read(roomProvider));
      }
      if (next == GamePhase.describing && prev != GamePhase.describing) {
        // 게임이 시작되면 서버가 draftConfig를 category:null/aiBotCount:0으로 초기화한다.
        // 방장의 로컬 드래프트(_selectedChip 등)는 이 리셋과 무관하게 이전 값이 남아있어서,
        // 다음 대기방에서 다른 참가자는(서버가 보낸) "AI 랜덤"을 보는데 방장 화면만 직전
        // 선택이 그대로 남아있다가 그 값으로 게임이 다시 시작되는 어긋남이 있었다 —
        // 여기서 함께 리셋해 다음 대기방 진입 시 서버 draftConfig로 다시 시드되게 한다.
        setState(() {
          _startingGame = false;
          _hostDraftSeeded = false;
          _selectedChip = null;
          _aiRandom = false;
          _botCount = 0;
          _customCategoryController.clear();
        });
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
    // 투표가 집계되면(누가 라이어로 지목됐는지) 바로 팝업으로 알린다 — 그 사람이 실제
    // 라이어라면 뒤이어 역전 기회(liarGuessTimeLimitSec) 팝업으로 이어진다.
    ref.listen<RoundResolved?>(roomProvider.select((v) => v.roundResolved), (prev, next) {
      if (prev == null && next != null) {
        _showVoteResultDialog(ref.read(roomProvider), next);
      }
    });
    // 역전 기회 프롬프트는 지목된 사람(라이어 본인)의 소켓에만 오므로, 이걸 받는 클라이언트가
    // 곧 라이어 자신이다. 정답 입력을 팝업으로 띄운다.
    ref.listen<int?>(roomProvider.select((v) => v.liarGuessTimeLimitSec), (prev, next) {
      if (prev == null && next != null) {
        _showLiarGuessDialog(next);
      }
    });
    // 최종 결과(지목된 사람·라이어 여부·실제/라이어 제시어·역전승 여부)가 다 갖춰지면
    // 채팅으로 흘려보내지 않고 큰 알림창으로 한 번에 보여준다.
    ref.listen<RoundFinalResult?>(roomProvider.select((v) => v.finalResult), (prev, next) {
      if (prev == null && next != null) {
        // 역전 기회 팝업이 아직 떠 있다면(시간 만료로 서버가 먼저 게임을 끝낸 경우)에도
        // _showManagedDialog가 새 팝업을 열기 전에 알아서 먼저 닫아준다.
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
        showAppAlert(context, message);
      });
    });
    // 예기치 않게 소켓 연결이 끊기면(네트워크 문제 등) 확인 알림창을 띄우고 바로 로비로 나간다.
    ref.listen<AsyncValue<void>>(socketDisconnectedProvider, (prev, next) {
      if (next.hasValue && !_leaving) {
        _leaving = true;
        _showDisconnectedDialog();
      }
    });
    // 설명 차례가 바뀐 걸 못 알아챈다는 피드백 — 확인 버튼이 필요한 팝업 대신, 잠깐 떴다
    // 사라지는 배너로 매 턴마다 알려준다(내 차례인지 아닌지 문구를 다르게 보여준다).
    ref.listen<String?>(roomProvider.select((v) => v.currentTurnPlayerId), (prev, next) {
      if (next == null || next == prev) return;
      final s = ref.read(roomProvider);
      if (next == _myUid) {
        _showTurnToast('내 차례예요! 제시어를 설명해주세요', isMine: true);
      } else {
        _showTurnToast('${s.nicknameOf(next)}님 차례예요', isMine: false);
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
        // 방장이 아직 아무 카테고리도 고르지 않은 새 방은 프리셋 첫 번째 칩(음식)을
        // 기본 선택으로 보여주고, 서버 draftConfig에도 같은 값을 반영해 다른 참가자
        // 화면과 실제 게임 시작 카테고리가 어긋나지 않게 한다.
        _selectedChip = _presetCategories.first;
        WidgetsBinding.instance.addPostFrameCallback((_) => _pushDraft());
      } else if (_presetCategories.contains(cat) || s.customCategories.contains(cat)) {
        _selectedChip = cat;
      } else {
        _customCategoryController.text = cat;
      }
    }

    final isDesktop = context.isDesktop;
    // 데스크탑에서는 나가기/초대 버튼이 헤더가 아니라 좌측 내비게이션 바로 이동한다
    // (frontend 브랜치의 데스크탑 레이아웃 참고, lobby_screen과 동일한 패턴).
    // 모바일에서 키보드가 실제로 열려있는 동안(MediaQuery.viewInsets.bottom > 0), 화면에서
    // 세로 공간을 크게 잡아먹는 참가자 아바타 줄·페이즈 컨텍스트 박스(카테고리/타이머/투표 등)를
    // 접어 채팅 목록이 키보드에 가려지지 않고 그대로 보이게 한다. 고정 요소 합이 화면 높이를
    // 넘겨 "bottom overflowed" 나던 문제도 이걸로 해결된다.
    // TextField 포커스 여부(_chatFocusNode.hasFocus) 대신 실제 키보드 인셋을 기준으로 삼는데,
    // 안드로이드에서 뒤로가기/제스처로 키보드만 내리면 포커스는 그대로 남아있어(hasFocus는
    // true 유지) 포커스 기반으로는 키보드를 내려도 박스가 다시 안 나타나는 문제가 있었다.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final hideForKeyboard = !isDesktop && keyboardOpen;
    // 투표 중엔 확정 상태/버튼을 반드시 볼 수 있어야 하므로, 접힘·키보드에 의한 숨김을
    // 무시하고 항상 펼쳐 보여준다(접혀 있으면 확정했는지조차 확인할 방법이 없었다).
    final forceShowPanel = s.phase == GamePhase.voting;
    // 키보드와 무관하게, 채팅을 더 넓게 보고 싶을 때 직접 접었다 펼 수 있는 토글도 둔다.
    final showContextPanel = forceShowPanel || (!hideForKeyboard && !_contextPanelCollapsed);
    final body = Column(
      children: [
        _header(s, isHost, showActions: !isDesktop),
        if (!hideForKeyboard) _playerProfileRow(s, isHost),
        Expanded(child: _chatFeed(s)),
        if (!hideForKeyboard && !forceShowPanel) _contextPanelToggle(showContextPanel),
        if (showContextPanel) _contextPanel(s, isHost),
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

  /// 현재 방 인원수(봇 포함). 게임 진행 중에는 실제 참가자 목록(participants)에서 봇 수를
  /// 세고, 대기 중(게임 시작 전/종료 후)에는 아직 봇이 실존하지 않으므로 방장이 드래프트로
  /// 골라둔 봇 수(draftAiBotCount)를 더해 "게임을 시작하면 될 인원"을 미리 보여준다.
  int _currentHeadcount(RoomViewState s) {
    final isWaiting = s.phase == GamePhase.waiting || s.phase == GamePhase.ended;
    final bots = isWaiting ? s.draftAiBotCount : s.participants.where((p) => p.isBot).length;
    return s.players.length + bots;
  }

  Widget _header(RoomViewState s, bool isHost, {required bool showActions}) {
    final emoji = (s.emoji?.isNotEmpty ?? false) ? s.emoji! : '🎮';
    final title = (s.title?.isNotEmpty ?? false) ? s.title! : '방 ${s.roomCode ?? ''}';
    return PixelBox(
      margin: const EdgeInsets.all(10),
      // 안의 글자만 키우고 바 자체 높이는 고정해서 그대로 유지한다.
      // 설명 턴 타이머 아이콘이 추가되면서 44px(56-패딩12) 콘텐츠 영역을 살짝 넘겨
      // "bottom overflowed"가 나던 걸 여유를 좀 더 둬서 해결한다.
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          if (s.llmMock) ...[
            _mockBadge(),
            const SizedBox(width: 8),
          ],
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: PixelFont.title(fontSize: 16, color: AppColors.foreground, height: 1.1),
                  overflow: TextOverflow.ellipsis,
                ),
                // 대기/종료 중엔 방 코드·인원을, 게임 진행 중(설명~역전승)엔 카테고리를 보여준다.
                if (s.category != null && s.phase != GamePhase.waiting && s.phase != GamePhase.ended)
                  Text(
                    '카테고리: ${s.category}',
                    style: PixelFont.body(fontSize: 13, color: AppColors.mutedForeground, height: 1.1),
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  Text(
                    '코드 ${s.roomCode ?? '----'} · ${_currentHeadcount(s)}/${s.maxPlayers ?? '-'}명',
                    style: PixelFont.body(fontSize: 13, color: AppColors.mutedForeground, height: 1.1),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // 타이머는 패널이 접히거나 키보드에 가려도 항상 보여야 해서 상단바 오른쪽에 크게
          // 고정 표시한다(설정 패널 안에 있으면 접혔을 때 아예 안 보이던 문제가 있었다).
          if (s.phaseDeadline != null) ...[
            const SizedBox(width: 8),
            _headerTimer(s),
          ],
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

  /// 상단바 오른쪽에 크게 보이는 타이머. 토론 중엔 -10초/+10초 조절 버튼도 양옆에 붙인다.
  Widget _headerTimer(RoomViewState s) {
    final isDiscussion = s.phase == GamePhase.discussion;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isDiscussion) ...[
          _timerAdjustButton(
            icon: Icons.remove_circle_outline,
            enabled: s.canShortenDiscussion,
            onTap: () => ref.read(roomProvider.notifier).adjustDiscussionTime(-10),
          ),
          const SizedBox(width: 4),
        ],
        const Icon(Icons.timer_outlined, size: 18, color: AppColors.primary),
        const SizedBox(width: 4),
        CountdownText(deadline: s.phaseDeadline!, style: PixelFont.title(fontSize: 18, color: AppColors.primary)),
        if (isDiscussion) ...[
          const SizedBox(width: 4),
          _timerAdjustButton(
            icon: Icons.add_circle_outline,
            enabled: s.canExtendDiscussion,
            onTap: () => ref.read(roomProvider.notifier).adjustDiscussionTime(10),
          ),
        ],
      ],
    );
  }

  /// 서버가 실제 LLM 대신 결정적 mock 응답으로 동작 중일 때(API 키 미설정 등)만 보이는
  /// 배지. 제시어/AI 설명/코멘트가 전부 고정 mock 값이라는 걸 바로 알 수 있게 상시 노출한다.
  Widget _mockBadge() {
    return Tooltip(
      message: '서버가 실제 LLM 대신 mock 응답으로 동작 중입니다 (API 키 미설정)',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.destructive,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.primaryBorder, width: 1.5),
        ),
        child: Text(
          'MOCK',
          style: PixelFont.title(fontSize: 10, color: Colors.white, height: 1),
        ),
      ),
    );
  }

  Widget _timerAdjustButton({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: HoverTap(
        onTap: enabled ? onTap : null,
        child: Icon(icon, size: 18, color: AppColors.mutedForeground),
      ),
    );
  }

  /// 참가자 프로필(아바타+닉네임+상태)을 화면 상단(헤더 바로 아래)에 가로로 나열한다.
  /// 대기 중엔 방장이 고르고 있는 봇 수만큼 로봇 이모지 카드를 함께 보여주고(아직 실제
  /// 봇은 게임 시작 전이라 존재하지 않음), 게임 중엔 실제 참가자 목록(participants, 봇 포함)을
  /// 쓴다. 인원이 많아 한 줄에 안 들어가면 가로로 스크롤해서 볼 수 있다.
  Widget _playerProfileRow(RoomViewState s, bool isHost) {
    final isWaiting = s.phase == GamePhase.waiting || s.phase == GamePhase.ended;

    final cards = <Widget>[
      for (final p in s.players)
        _PlayerProfileCard(
          avatar: UserAvatar(avatarIndex: _avatarIndexFor(p.id, s), radius: 13, imageUrl: _avatarUrlFor(p.id)),
          nickname: p.nickname,
          isMe: p.id == _myUid,
          isCurrentTurn: !isWaiting && s.currentTurnPlayerId == p.id,
          statusText: !isWaiting ? null : (p.id == s.hostId ? '👑방장' : (p.isReady ? '✓준비' : '대기')),
          statusColor: p.id == s.hostId
              ? AppColors.primary
              : (p.isReady ? AppColors.readyBadgeText : AppColors.waitingBadgeText),
        ),
    ];

    if (isWaiting) {
      // 대기 중엔 봇이 아직 실존하지 않아(방장이 고르고 있는 숫자일 뿐) 실제 id가 없으니
      // 그냥 번호로 자리만 채운다.
      final botCount = isHost ? _botCount : s.draftAiBotCount;
      for (var i = 0; i < botCount; i++) {
        cards.add(_PlayerProfileCard(
          avatar: UserAvatar(avatarIndex: 0, radius: 13, isBot: true),
          nickname: '봇${i + 1}',
          isMe: false,
          isCurrentTurn: false,
          statusText: '✓준비',
          statusColor: AppColors.readyBadgeText,
        ));
      }
    } else {
      // 게임 진행 중엔 실제 봇 id(participants)로 그려야 "지금 차례" 판정이 가능하다.
      for (final p in s.participants.where((p) => p.isBot)) {
        cards.add(_PlayerProfileCard(
          avatar: UserAvatar(avatarIndex: 0, radius: 13, isBot: true),
          nickname: p.nickname,
          isMe: false,
          isCurrentTurn: s.currentTurnPlayerId == p.id,
          statusText: null,
          statusColor: null,
        ));
      }
    }

    // 카드 높이를 고정 SizedBox로 강제하면(전에 78px로 고정했던 것) 폰트 렌더링에 따라
    // 내용이 살짝 넘칠 수 있어(RenderFlex overflow) 실제로 겪었던 문제였다. 대신
    // SingleChildScrollView+Row로 감싸 컨테이너 높이가 카드 내용에 맞게 자연스럽게
    // 정해지도록 해서 오버플로우 위험 자체를 없앤다.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            cards[i],
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

  /// 내 제시어 카드 — 채팅 로그에 섞이지 않고 채팅 입력창 바로 위(컨텍스트 패널)에 고정
  /// 표시된다. AI 설명이 있으면 눌러서 펼쳐볼 수 있다.
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

  /// 서버 메시지는 senderNickname/avatarIndex가 비어 있으므로 참가자 목록으로 해석해 채워 준다.
  /// highlight(게임 시작/종료 강조)도 서버 계약엔 없어, 시스템 메시지 문구로 여기서 판별한다.
  ChatMessage _displayMessage(ChatMessage m, RoomViewState s) {
    final nickname = m.isAi ? 'AI' : (m.isSystem ? '시스템' : s.nicknameOf(m.senderId));
    final isGameStart = m.isSystem && m.text.startsWith('새 게임이 시작되었습니다');
    final isGameStartOrEnd = isGameStart || (m.isSystem && m.text.startsWith('---- 게임이 종료되었습니다'));
    // 서버 브로드캐스트 문구엔 카테고리가 붙어있지만("... 카테고리: 음식"), 실제로는 사람마다
    // 배정된 제시어가 다르므로(진짜/가짜) 여기서 카테고리 언급은 지우고 내가 받은 제시어로
    // 클라이언트에서 개인화해 보여준다.
    final text = isGameStart ? '새 게임이 시작되었습니다! 제시어: ${s.myWord ?? "..."}' : m.text;
    return ChatMessage(
      id: m.id,
      senderId: m.senderId,
      senderNickname: nickname,
      avatarIndex: _avatarIndexFor(m.senderId, s),
      text: text,
      type: m.type,
      highlight: isGameStartOrEnd,
      timestamp: m.timestamp,
    );
  }

  int _avatarIndexFor(String id, RoomViewState s) {
    final pool = s.participants.isNotEmpty ? s.participants : s.players;
    final idx = pool.indexWhere((p) => p.id == id);
    return idx == -1 ? 0 : idx;
  }

  /// 채팅 목록을 더 넓게 보고 싶을 때 카테고리/타이머/투표 등 컨텍스트 박스를 직접
  /// 접었다 펼 수 있는 얇은 토글 바. [expanded]는 박스가 지금 펼쳐져 보이는 상태인지.
  Widget _contextPanelToggle(bool expanded) {
    // 좌우만 패널과 리듬을 맞추고, 상하는 텍스트 자체 줄 높이에 맡겨 토글 바와 그 아래
    // 패널 사이 빈 공간을 최대한 좁힌다.
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: HoverTap(
        onTap: () => setState(() => _contextPanelCollapsed = !_contextPanelCollapsed),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            expanded ? '▼ 설정 닫기' : '▲ 설정 열기',
            textAlign: TextAlign.center,
            style: PixelFont.body(fontSize: 12, color: AppColors.mutedForeground),
          ),
        ),
      ),
    );
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
        return _discussionPanel(s);
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
        // 위쪽만 더 줄여 바로 위 토글 바와의 간격이 최소한만 남게 한다.
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: child,
      );

  Widget _waitingPanel(RoomViewState s, bool isHost) {
    final myUid = _myUid;
    final me = s.players.where((p) => p.id == myUid).cast<Player?>().firstWhere((_) => true, orElse: () => null);
    final allReady = s.players.isNotEmpty && s.players.every((p) => p.isReady);
    // 사람+봇 합이 방 최대 인원(maxPlayers)을 넘을 수 없다 — 서버(game:configure)도 같은
    // 상한을 검증하지만, 여기서 미리 막아야 "시작" 눌렀을 때 room:error로 튕기지 않는다.
    final maxBotCount = ((s.maxPlayers ?? 8) - s.players.length).clamp(0, 8);
    if (isHost && _botCount > maxBotCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _botCount = maxBotCount);
      });
    }
    final botCount = isHost ? _botCount : s.draftAiBotCount;
    final enough = s.players.length + botCount >= _minParticipants;
    final canStart = isHost && allReady && enough;

    // 방장이 프리셋 칩이 아니라 직접 입력으로 카테고리를 골랐으면 _selectedChip은 null로
    // 비워두고 _customCategoryController에만 값이 남는다(_pushDraft와 동일한 우선순위) —
    // 여기서도 그 순서를 그대로 따라야 방장 화면에 "선택 안 함"으로 잘못 보이지 않는다.
    final customCategory = _customCategoryController.text.trim();
    final selectedChip = isHost
        ? (customCategory.isNotEmpty ? customCategory : _selectedChip)
        : s.draftCategory;
    final aiRandom = isHost ? _aiRandom : s.draftCategory == null;

    return _panelBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 참가자 프로필(아바타·준비 상태)은 화면 상단(_playerProfileRow)으로 옮겨졌다.
          // 방장은 서버가 참여 즉시 준비 완료로 고정해두므로(봇과 동일 규칙) 준비 토글을
          // 보여주지 않는다. 방장이 아닌 참가자만 직접 준비 상태를 토글하고, 이 버튼은
          // 방장 화면의 "시작 ▶" 버튼과 같은 자리(가로 한 줄의 맨 끝)에 놓인다.
          if (isHost) ...[
            const SizedBox(height: 10),
            // 안내 문구가 없어지는 조건(전원 준비 완료 + 인원 충분)일 때 빈 여백만 남지 않도록,
            // 문구와 그 아래 간격을 하나의 묶음으로 묶어 문구가 없으면 간격도 같이 사라지게 한다.
            if (!allReady) ...[
              Text('모든 참가자가 준비 완료해야 시작할 수 있어요.',
                  style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
              const SizedBox(height: 6),
            ] else if (!enough) ...[
              Text('참가자(사람+봇)가 최소 $_minParticipants명 이상이어야 해요.',
                  style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
              const SizedBox(height: 6),
            ],
            // 카테고리 선택 + AI 봇 수 조절을 한 줄에, 게임 시작은 아래 별도 줄에 둔다 —
            // 예전엔 이 다섯 요소를 한 줄에 다 욱여넣었는데, 화면 폭이 좁은 실기기에서
            // Row가 가로로 넘쳐(overflow) 봇 수 +/- 버튼이 아예 안 보이는 문제가 있었다.
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: '카테고리: ${aiRandom ? "AI 랜덤" : (selectedChip ?? "선택 안 함")}',
                    variant: AppButtonVariant.outlined,
                    dense: true,
                    onPressed: _openCategoryPicker,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    setState(() => _botCount = (_botCount - 1).clamp(0, maxBotCount));
                    _pushDraft();
                  },
                  icon: const Icon(Icons.remove_circle_outline, size: 18),
                ),
                Text('🤖$_botCount', style: PixelFont.title(fontSize: 16, color: AppColors.foreground)),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: _botCount >= maxBotCount
                      ? null
                      : () {
                          setState(() => _botCount = (_botCount + 1).clamp(0, maxBotCount));
                          _pushDraft();
                        },
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AppButton(
              label: '시작 ▶',
              dense: true,
              loading: _startingGame,
              onPressed: canStart && !_startingGame ? _startGame : null,
            ),
            // AI가 제시어 쌍(+카테고리 랜덤이면 카테고리까지)을 생성하는 데 몇 초 걸릴 수
            // 있어서, 버튼 스피너만으론 뭘 기다리는 건지 알기 어려웠다 — 문구로 명시한다.
            if (_startingGame) ...[
              const SizedBox(height: 6),
              Text('AI가 제시어를 생성하는 중이에요...',
                  style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
            ],
          ] else ...[
            const SizedBox(height: 10),
            // 방장이 아닌 참가자 화면도 위로 쌓지 않고 가로 한 줄로 나열한다.
            Row(
              children: [
                Expanded(
                  child: Text(
                    '카테고리: ${aiRandom ? "AI 랜덤" : (selectedChip ?? "선택 중...")}',
                    style: PixelFont.body(fontSize: 13, color: AppColors.foreground, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text('🤖$botCount', style: PixelFont.title(fontSize: 16, color: AppColors.foreground)),
                if (me != null) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 2,
                    child: AppButton(
                      label: me.isReady ? '준비완료 ✓' : '준비하기',
                      variant: me.isReady ? AppButtonVariant.outlined : AppButtonVariant.primary,
                      dense: true,
                      onPressed: () => ref.read(roomProvider.notifier).setReady(!me.isReady),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _describingPanel(RoomViewState s, bool isHost) {
    final myTurn = s.isMyTurn(_myUid);
    // 설명 제출 직후~다음 턴 시작 전(AI 코멘트 생성 대기 중)에는 currentTurnPlayerId가
    // 잠깐 비어있다(room_provider.submitDescription 참고) — 다음 턴 안내 문구를 보여준다.
    final waitingNextTurn = s.currentTurnPlayerId == null;
    final turnNick = waitingNextTurn ? '' : s.nicknameOf(s.currentTurnPlayerId!);
    final statusText = waitingNextTurn
        ? 'AI 코멘트 생성 중... 곧 다음 턴이 시작돼요'
        : (myTurn ? '내 차례! 제시어를 설명하세요' : '$turnNick님이 설명 중...');
    return _panelBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _myWordCard(s),
          // 타이머는 접히거나 키보드에 가려도 항상 보여야 해서 상단바로 옮겼다(_headerTimer 참고).
          Text(statusText,
              style: PixelFont.body(fontSize: 12, color: myTurn ? AppColors.primary : AppColors.foreground)),
        ],
      ),
    );
  }

  Widget _discussionPanel(RoomViewState s) {
    return _panelBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _myWordCard(s),
          // 타이머·조절 버튼은 상단바로 옮겼다(_headerTimer 참고).
          Text('자유 토론 중', style: PixelFont.body(fontSize: 12, color: AppColors.foreground)),
        ],
      ),
    );
  }

  Widget _votingPanel(RoomViewState s) {
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
              child: Text('확정 ${s.votesInCount}/${s.totalVoteCount}',
                  style: PixelFont.body(fontSize: 11, color: AppColors.mutedForeground)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: AppButton(
                  label: _myVote == null ? '투표하기' : '변경 (${s.nicknameOf(_myVote!)})',
                  dense: true,
                  // 확정 후에는 선택을 바꿀 수 없다(서버도 castVote를 무시함).
                  onPressed: _myVoteConfirmed ? null : () => _openVoteDialog(s),
                ),
              ),
              const SizedBox(width: 6),
              // 후보 선택과 별개로, 이 버튼을 눌러야 서버 집계에 "확정"으로 반영된다.
              // 전원이 확정하면 제한시간을 다 기다리지 않고 곧바로(3초 뒤) 결과로 넘어간다.
              Expanded(
                flex: 2,
                child: AppButton(
                  label: _myVoteConfirmed ? '확정 ✓' : '확정',
                  dense: true,
                  variant: _myVoteConfirmed ? AppButtonVariant.outlined : AppButtonVariant.primary,
                  accentColor: _myVoteConfirmed ? AppColors.success : null,
                  onPressed: _myVote == null || _myVoteConfirmed
                      ? null
                      : () {
                          setState(() => _myVoteConfirmed = true);
                          ref.read(roomProvider.notifier).confirmVote();
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 투표 결과·역전승 여부는 이제 팝업(_showVoteResultDialog/_showResultDialog)이 도맡아
  // 보여주므로, 페이즈 동안 채팅창 아래에는 최소한의 진행 상태 텍스트만 남긴다.
  Widget _resolutionPanel(RoomViewState s) {
    return _panelBox(
      child: Text('결과를 확인하는 중...',
          style: PixelFont.body(fontSize: 12, color: AppColors.foreground)),
    );
  }

  Widget _liarGuessPanel(RoomViewState s) {
    final isMe = s.liarGuessTimeLimitSec != null;
    return _panelBox(
      child: Text(
        isMe
            ? (_submittingGuess ? '제출했습니다! 결과를 기다리는 중...' : '역전 기회! 팝업에서 진짜 제시어를 맞혀보세요.')
            : '라이어가 진짜 제시어를 맞히는 중...',
        style: PixelFont.body(fontSize: 12, color: AppColors.foreground),
      ),
    );
  }

  Widget _inputBar(RoomViewState s) {
    // 대기/종료 페이즈엔 하단 컨텍스트 패널에 컨트롤이 있으니 자유 채팅만 노출.
    final describingMyTurn = s.phase == GamePhase.describing && s.isMyTurn(_myUid);
    // 설명 페이즈에서는 지금 차례인 사람만 입력할 수 있다 — 다른 참가자가 자유 채팅으로
    // 끼어들면 설명이 채팅에 묻히거나 눈치를 주는 용도로 악용될 수 있어서 막는다.
    // 단, currentTurnPlayerId가 비어있는 동안(설명 제출 직후~다음 턴 시작 전, AI 코멘트
    // 생성 대기 중 — room_provider.submitDescription 참고)은 "차례인 사람"이 아무도 없으므로
    // 막을 이유가 없다. 이 조건이 없으면 그 잠깐 사이 전원의 채팅이 막히고, 힌트 문구도
    // "님이 설명 중..."처럼 이름이 빠진 채로 떠서 "가끔 입력이 안 된다"는 문제로 보였다.
    final describingNotMyTurn =
        s.phase == GamePhase.describing && s.currentTurnPlayerId != null && !s.isMyTurn(_myUid);
    final canChat = !describingNotMyTurn;
    final hint = describingMyTurn
        ? '제시어 설명 입력...'
        : (describingNotMyTurn
            ? '${s.currentTurnPlayerId == null ? '' : s.nicknameOf(s.currentTurnPlayerId!)}님이 설명 중...'
            : '메시지 입력...');
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Row(
        children: [
          Expanded(
            // 유령 포커스 상태(_refocusChat 참고)에서는 입력창을 탭해도 이미 hasFocus라
            // 포커스 변화가 없어 스스로 복구되지 않는다 — 탭(pointer down)이 TextField의
            // 포커스 처리보다 먼저 오는 이 지점에서 포커스를 미리 풀어, 어떤 경로로 입력이
            // 죽었든 입력창을 한 번 탭하면 새 포커스 연결로 반드시 살아나게 한다.
            child: Listener(
              onPointerDown: (_) {
                if (kIsWeb && _chatFocusNode.hasFocus) _chatFocusNode.unfocus();
              },
              child: AppTextField(
                controller: _chatController,
                focusNode: _chatFocusNode,
                hintText: hint,
                enabled: canChat,
                onSubmitted: canChat ? (_) => _sendChatOrDescription(s) : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Opacity(
            opacity: canChat ? 1 : 0.4,
            child: HoverTap(
              onTap: canChat ? () => _sendChatOrDescription(s) : null,
              child: PixelBox(
                padding: const EdgeInsets.all(10),
                color: AppColors.primary,
                child: const Icon(Icons.send, size: 18, color: AppColors.primaryForeground),
              ),
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
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: PixelFont.body(fontSize: 12, color: AppColors.mutedForeground)),
          ),
          const SizedBox(width: 10),
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

class _PlayerProfileCard extends StatelessWidget {
  final Widget avatar;
  final String nickname;
  final bool isMe;
  final bool isCurrentTurn;
  final String? statusText;
  final Color? statusColor;

  const _PlayerProfileCard({
    required this.avatar,
    required this.nickname,
    required this.isMe,
    required this.isCurrentTurn,
    required this.statusText,
    this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return PixelBox(
      width: 50,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      color: isCurrentTurn ? AppColors.primary.withValues(alpha: 0.15) : AppColors.card,
      border: Border.all(color: isCurrentTurn ? AppColors.primary : AppColors.border, width: isCurrentTurn ? 2 : 1.5),
      shadowOffset: null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(height: 2),
          Text(
            isMe ? '나' : nickname,
            style: PixelFont.body(fontSize: 9, color: AppColors.foreground, height: 1.0),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (statusText != null)
            Text(
              statusText!,
              style: PixelFont.body(fontSize: 8, height: 1.0, color: statusColor ?? AppColors.mutedForeground),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
        ],
      ),
    );
  }
}
