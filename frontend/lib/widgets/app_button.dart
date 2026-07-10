import 'package:flutter/material.dart';

enum AppButtonVariant { primary, outlined }

/// 공통 버튼. 화면마다 ElevatedButton/OutlinedButton을 직접 스타일링하지 않도록 통일한다.
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
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          );

    final button = variant == AppButtonVariant.primary
        ? ElevatedButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
