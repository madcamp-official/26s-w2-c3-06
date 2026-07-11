import 'package:flutter/material.dart';

class AvatarOption {
  final Color color;
  final IconData icon;

  const AvatarOption({required this.color, required this.icon});
}

/// 실제 이미지 업로드 대신 사용하는 프로필 사진 프리셋 목록.
const avatarOptions = <AvatarOption>[
  AvatarOption(color: Color(0xFF6C5CE7), icon: Icons.pets),
  AvatarOption(color: Color(0xFF00B894), icon: Icons.emoji_nature),
  AvatarOption(color: Color(0xFFE17055), icon: Icons.local_fire_department),
  AvatarOption(color: Color(0xFF0984E3), icon: Icons.rocket_launch),
  AvatarOption(color: Color(0xFFFDCB6E), icon: Icons.star),
  AvatarOption(color: Color(0xFFE84393), icon: Icons.favorite),
];

/// 공통 프로필 아바타. [avatarIndex]에 해당하는 프리셋 색상/아이콘으로 렌더링한다.
class UserAvatar extends StatelessWidget {
  final int avatarIndex;
  final double radius;

  const UserAvatar({super.key, required this.avatarIndex, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    final option = avatarOptions[avatarIndex % avatarOptions.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: option.color,
      child: Icon(option.icon, color: Colors.white, size: radius),
    );
  }
}
