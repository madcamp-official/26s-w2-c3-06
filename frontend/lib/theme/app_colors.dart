import 'package:flutter/material.dart';

/// 앱 전체에서 사용하는 공통 색상 팔레트.
class AppColors {
  AppColors._();

  // Figma Make 디자인 토큰(theme.css) 그대로.
  static const background = Color(0xFFFFF8EE);
  static const foreground = Color(0xFF1A0A00);
  static const card = Color(0xFFFFFEF5);
  static const primary = Color(0xFFE85D04);
  static const primaryForeground = Colors.white;
  static const secondary = Color(0xFFF5E8C8);
  static const secondaryForeground = Color(0xFF1A0A00);
  static const muted = Color(0xFFF5E8C8);
  static const mutedForeground = Color(0xFF7A5020);
  static const accent = Color(0xFFFFF3D6);
  static const destructive = Color(0xFFC62828);
  static const border = Color(0xFFC49030);

  /// Primary 버튼 전용 진한 테두리색 (Figma 코드 export 기준).
  static const primaryBorder = Color(0xFFA83200);

  /// 픽셀 게임풍 "하드 섀도"(블러 없는 오프셋 그림자) 색상.
  static const hardShadow = Color(0xFF2A1400);

  /// 알림 배지(친구 요청 수 등) 전용 빨강 (Figma 코드 export 기준).
  static const notificationBadge = Color(0xFFFF4444);

  // 기존 코드 곳곳에서 쓰는 이름들 — 위 토큰에 대응.
  static const surface = Color(0xFFFFFEF5);
  static const textPrimary = Color(0xFF1A0A00);
  static const textSecondary = Color(0xFF7A5020);
  static const error = Color(0xFFC62828);

  /// 성공/승리/준비완료 등 긍정 상태 표시용 (theme.css chart-2).
  static const success = Color(0xFF43A047);

  /// AI가 보낸 메시지(분탕질 코멘트 등)를 구분하기 위한 강조색 (theme.css chart-5).
  static const aiAccent = Color(0xFFF57C00);

  /// 방장 표시 배지 색상.
  static const hostBadge = Color(0xFFE85D04);

  // 방(RoomScreen) PLAYERS 사이드바의 상태 배지 색상 (Figma 코드 export 기준).
  static const waitingBadgeBg = Color(0xFFF5EDDB);
  static const waitingBadgeText = Color(0xFF9A7040);
  static const waitingBadgeBorder = Color(0x449A7040);
  static const readyBadgeBg = Color(0xFFE8F5E9);
  static const readyBadgeText = Color(0xFF2E7D32);
  static const readyBadgeBorder = Color(0x442E7D32);
  static const crownBadgeBg = Color(0xFFFFF3E0);
  static const crownBadgeText = Color(0xFFE65100);
  static const crownBadgeBorder = Color(0x54E65100);
}
