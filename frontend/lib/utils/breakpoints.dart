import 'package:flutter/widgets.dart';

/// 이 너비 이상이면 데스크탑(웹) 레이아웃, 미만이면 모바일(앱) 레이아웃을 사용한다.
const double kDesktopBreakpoint = 900;

extension ResponsiveContext on BuildContext {
  bool get isDesktop => MediaQuery.sizeOf(this).width >= kDesktopBreakpoint;
}
