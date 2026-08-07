// lib/widgets/dashboard/dashboard_header.dart
// Premium dashboard header with dark mode support and animated notification badge

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../providers/notification_provider.dart';
import '../../screens/notifications_screen.dart';
import '../../core/theme/app_colors.dart';
import '../../core/animations/app_animations.dart';

class DashboardHeader extends StatelessWidget {
  final String userName;
  final String? avatarUrl;

  const DashboardHeader({
    super.key,
    required this.userName,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final notifications = context.watch<NotificationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.primaryLight : AppColors.primary;

    return Row(
      children: [
        // ── Avatar with premium ring ──
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: primaryColor.withOpacity(0.3),
              width: 2.5,
            ),
          ),
          child: CircleAvatar(
            radius: 26,
            backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
                ? CachedNetworkImageProvider(avatarUrl!)
                : const AssetImage('assets/avatars/default.png')
                    as ImageProvider,
          ),
        ),
        const SizedBox(width: 14),
        // ── Greeting ──
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hola, $userName',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.textSecondary,
                ),
              ),
              Text(
                '¡Sigue aprendiendo!',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        // ── Notification bell with animated badge ──
        PressScale(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationsScreen(),
              ),
            );
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  notifications.unreadCount > 0
                      ? Icons.notifications_rounded
                      : Icons.notifications_none_rounded,
                  color: primaryColor,
                  size: 22,
                ),
                if (notifications.unreadCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: _AnimatedBadge(count: notifications.unreadCount),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Animated notification badge that pulses
class _AnimatedBadge extends StatefulWidget {
  final int count;
  const _AnimatedBadge({required this.count});

  @override
  State<_AnimatedBadge> createState() => _AnimatedBadgeState();
}

class _AnimatedBadgeState extends State<_AnimatedBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
      lowerBound: 0.85,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulse,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.error.withOpacity(0.4),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          '${widget.count}',
          style: const TextStyle(
            color: AppColors.textOnPrimary,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
