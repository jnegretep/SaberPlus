// lib/core/animations/shimmer_loading.dart
// Premium shimmer loading states for dashboard and list screens
// Provides skeleton layouts that mimic real content structure

import 'package:flutter/material.dart';
import 'app_animations.dart';
import '../theme/app_colors.dart';

class DashboardShimmer extends StatelessWidget {
  const DashboardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          // Header shimmer
          _HeaderShimmer(),
          SizedBox(height: 24),
          // Progress card shimmer
          _ProgressCardShimmer(),
          SizedBox(height: 24),
          // Section shimmer (Simulacros)
          _SectionShimmer(),
          SizedBox(height: 28),
          // Section shimmer (Cursos)
          _SectionShimmer(),
          SizedBox(height: 28),
          // Section shimmer (Retos)
          _SectionShimmer(),
        ],
      ),
    );
  }
}

class _HeaderShimmer extends StatelessWidget {
  const _HeaderShimmer();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Avatar
        ShimmerBox(
          width: 52,
          height: 52,
          borderRadius: BorderRadius.circular(26),
        ),
        const SizedBox(width: 14),
        // Greeting text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              ShimmerBox(width: 160, height: 20),
              SizedBox(height: 8),
              ShimmerBox(width: 100, height: 14),
            ],
          ),
        ),
        // Notification bell
        ShimmerBox(
          width: 40,
          height: 40,
          borderRadius: BorderRadius.circular(12),
        ),
      ],
    );
  }
}

class _ProgressCardShimmer extends StatelessWidget {
  const _ProgressCardShimmer();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final cleanColor = isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceClean;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerBox(width: 140, height: 16),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cleanColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                // Score circle
                ShimmerBox(
                  width: 85,
                  height: 85,
                  borderRadius: BorderRadius.circular(42.5),
                ),
                const SizedBox(width: 20),
                // Area bars
                Expanded(
                  child: Column(
                    children: const [
                      ShimmerBox(height: 12),
                      SizedBox(height: 8),
                      ShimmerBox(height: 8),
                      SizedBox(height: 14),
                      ShimmerBox(height: 12),
                      SizedBox(height: 8),
                      ShimmerBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Last simulacro row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cleanColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                ShimmerBox(
                  width: 34,
                  height: 34,
                  borderRadius: BorderRadius.circular(17),
                ),
                const SizedBox(width: 12),
                const Expanded(child: ShimmerBox(width: 120, height: 14)),
                const ShimmerBox(width: 60, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionShimmer extends StatelessWidget {
  const _SectionShimmer();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const ShimmerBox(width: 100, height: 20),
            const Spacer(),
            ShimmerBox(
              width: 70,
              height: 28,
              borderRadius: BorderRadius.circular(14),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Horizontal card list
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, __) => const _CardShimmer(),
          ),
        ),
      ],
    );
  }
}

class _CardShimmer extends StatelessWidget {
  const _CardShimmer();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;

    return Container(
      width: 128,
      height: 138,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: const [
          ShimmerBox(
            width: 64,
            height: 64,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          SizedBox(height: 8),
          ShimmerBox(height: 12),
          SizedBox(height: 6),
          ShimmerBox(width: 60, height: 10),
        ],
      ),
    );
  }
}

// ── List Shimmer (for course_list, quiz_list, challenge_list) ──
class ListShimmer extends StatelessWidget {
  final int itemCount;
  final double itemHeight;

  const ListShimmer({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 80,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
        return Container(
          height: itemHeight,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              ShimmerBox(
                width: 48,
                height: 48,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    ShimmerBox(height: 16),
                    SizedBox(height: 8),
                    ShimmerBox(width: 120, height: 12),
                  ],
                ),
              ),
              ShimmerBox(
                width: 24,
                height: 24,
                borderRadius: BorderRadius.circular(12),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Profile Shimmer ──
class ProfileShimmer extends StatelessWidget {
  const ProfileShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: surfaceColor,
            ),
            child: Row(
              children: [
                ShimmerBox(
                  width: 64,
                  height: 64,
                  borderRadius: BorderRadius.circular(32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      ShimmerBox(width: 140, height: 18),
                      SizedBox(height: 8),
                      ShimmerBox(width: 100, height: 14),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Info sections
          for (int i = 0; i < 3; i++) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: surfaceColor,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ShimmerBox(width: 120, height: 16),
                  SizedBox(height: 16),
                  ShimmerBox(height: 48),
                  SizedBox(height: 12),
                  ShimmerBox(height: 48),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
