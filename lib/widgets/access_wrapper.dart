// lib/widgets/access_wrapper.dart
// Premium paywall gate for Saber+ — Phase 4
// Wraps content to check premium access before showing

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/plan_service.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';
import '../core/animations/app_animations.dart';

class AccessWrapper extends StatelessWidget {
  final String contentType;
  final String contentId;
  final Widget freeContent;
  final Widget premiumContent;
  final bool showUpgradePrompt;

  const AccessWrapper({
    super.key,
    required this.contentType,
    required this.contentId,
    required this.freeContent,
    required this.premiumContent,
    this.showUpgradePrompt = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final planService = context.watch<PlanService>();

    // If user is premium, show premium content directly
    if (planService.isPremium) {
      return premiumContent;
    }

    return FutureBuilder<bool>(
      future: planService.checkContentAccess(contentType, contentId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          );
        }

        final hasAccess = snapshot.data ?? false;

        if (hasAccess) {
          return premiumContent;
        } else {
          return Column(
            children: [
              freeContent,
              if (showUpgradePrompt) _buildUpgradePrompt(context, isDark),
            ],
          );
        }
      },
    );
  }

  Widget _buildUpgradePrompt(BuildContext context, bool isDark) {
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final primaryBg = isDark ? AppColors.primary.withOpacity(0.1) : const Color(0xFFEFF6FF);
    final primaryBorder = isDark ? AppColors.primaryLight.withOpacity(0.3) : const Color(0xFFBFDBFE);
    final textOnBg = isDark ? AppColors.primaryLight : AppColors.primary;

    return PressScale(
      onTap: () => Nav.goUpgrade(context),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: primaryBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primaryBorder),
        ),
        child: Column(
          children: [
            Icon(
              Icons.lock_rounded,
              color: textOnBg,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              'Contenido Premium',
              style: TextStyle(
                color: textOnBg,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Desbloquea este contenido y mucho más con Premium',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Nav.goUpgrade(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: const Text(
                  'VER PLANES PREMIUM',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
