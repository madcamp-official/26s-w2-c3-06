import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'pixel_box.dart';

/// 로비/방 화면 상단바 공통 셸(연한 배경 + 하단 굵은 테두리 + 하드 섀도).
/// 내용(child)만 화면마다 다르게 채워 넣는다.
class PixelTopBar extends StatelessWidget {
  const PixelTopBar({
    super.key,
    required this.child,
    this.height = 54,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return PixelBox(
      color: AppColors.accent,
      border: const Border(bottom: BorderSide(color: AppColors.border, width: 3)),
      shadowOffset: const Offset(0, 3),
      height: height,
      padding: padding,
      child: child,
    );
  }
}
