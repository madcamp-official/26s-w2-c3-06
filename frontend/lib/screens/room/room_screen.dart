import 'package:flutter/material.dart';

import '../../mock/mock_data.dart';
import '../../models/chat_message.dart';
import '../../models/player.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/responsive_center.dart';
import '../../widgets/section_card.dart';
import '../game/game_screen.dart';

class RoomScreen extends StatefulWidget {
  final String roomCode;
  final bool isHost;

  const RoomScreen({super.key, required this.roomCode, this.isHost = false});

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late List<Player> _humanPlayers;
  late final List<ChatMessage> _messages;
  final _chatController = TextEditingController();
  int _botCount = 1;
  bool _isReady = false;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _humanPlayers = List.of(buildMockPlayers(selfIsHost: widget.isHost));
    _messages = List.of(mockRoomChat);
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  List<Player> get _bots => List.generate(
        _botCount,
        (index) => Player(id: 'bot${index + 1}', nickname: 'AI 봇 ${index + 1}', isBot: true, isReady: true),
      );

  List<Player> get _allPlayers => [..._humanPlayers, ..._bots];

  void _toggleReady() {
    setState(() {
      _isReady = !_isReady;
      final index = _humanPlayers.indexWhere((p) => p.id == 'me');
      if (index != -1) {
        _humanPlayers[index] = _humanPlayers[index].copyWith(isReady: _isReady);
      }
    });
  }

  void _changeBotCount(int delta) {
    setState(() => _botCount = (_botCount + delta).clamp(0, 4));
  }

  void _sendMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(ChatMessage(id: 'local-${_messages.length}', sender: '나', text: text));
      _chatController.clear();
    });
  }

  void _startGame() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GameScreen()),
    );
  }

  bool get _canStartGame => widget.isHost && _allPlayers.every((p) => p.isReady);

  Future<void> _handleLeaveRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('방 나가기'),
          content: const Text('정말 이 방에서 나가시겠어요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('나가기'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('방 코드 ${widget.roomCode}'),
        actions: [
          IconButton(
            onPressed: _handleLeaveRoom,
            icon: const Icon(Icons.logout),
            tooltip: '나가기',
          ),
        ],
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: '참가자 (${_allPlayers.length}명)',
                child: Column(
                  children: _allPlayers.map((p) => _PlayerTile(player: p)).toList(),
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: widget.isHost ? 'AI 봇 수' : 'AI 봇 수 (방장만 설정 가능)',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: widget.isHost ? () => _changeBotCount(-1) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '$_botCount',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: widget.isHost ? () => _changeBotCount(1) : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: widget.isHost ? '카테고리' : '카테고리 (방장만 설정 가능)',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: mockCategories.map((category) {
                    return ChoiceChip(
                      label: Text(category),
                      selected: category == _selectedCategory,
                      onSelected: widget.isHost
                          ? (_) => setState(() => _selectedCategory = category)
                          : null,
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: _isReady ? '준비 완료' : '준비하기',
                      variant: _isReady ? AppButtonVariant.primary : AppButtonVariant.outlined,
                      onPressed: _toggleReady,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppButton(
                      label: '게임 시작',
                      onPressed: _canStartGame ? _startGame : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('채팅', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _messages.length,
                            itemBuilder: (context, index) => ChatBubble(message: _messages[index]),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: AppTextField(
                                controller: _chatController,
                                hintText: '메시지를 입력하세요',
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(onPressed: _sendMessage, icon: const Icon(Icons.send)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  final Player player;

  const _PlayerTile({required this.player});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Icon(player.isBot ? Icons.smart_toy : Icons.person),
      ),
      title: Row(
        children: [
          Text(player.nickname),
          if (player.isHost) ...[
            const SizedBox(width: 6),
            const Icon(Icons.emoji_events, size: 16, color: AppColors.hostBadge),
          ],
        ],
      ),
      trailing: Icon(
        player.isReady ? Icons.check_circle : Icons.radio_button_unchecked,
        color: player.isReady ? AppColors.secondary : Colors.grey,
      ),
    );
  }
}
