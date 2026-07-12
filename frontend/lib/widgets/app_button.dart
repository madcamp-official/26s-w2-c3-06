import 'package:flutter/material.dart';
import '../theme/pixel_font.dart';

import '../theme/app_colors.dart';

enum AppButtonVariant { primary, outlined }

/// 공통 버튼. Figma Make 디자인의 "픽셀 게임" 스타일(두꺼운 테두리 + 블러 없는
/// 오프셋 하드 섀도)을 그대로 구현한다. 화면마다 직접 스타일링하지 않도록 통일.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool fullWidth;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final isPrimary = variant == AppButtonVariant.primary;
    final backgroundColor = isPrimary ? AppColors.primary : AppColors.secondary;
    final borderColor = isPrimary ? AppColors.primaryBorder : AppColors.border;
    final textColor = isPrimary ? AppColors.primaryForeground : AppColors.foreground;
    final enabled = onPressed != null;

    final textStyle = PixelFont.body(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: textColor,
    ).copyWith(fontFamilyFallback: const ['Noto Sans KR']);

    final child = icon == null
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
      opacity: enabled ? 1 : 0.5,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor, width: 3),
          boxShadow: enabled
              ? const [BoxShadow(color: AppColors.hardShadow, offset: Offset(2, 2), blurRadius: 0)]
              : null,
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );

    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: button,
      ),
    );
  }
}
