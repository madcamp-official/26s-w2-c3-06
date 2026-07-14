import 'package:flutter/material.dart';

/// 앱 전체에서 쓰는 픽셀 게임 컨셉 폰트(NeoDGM, 번들 자산). 한글 도트 폰트라
/// Google Fonts(DotGothic16/Press Start 2P)와 달리 네트워크 없이도 완전한 한글을 지원한다.
class PixelFont {
  PixelFont._();

  static const familyName = 'NeoDGM';
  static const codeFamilyName = 'NeoDGM Code';

  /// 본문/버튼/라벨 등 일반 텍스트용.
  static TextStyle body({
    double? fontSize,
    Color? color,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: familyName,
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// 큰 타이틀/브랜딩 텍스트용(기존 Press Start 2P 자리를 대체) — 같은 폰트를 쓰되
  /// 호출부에서 의도를 구분할 수 있도록 별도 이름으로 둔다.
  static TextStyle title({
    double? fontSize,
    Color? color,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: familyName,
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  /// 타이머/방 코드 등 자릿수가 고정된 숫자 표시용(고정폭 코드 변형 폰트).
  static TextStyle code({
    double? fontSize,
    Color? color,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: codeFamilyName,
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}
