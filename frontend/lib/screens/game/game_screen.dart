import 'package:flutter/material.dart';

import '../../mock/mock_data.dart';
import '../../models/chat_message.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/responsive_center.dart';
import '../result/result_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const _currentPhase = '설명 페이즈';
  static const _currentTurnPlayer = '방장곰';

  final _descriptionController = TextEditingController();
  late final List<ChatMessage> _messages;

  @override
  void initState() {
    super.initState();
    _messages = List.of(mockGameChat);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _submitDescription() {
    final text = _descriptionController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(ChatMessage(id: 'local-${_messages.length}', sender: '나', text: text));
      _descriptionController.clear();
    });
  }

  void _goToVotePhase() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ResultScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('게임 진행 중'),
            Text(_currentPhase, style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.person_pin_circle_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '현재 턴: $_currentTurnPlayer',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _goToVotePhase,
                  icon: const Icon(Icons.how_to_vote_outlined),
                  label: const Text('투표 페이즈로 이동 (임시)'),
                ),
              ),
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
                      controller: _descriptionController,
                      hintText: '제시어에 대한 설명을 입력하세요',
                      onSubmitted: (_) => _submitDescription(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppButton(label: '제출', fullWidth: false, onPressed: _submitDescription),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
