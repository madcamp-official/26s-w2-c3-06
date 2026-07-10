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
  late final List<Player> _players;
  late final List<ChatMessage> _messages;
  final _categoryController = TextEditingController();
  final _chatController = TextEditingController();
  int _botCount = 1;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _players = List.of(buildMockPlayers(selfIsHost: widget.isHost));
    _messages = List.of(mockRoomChat);
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  void _toggleReady() {
    setState(() => _isReady = !_isReady);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('방 코드 ${widget.roomCode}')),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: '참가자 (${_players.length}명)',
                child: Column(
                  children: _players.map((p) => _PlayerTile(player: p)).toList(),
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'AI 봇 수',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => _changeBotCount(-1),
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
                      onPressed: () => _changeBotCount(1),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: '카테고리',
                child: AppTextField(
                  controller: _categoryController,
                  hintText: '예: 음식, 동물, 영화 ...',
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
                      onPressed: widget.isHost ? _startGame : null,
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
