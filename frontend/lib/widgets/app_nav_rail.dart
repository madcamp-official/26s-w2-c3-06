import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/pixel_font.dart';
import 'hover_tap.dart';
import 'pixel_box.dart';

/// [AppNavRail]에 들어가는 개별 아이콘 항목.
class AppNavRailItem {
  const AppNavRailItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.badgeCount = 0,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final int badgeCount;
  final bool selected;
}

/// 데스크탑(웹) 화면에서 로비/방 상단 헤더의 아이콘들을 대신하는 좌측 고정 내비게이션 바.
/// 모바일에서는 쓰지 않고, 대신 각 화면의 상단 헤더에 아이콘을 그대로 둔다.
class AppNavRail extends StatelessWidget {
  const AppNavRail({super.key, required this.items});

  final List<AppNavRailItem> items;

  @override
  Widget build(BuildContext context) {
    return PixelBox(
      width: 84,
      color: AppColors.accent,
      border: const Border(right: BorderSide(color: AppColors.border, width: 3)),
      shadowOffset: const Offset(3, 0),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          const Text('🤖', style: TextStyle(fontSize: 28)),
          const SizedBox(height: 20),
          for (final item in items) ...[
            _RailIconButton(item: item),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({required this.item});

  final AppNavRailItem item;

  @override
  Widget build(BuildContext context) {
    final enabled = item.onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: HoverTap(
        onTap: item.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                PixelBox(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  color: item.selected ? AppColors.primary : AppColors.secondary,
                  border: Border.all(
                    color: item.selected ? AppColors.primaryBorder : AppColors.border,
                    width: 2,
                  ),
                  shadowOffset: const Offset(2, 2),
                  child: Icon(item.icon, size: 20, color: item.selected ? Colors.white : AppColors.foreground),
                ),
                if (item.badgeCount > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      width: 16,
                      height: 16,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.notificationBadge,
                        border: Border.all(color: AppColors.background, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${item.badgeCount}', style: PixelFont.body(fontSize: 9, color: Colors.white)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(item.label, style: PixelFont.body(fontSize: 9, color: AppColors.mutedForeground)),
          ],
        ),
      ),
    );
  }
}
