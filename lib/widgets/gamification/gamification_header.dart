// lib/widgets/gamification/gamification_header.dart
// Saber+ — Header de gamificación para el dashboard
//
// Combina la barra de XP y el indicador de racha en una fila compacta.
// Se coloca debajo del DashboardHeader y encima del ProgressCard.
//
// Layout:
// ┌──────────────────────────────────────┬───────────┐
// │  [Nivel 4]  ████░░░░░  450/900 XP    │  🔥 5 días │
// │             450 XP para nivel 5      │  ¡Sigue!   │
// └──────────────────────────────────────┴───────────┘

import 'package:flutter/material.dart';
import 'xp_bar.dart';
import 'streak_indicator.dart';

class GamificationHeader extends StatelessWidget {
  /// Callback cuando se toca la barra de XP (abrir pantalla de logros)
  final VoidCallback? onXpTap;

  /// Callback cuando se toca la racha (abrir info de rachas)
  final VoidCallback? onStreakTap;

  const GamificationHeader({
    super.key,
    this.onXpTap,
    this.onStreakTap,
  });

  @override
Widget build(BuildContext context) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ── XP Bar (ocupa la mayor parte del espacio) ──
      Expanded(
        flex: 3,
        child: XpBar(
          compact: true,
          onTap: onXpTap,
        ),
      ),

      const SizedBox(width: 10),

      // ── Streak Indicator (compacto, a la derecha) ──
      Expanded(
        flex: 2,
        child: StreakIndicator(
          compact: true,
          onTap: onStreakTap,
        ),
      ),
    ],
  );
}
}