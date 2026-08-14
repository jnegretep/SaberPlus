// lib/widgets/gamification/streak_indicator.dart
// Saber+ — Indicador de racha de días consecutivos
//
// Muestra una flama animada con el número de días de racha actual.
// La flama "parpadea" sutilmente cuando la racha está activa.
// El color cambia según la longitud de la racha:
//   1-2 días: naranja (warning)
//   3-6 días: naranja-rosa
//   7-29 días: rojo (error)
//   30+ días: púrpura (legendario)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/animations/app_animations.dart';
import '../../providers/gamification_provider.dart';

class StreakIndicator extends StatefulWidget {
  /// Compact mode: muestra solo el icono + número (sin texto "días")
  final bool compact;

  /// Callback cuando el usuario toca el indicador
  final VoidCallback? onTap;

  const StreakIndicator({
    super.key,
    this.compact = false,
    this.onTap,
  });

  @override
  State<StreakIndicator> createState() => _StreakIndicatorState();
}

class _StreakIndicatorState extends State<StreakIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _flickerController;
  late final Animation<double> _flicker;

  @override
  void initState() {
    super.initState();

    // Animación sutil de "parpadeo" de la flama
    _flickerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _flicker = Tween(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _flickerController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _flickerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gamif = context.watch<GamificationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final streak = gamif.currentStreak;
    final isActive = streak > 0;

    // Iniciar/detener animación según si hay racha activa
    if (isActive && !_flickerController.isAnimating) {
      _flickerController.repeat(reverse: true);
    } else if (!isActive && _flickerController.isAnimating) {
      _flickerController.stop();
      _flickerController.value = 1.0;
    }

    final streakColor = _getStreakColor(streak);
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    return PressScale(
      onTap: widget.onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 10 : 14,
          vertical: widget.compact ? 8 : 12,
        ),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(widget.compact ? 12 : 14),
          border: Border.all(
            color: isActive
                ? streakColor.withOpacity(0.4)
                : (isDark ? AppColors.darkBorder : AppColors.border),
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: streakColor.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: AppColors.shadowSm,
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Flama animada ──
            ScaleTransition(
              scale: isActive ? _flicker : const AlwaysStoppedAnimation(1.0),
              child: _buildFlameIcon(streak, isActive, streakColor),
            ),
            SizedBox(width: widget.compact ? 6 : 8),

            // ── Número de días + texto ──
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$streak',
                      style: TextStyle(
                        fontSize: widget.compact ? 18 : 22,
                        fontWeight: FontWeight.w800,
                        color: isActive ? streakColor : textTertiary,
                        height: 1.0,
                      ),
                    ),
                    SizedBox(width: widget.compact ? 2 : 3),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        widget.compact ? '' : 'días',
                        style: TextStyle(
                          fontSize: widget.compact ? 10 : 11,
                          fontWeight: FontWeight.w600,
                          color: isActive ? streakColor : textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!widget.compact) ...[
                  const SizedBox(height: 1),
                  Text(
                    isActive ? '¡Sigue así!' : 'Sin racha',
                    style: TextStyle(
                      fontSize: 9,
                      color: textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Construye el icono de flama con efecto de brillo cuando está activa.
  Widget _buildFlameIcon(int streak, bool isActive, Color color) {
    if (!isActive) {
      // Flama gris/apagada cuando no hay racha
      return Icon(
        Icons.local_fire_department_outlined,
        size: widget.compact ? 22 : 28,
        color: AppColors.textDisabled,
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow de fondo (solo si la racha es alta)
        if (streak >= 7)
          Container(
            width: widget.compact ? 28 : 36,
            height: widget.compact ? 28 : 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.2),
            ),
          ),
        // Flama principal
        Icon(
          Icons.local_fire_department_rounded,
          size: widget.compact ? 22 : 28,
          color: color,
          shadows: [
            Shadow(
              color: color.withOpacity(0.5),
              blurRadius: 6,
            ),
          ],
        ),
      ],
    );
  }

  /// Retorna el color de la flama según la longitud de la racha.
  Color _getStreakColor(int streak) {
    if (streak <= 0) return AppColors.textDisabled;
    if (streak <= 2) return AppColors.warning;       // naranja
    if (streak <= 6) return AppColors.accentDark;     // naranja-rosa
    if (streak <= 29) return AppColors.error;         // rojo
    return AppColors.purple;                          // púrpura legendario
  }
}
