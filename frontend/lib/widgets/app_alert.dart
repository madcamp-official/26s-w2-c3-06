import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/pixel_font.dart';
import 'app_button.dart';
import 'pixel_dialog.dart';

/// 화면 아래에서 잠깐 떴다 사라지는 스낵바 대신, "확인"을 눌러야 닫히는 알림창.
/// "닉네임이 저장되었습니다" 같은 1회성 알림은 화면 밖에서도 잘 보이도록 전부 이걸로 통일한다.
Future<void> showAppAlert(
  BuildContext context,
  String message, {
  String title = '알림',
}) {
  return showPixelDialog<void>(
    context: context,
    maxWidth: 320,
    builder: (dialogContext) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: PixelFont.title(fontSize: 13, color: AppColors.primary)),
          const SizedBox(height: 12),
          Text(message, style: PixelFont.body(fontSize: 13, color: AppColors.foreground)),
          const SizedBox(height: 18),
          AppButton(label: '확인', onPressed: () => Navigator.of(dialogContext).pop()),
        ],
      );
    },
  );
}
