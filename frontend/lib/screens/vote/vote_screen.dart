import 'package:flutter/material.dart';

import '../../mock/mock_data.dart';
import '../../models/game_result.dart';
import '../../widgets/app_button.dart';
import '../../widgets/responsive_center.dart';
import '../../widgets/section_card.dart';
import '../result/result_screen.dart';
import 'liar_guess_screen.dart';

/// 투표 페이즈. 라이어로 의심되는 플레이어를 지목하고 투표 결과를 확인한다.
class VoteScreen extends StatefulWidget {
  const VoteScreen({super.key});

  @override
  State<VoteScreen> createState() => _VoteScreenState();
}

class _VoteScreenState extends State<VoteScreen> {
  String? _selectedNickname;
  bool _isRevealed = false;

  void _submitVote() {
    if (_selectedNickname == null) return;
    setState(() => _isRevealed = true);
  }

  void _confirmResult() {
    final votedNickname = _selectedNickname!;
    final liarCaught = votedNickname == mockGameResult.liarNickname;

    if (liarCaught) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LiarGuessScreen()),
      );
      return;
    }

    final result = GameResult(
      category: mockGameResult.category,
      liarNickname: mockGameResult.liarNickname,
      realWord: mockGameResult.realWord,
      fakeWord: mockGameResult.fakeWord,
      citizensWin: false,
      summary: '$votedNickname님이 라이어로 지목되었지만 실제 라이어가 아니었습니다.',
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('투표 페이즈')),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: '라이어로 의심되는 플레이어를 선택하세요',
                child: Column(
                  children: mockVoteCandidates
                      .map(
                        (nickname) => RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: Text(nickname),
                          value: nickname,
                          groupValue: _selectedNickname,
                          onChanged: _isRevealed
                              ? null
                              : (value) => setState(() => _selectedNickname = value),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              if (!_isRevealed)
                AppButton(
                  label: '투표하기',
                  onPressed: _selectedNickname == null ? null : _submitVote,
                )
              else ...[
                SectionCard(
                  child: Row(
                    children: [
                      const Icon(Icons.campaign_outlined),
                      const SizedBox(width: 8),
                      Expanded(child: Text('$_selectedNickname님이 최다 득표로 지목되었습니다.')),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppButton(label: '결과 확인', onPressed: _confirmResult),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
