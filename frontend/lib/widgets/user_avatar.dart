import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AvatarOption {
  final String emoji;

  const AvatarOption({required this.emoji});
}

/// 실제 프로필 사진이 없을 때 대신 보여주는 기본 아이콘 타일(디자인의 동물 이모지).
const avatarOptions = <AvatarOption>[
  AvatarOption(emoji: '🦊'),
  AvatarOption(emoji: '🐱'),
  AvatarOption(emoji: '🐸'),
  AvatarOption(emoji: '🦋'),
  AvatarOption(emoji: '⭐'),
  AvatarOption(emoji: '🐰'),
  AvatarOption(emoji: '🌈'),
  AvatarOption(emoji: '🍀'),
];

/// 공통 프로필 아바타. 우선순위: [imageBytes](이번 세션 로컬 미리보기) > [imageUrl](서버 저장
/// Firebase Storage 사진) > [avatarIndex] 기반 기본 아이콘 타일. 앰버 테두리의 둥근 사각형 스타일.
class UserAvatar extends StatelessWidget {
  final int avatarIndex;
  final double radius;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final Color? borderColor;

  const UserAvatar({
    super.key,
    required this.avatarIndex,
    this.radius = 18,
    this.imageBytes,
    this.imageUrl,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final borderRadius = BorderRadius.circular(size * 0.16);
    final Widget content;
    if (imageBytes != null) {
      content = Image.memory(imageBytes!, width: size, height: size, fit: BoxFit.cover);
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      content = Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Text(avatarOptions[avatarIndex % avatarOptions.length].emoji, style: TextStyle(fontSize: radius)),
      );
    } else {
      content = Text(avatarOptions[avatarIndex % avatarOptions.length].emoji, style: TextStyle(fontSize: radius));
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
