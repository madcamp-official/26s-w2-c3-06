import 'package:flutter/material.dart';

/// 앱 전체에서 사용하는 공통 색상 팔레트.
class AppColors {
  AppColors._();

  static const primary = Color(0xFF6C5CE7);
  static const primaryDark = Color(0xFF4834D4);
  static const secondary = Color(0xFF00B894);
  static const background = Color(0xFFF5F6FA);
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF2D3436);
  static const textSecondary = Color(0xFF636E72);
  static const error = Color(0xFFD63031);

  /// AI가 보낸 메시지(분탕질 코멘트 등)를 구분하기 위한 강조색.
  static const aiAccent = Color(0xFFE17055);

  /// 방장 표시 배지 색상.
  static const hostBadge = Color(0xFFFDCB6E);
}
