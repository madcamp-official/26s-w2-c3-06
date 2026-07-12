import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 픽셀 게임풍 "하드 섀도" 데코레이션(두꺼운 테두리 + 블러 없는 오프셋 그림자)을 적용한 박스.
/// 버튼/카드/배지/헤더 등 앱 전반에서 반복되던 `BoxDecoration` 패턴을 하나로 통일한다.
/// [shadowOffset]을 null로 주면 그림자 없이 테두리만 있는 박스가 된다.
class PixelBox extends StatelessWidget {
  const PixelBox({
    super.key,
    required this.child,
    this.color = AppColors.card,
    this.border = const Border.fromBorderSide(BorderSide(color: AppColors.border, width: 3)),
    this.shadowOffset = const Offset(4, 4),
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.alignment,
  });

  final Widget child;
  final Color color;
  final Border border;
  final Offset? shadowOffset;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: color,
        border: border,
        boxShadow: shadowOffset == null
            ? null
            : [BoxShadow(color: AppColors.hardShadow, offset: shadowOffset!, blurRadius: 0)],
      ),
      child: child,
    );
  }
}
