import 'dart:async';

import 'package:flutter/material.dart';

/// [deadline]까지 남은 시간을 1초마다 갱신해 보여준다. 실제 페이즈 전환은 서버가
/// 소유하므로(타이머 만료는 서버가 스스로 판단) 이건 어디까지나 표시용 — deadline은
/// 프론트가 이벤트 수신 시각 + timeLimitSec로 로컬 계산한 추정치다.
class CountdownText extends StatefulWidget {
  final DateTime deadline;
  final TextStyle? style;

  const CountdownText({super.key, required this.deadline, this.style});

  @override
  State<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<CountdownText> {
  Timer? _timer;
  late int _remainingSec;

  @override
  void initState() {
    super.initState();
    _remainingSec = _computeRemaining();
    _startTimer();
  }

  @override
  void didUpdateWidget(CountdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) {
      setState(() => _remainingSec = _computeRemaining());
    }
  }

  int _computeRemaining() {
    final diff = widget.deadline.difference(DateTime.now()).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remainingSec = _computeRemaining());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text('$_remainingSec초', style: widget.style);
  }
}

/// 시계 아이콘 + [CountdownText]를 묶은 작은 뱃지. 각 페이즈 패널에서 공통으로 쓴다.
class TimerBadge extends StatelessWidget {
  final DateTime deadline;

  const TimerBadge({super.key, required this.deadline});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 16, color: color),
        const SizedBox(width: 4),
        CountdownText(
          deadline: deadline,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
