// lib/core/widgets/empty_state.dart
// Premium empty state widget for Saber+
// Beautiful illustrations + clear CTA for when lists are empty

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../animations/app_animations.dart';

class PremiumEmptyState extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final Color? accentColor;

  const PremiumEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.ctaLabel,
    this.onCta,
    this.accentColor,
  });

  @override
  State<PremiumEmptyState> createState() => _PremiumEmptyStateState();
}

class _PremiumEmptyStateState extends State<PremiumEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeScale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.slow,
    );
    _fadeScale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? AppColors.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScaleTransition(
      scale: _fadeScale,
      child: FadeTransition(
        opacity: _controller,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon with soft background
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: accent.withOpacity(isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  widget.icon,
                  size: 40,
                  color: accent.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 20),
              // Title
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              // Subtitle
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
                ),
              ),
              // CTA Button
              if (widget.ctaLabel != null && widget.onCta != null) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: widget.onCta,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                  child: Text(widget.ctaLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
