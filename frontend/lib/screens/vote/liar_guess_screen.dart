import 'package:flutter/material.dart';

import '../../mock/mock_data.dart';
import '../../models/game_result.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/responsive_center.dart';
import '../../widgets/section_card.dart';
import '../result/result_screen.dart';

/// 투표로 라이어가 지목되었을 때, 진짜 제시어를 맞히면 역전승할 수 있는 마지막 기회 화면.
class LiarGuessScreen extends StatefulWidget {
  const LiarGuessScreen({super.key});

  @override
  State<LiarGuessScreen> createState() => _LiarGuessScreenState();
}

class _LiarGuessScreenState extends State<LiarGuessScreen> {
  final _guessController = TextEditingController();

  @override
  void dispose() {
    _guessController.dispose();
    super.dispose();
  }

  void _submitGuess() {
    final guess = _guessController.text.trim();
    if (guess.isEmpty) return;

    final correct = guess == mockGameResult.realWord;
    final result = GameResult(
      category: mockGameResult.category,
      liarNickname: mockGameResult.liarNickname,
      realWord: mockGameResult.realWord,
      fakeWord: mockGameResult.fakeWord,
      citizensWin: !correct,
      summary: correct
          ? '라이어 ${mockGameResult.liarNickname}님이 진짜 제시어를 맞혀 역전승했습니다!'
          : '라이어 ${mockGameResult.liarNickname}님이 진짜 제시어를 맞히지 못했습니다.',
      liarGuess: guess,
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('라이어의 마지막 기회')),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: '투표로 라이어가 지목되었습니다',
                child: Text(
                  '카테고리 "${mockGameResult.category}"의 진짜 제시어를 맞히면 라이어 팀이 역전승합니다.',
                ),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _guessController,
                label: '진짜 제시어',
                hintText: '제시어를 입력하세요',
                onSubmitted: (_) => _submitGuess(),
              ),
              const SizedBox(height: 16),
              AppButton(label: '제출', onPressed: _submitGuess),
            ],
          ),
        ),
      ),
    );
  }
}
