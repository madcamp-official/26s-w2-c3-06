import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AvatarOption {
  final String emoji;

  const AvatarOption({required this.emoji});
}

/// 실제 이미지 업로드 대신 사용하는 프로필 사진 프리셋 목록(디자인의 동물 이모지 아이콘 타일).
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

/// 공통 프로필 아바타. 디자인상 원형이 아니라 앰버 테두리의 둥근 사각 "아이콘 타일" 스타일.
class UserAvatar extends StatelessWidget {
  final int avatarIndex;
  final double radius;

  const UserAvatar({super.key, required this.avatarIndex, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    final option = avatarOptions[avatarIndex % avatarOptions.length];
    final size = radius * 2;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accent,
        border: Border.all(color: AppColors.border, width: size > 32 ? 2 : 1.5),
        borderRadius: BorderRadius.circular(size * 0.16),
      ),
      child: Text(option.emoji, style: TextStyle(fontSize: radius)),
    );
  }
}
