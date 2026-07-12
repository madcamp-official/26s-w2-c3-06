import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 디자인의 팝업(투표/결과/승패/게스트입장) 공통 스타일 — 크림 배경 + 굵은 앰버 테두리 + 하드 섀도.
/// [barrierDismissible]이 false면 바깥을 눌러도 닫히지 않는다(투표/결과처럼 강제 진행 흐름용).
Future<T?> showPixelDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
  double maxWidth = 460,
  EdgeInsetsGeometry padding = const EdgeInsets.all(28),
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border.fromBorderSide(BorderSide(color: AppColors.border, width: 3)),
              boxShadow: [BoxShadow(color: AppColors.hardShadow, offset: Offset(4, 4), blurRadius: 0)],
            ),
            padding: padding,
            child: builder(dialogContext),
          ),
        ),
      );
    },
  );
}
