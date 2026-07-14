import 'package:flutter/material.dart';

/// 탭 가능한 영역을 감싸는 공통 위젯. GestureDetector에 더해, 웹에서 마우스를
/// 올리면 손가락(클릭) 커서로 바뀌도록 MouseRegion을 함께 적용한다.
/// [onTap]이 null이면(비활성) 기본 커서를 유지한다. AppButton과 동일한 커서 규칙.
class HoverTap extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const HoverTap({super.key, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: child),
    );
  }
}
