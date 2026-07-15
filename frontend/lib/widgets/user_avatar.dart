import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 공통 프로필 아바타. 우선순위: [imageBytes](이번 세션 로컬 미리보기) > [imageUrl](서버 저장
/// Firebase Storage 사진) > 사진이 없으면 기본 프로필 아이콘(사람 실루엣). 앰버 테두리의
/// 둥근 사각형 스타일. [avatarIndex]는 호환용으로 남겨둔 값(현재 표시에는 사용하지 않음).
class UserAvatar extends StatelessWidget {
  final int avatarIndex;
  final double radius;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final Color? borderColor;

  /// AI 봇 참가자용 — 사진이 없을 때 사람 실루엣 대신 🤖 이모지를 보여준다.
  final bool isBot;

  const UserAvatar({
    super.key,
    required this.avatarIndex,
    this.radius = 18,
    this.imageBytes,
    this.imageUrl,
    this.borderColor,
    this.isBot = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final borderRadius = BorderRadius.circular(size * 0.16);
    final Widget content;
    final placeholder = isBot
        ? Image.asset('images/bot_avatar.png', width: size, height: size, fit: BoxFit.cover)
        : Icon(Icons.person, size: size * 0.6, color: AppColors.mutedForeground);
    if (imageBytes != null) {
      content = Image.memory(imageBytes!, width: size, height: size, fit: BoxFit.cover);
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      content = Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      );
    } else {
      content = placeholder;
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.accent,
        border: Border.all(color: borderColor ?? AppColors.border, width: size > 32 ? 2 : 1.5),
        borderRadius: borderRadius,
      ),
      child: content,
    );
  }
}
