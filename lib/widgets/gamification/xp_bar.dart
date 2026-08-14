// lib/widgets/gamification/xp_bar.dart
// Saber+ — Barra de XP con nivel y progreso al siguiente nivel
//
// Muestra:
// - Badge circular con el nivel actual (animado al subir de nivel)
// - Barra de progreso lineal con gradiente
// - Texto "450 / 900 XP" o "450 XP para nivel 4"
//
// Se actualiza automáticamente cuando el GamificationProvider cambia.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/animations/app_animations.dart';
import '../../providers/gamification_provider.dart';

class XpBar extends StatefulWidget {
  /// Compact mode: muestra solo el badge + barra (sin texto adicional)
  /// Útil para espacios reducidos como el header del dashboard.
  final bool compact;

  /// Callback cuando el usuario toca la barra (para abrir pantalla de logros)
  final VoidCallback? onTap;

  const XpBar({
    super.key,
    this.compact = false,
    this.onTap,
  });

  @override
  State<XpBar> createState() => _XpBarState();
}

class _XpBarState extends State<XpBar> with TickerProviderStateMixin {
  late final AnimationController _levelPulseController;
  late final Animation<double> _levelPulse;
  int _lastLevel = 1;

  @override
  void initState() {
    super.initState();

    // Controlador para la animación de "pulse" al subir de nivel
    _levelPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _levelPulse = Tween(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(
        parent: _levelPulseController,
        curve: Curves.elasticOut,
      ),
    );
  }

  @override
  void dispose() {
    _levelPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gamif = context.watch<GamificationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Detectar subida de nivel para animar
    final currentLevel = gamif.level;
    if (currentLevel > _lastLevel) {
      _lastLevel = currentLevel;
      _levelPulseController.forward(from: 0.0);
    } else {
      _lastLevel = currentLevel;
    }

    final totalXp = gamif.totalXp;
    final xpToNext = gamif.xpToNextLevel;
    final progressPct = gamif.levelProgressPct / 100.0; // 0.0 - 1.0

    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    return PressScale(
      onTap: widget.onTap,
      child: Container(
        padding: EdgeInsets.all(widget.compact ? 12 : 16),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(widget.compact ? 14 : 16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowSm,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Badge circular de nivel (con animación de pulse) ──
            ScaleTransition(
              scale: _levelPulse,
              child: _buildLevelBadge(currentLevel, isDark),
            ),
            SizedBox(width: widget.compact ? 10 : 14),

            // ── Barra de progreso + texto ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Fila superior: "Nivel X" + "XP total"
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Nivel $currentLevel',
                        style: TextStyle(
                          fontSize: widget.compact ? 13 : 15,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      Text(
                        '$totalXp XP',
                        style: TextStyle(
                          fontSize: widget.compact ? 11 : 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: widget.compact ? 6 : 8),

                  // Barra de progreso
                  ClipRRect(
                    borderRadius: BorderRadius.circular(widget.compact ? 4 : 6),
                    child: SizedBox(
                      height: widget.compact ? 6 : 8,
                      child: Stack(
                        children: [
                          // Fondo de la barra
                          Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.darkSurfaceVariant
                                  : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(
                                  widget.compact ? 4 : 6),
                            ),
                          ),
                          // Progreso con gradiente
                          FractionallySizedBox(
                            widthFactor: progressPct.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AppColors.primary,
                                    AppColors.primaryLight,
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(
                                    widget.compact ? 4 : 6),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        AppColors.primary.withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: widget.compact ? 3 : 4),

                  // Texto inferior: "X XP para nivel Y"
                  Text(
                    xpToNext > 0
                        ? '$xpToNext XP para nivel ${currentLevel + 1}'
                        : '¡Nivel máximo alcanzado!',
                    style: TextStyle(
                      fontSize: widget.compact ? 9 : 10,
                      color: textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Construye el badge circular del nivel.
  /// Usa un gradiente y el número del nivel en el centro.
  Widget _buildLevelBadge(int level, bool isDark) {
    return Container(
      width: widget.compact ? 40 : 48,
      height: widget.compact ? 40 : 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.textOnPrimary.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Icono de estrella de fondo (sutil)
          Icon(
            Icons.star_rounded,
            color: AppColors.textOnPrimary.withOpacity(0.15),
            size: widget.compact ? 24 : 28,
          ),
          // Número del nivel
          Text(
            '$level',
            style: TextStyle(
              fontSize: widget.compact ? 16 : 19,
              fontWeight: FontWeight.w800,
              color: AppColors.textOnPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
