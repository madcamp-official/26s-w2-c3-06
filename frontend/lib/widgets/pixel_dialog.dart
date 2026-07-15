import 'package:flutter/material.dart';

import 'pixel_box.dart';

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
          // 후보 목록이 많거나(투표) 화면이 작은 실기기에서 다이얼로그 내용이 화면 높이를
          // 넘으면 잘려나가지 않고 스크롤되게 한다 — 예전엔 높이 제약이 없어 내용이 넘치면
          // 그대로 "bottom overflowed" 에러가 났다.
          child: SingleChildScrollView(
            child: PixelBox(padding: padding, child: builder(dialogContext)),
          ),
        ),
      );
    },
  );
}
