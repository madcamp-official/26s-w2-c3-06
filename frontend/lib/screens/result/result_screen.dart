import 'package:flutter/material.dart';

import '../../mock/mock_data.dart';
import '../../models/game_result.dart';
import '../../widgets/app_button.dart';
import '../../widgets/responsive_center.dart';
import '../../widgets/section_card.dart';
import '../lobby/lobby_screen.dart';

class ResultScreen extends StatelessWidget {
  final GameResult? result;

  const ResultScreen({super.key, this.result});

  void _handleRestart(BuildContext context) {
    // Game/Vote/LiarGuess/Result 화면을 모두 걷어내고 대기 중이던 RoomScreen으로 되돌아간다.
    Navigator.of(context).popUntil((route) => route.settings.name == 'room');
  }

  void _handleBackToLobby(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LobbyScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = this.result ?? mockGameResult;
    return Scaffold(
      appBar: AppBar(title: const Text('결과')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ResponsiveCenter(
            maxWidth: 520,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: result.citizensWin
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(result.citizensWin ? Icons.groups : Icons.theater_comedy, size: 40),
                        const SizedBox(height: 8),
                        Text(
                          result.citizensWin ? '시민 팀 승리!' : '라이어 승리!',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(result.summary, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: '라이어 공개',
                  child: Row(
                    children: [
                      const Icon(Icons.person_search),
                      const SizedBox(width: 8),
                      Text(result.liarNickname, style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: '카테고리: ${result.category}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WordRow(label: '진짜 제시어', word: result.realWord),
                      const SizedBox(height: 8),
                      _WordRow(label: '가짜 제시어 (라이어)', word: result.fakeWord),
                    ],
                  ),
                ),
                if (result.liarGuess != null) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    title: '라이어의 역전승 시도',
                    child: Row(
                      children: [
                        Icon(
                          result.citizensWin ? Icons.cancel_outlined : Icons.check_circle_outline,
                          color: result.citizensWin
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${result.liarNickname}님이 제출한 답: ${result.liarGuess}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                AppButton(label: '다시하기', onPressed: () => _handleRestart(context)),
                const SizedBox(height: 12),
                AppButton(
                  label: '로비로 돌아가기',
                  variant: AppButtonVariant.outlined,
                  onPressed: () => _handleBackToLobby(context),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WordRow extends StatelessWidget {
  final String label;
  final String word;

  const _WordRow({required this.label, required this.word});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ', style: Theme.of(context).textTheme.bodyMedium),
        Text(
          word,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
