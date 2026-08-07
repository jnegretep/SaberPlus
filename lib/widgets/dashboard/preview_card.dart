// lib/widgets/dashboard/preview_card.dart
// Premium preview card with dark mode, animations, and press scale

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/animations/app_animations.dart';

class PreviewCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String imagePath;
  final Color color;
  final VoidCallback? onTap;

  final bool locked;
  final bool completed;

  const PreviewCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.color,
    this.onTap,
    this.locked = false,
    this.completed = false,
  });

  @override
  State<PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<PreviewCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );

    _scale = Tween(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _fade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slide = Tween(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    await _controller.reverse();
    await _controller.forward();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = widget.locked;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final tertiaryTextColor = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    final safeTitle = widget.title.replaceAll('\n', ' ').trim();
    final safeSubtitle = widget.subtitle.replaceAll('\n', ' ').trim();

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          child: Material(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _handleTap,
              child: Stack(
                children: [
                  // ───────── CARD CONTENT ─────────
                  Container(
                    width: 128,
                    height: 138,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: AppColors.shadowSm,
                                blurRadius: 14,
                                offset: const Offset(0, 8),
                              ),
                            ],
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: Image.asset(
                            widget.imagePath,
                            fit: BoxFit.contain,
                            color: isDark ? Colors.white.withOpacity(0.8) : null,
                            colorBlendMode: isDark ? BlendMode.modulate : null,
                            errorBuilder: (_, __, ___) => Icon(
                              widget.icon,
                              size: 40,
                              color: widget.color,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  safeTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: primaryTextColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  safeSubtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: tertiaryTextColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.completed
                                ? "Completado"
                                : isLocked
                                    ? "Bloqueado"
                                    : "Pendiente",
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: _statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ───────── LOCK OVERLAY ─────────
                  if (isLocked)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: true,
                        child: Container(
                          decoration: BoxDecoration(
                            color: surfaceColor.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.lock_rounded,
                              size: 28,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color get _statusColor {
    if (widget.completed) return AppColors.success;
    if (widget.locked) return AppColors.textDisabled;
    return AppColors.warning;
  }
}
