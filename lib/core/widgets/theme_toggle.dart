// lib/core/widgets/theme_toggle.dart
// Premium theme toggle widget for Saber+ Phase 4
// Beautiful segmented control with sun/moon/auto icons

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../animations/app_animations.dart';

class ThemeToggle extends StatelessWidget {
  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onModeChanged;

  const ThemeToggle({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ThemeOption(
            icon: Icons.light_mode_rounded,
            label: 'Claro',
            isSelected: currentMode == ThemeMode.light,
            isDark: isDark,
            onTap: () => onModeChanged(ThemeMode.light),
          ),
          _ThemeOption(
            icon: Icons.dark_mode_rounded,
            label: 'Oscuro',
            isSelected: currentMode == ThemeMode.dark,
            isDark: isDark,
            onTap: () => onModeChanged(ThemeMode.dark),
          ),
          _ThemeOption(
            icon: Icons.brightness_auto_rounded,
            label: 'Auto',
            isSelected: currentMode == ThemeMode.system,
            isDark: isDark,
            onTap: () => onModeChanged(ThemeMode.system),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppAnimations.normal,
      curve: AppAnimations.defaultCurve,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark ? AppColors.primaryLight : AppColors.primary)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? Colors.white
                  : (isDark ? AppColors.darkTextTertiary : AppColors.textTertiary),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppColors.darkTextTertiary : AppColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
