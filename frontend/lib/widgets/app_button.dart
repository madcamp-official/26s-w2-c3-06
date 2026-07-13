import 'package:flutter/material.dart';
import '../theme/pixel_font.dart';

import '../theme/app_colors.dart';
import 'pixel_box.dart';

enum AppButtonVariant { primary, outlined }

/// 공통 버튼. Figma Make 디자인의 "픽셀 게임" 스타일(두꺼운 테두리 + 블러 없는
/// 오프셋 하드 섀도)을 그대로 구현한다. 화면마다 직접 스타일링하지 않도록 통일.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool fullWidth;

  /// 좁은 영역(하단바 등)에 쓰는 컴팩트한 크기. 패딩/글자 크기를 줄인다.
  final bool dense;

  /// true면 라벨 대신 스피너를 보여주고 탭을 막는다 — AI 응답을 기다리는 등
  /// 서버 왕복이 오래 걸리는 액션에서 "눌렸고 처리 중"임을 명확히 보여주기 위함.
  final bool loading;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.fullWidth = true,
    this.dense = false,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPrimary = variant == AppButtonVariant.primary;
    final backgroundColor = isPrimary ? AppColors.primary : AppColors.secondary;
    final borderColor = isPrimary ? AppColors.primaryBorder : AppColors.border;
    final textColor = isPrimary ? AppColors.primaryForeground : AppColors.foreground;
    final enabled = onPressed != null && !loading;

    final textStyle = PixelFont.body(
      fontSize: dense ? 12 : 14,
      fontWeight: FontWeight.w400,
      color: textColor,
    ).copyWith(fontFamilyFallback: const ['Noto Sans KR']);

    final spinnerSize = dense ? 14.0 : 16.0;
    final child = loading
        ? SizedBox(
            width: spinnerSize,
            height: spinnerSize,
            child: CircularProgressIndicator(strokeWidth: 2, color: textColor),
          )
        : icon == null
            ? Text(label, textAlign: TextAlign.center, style: textStyle)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: textColor),
                  const SizedBox(width: 8),
                  Text(label, style: textStyle),
                ],
              );

    final button = Opacity(
      opacity: onPressed == null && !loading ? 0.5 : 1,
      child: PixelBox(
        width: fullWidth ? double.infinity : null,
        padding: dense
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        color: backgroundColor,
        border: Border.all(color: borderColor, width: dense ? 2 : 3),
        shadowOffset: onPressed != null ? const Offset(2, 2) : null,
        alignment: Alignment.center,
        child: child,
      ),
    );

    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: button,
      ),
    );
  }
}
