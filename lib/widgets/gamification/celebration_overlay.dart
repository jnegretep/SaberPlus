// lib/widgets/gamification/celebration_overlay.dart
// Saber+ — Overlay de celebración con confetti
//
// Muestra un diálogo modal con confetti animado para celebrar:
// - Subida de nivel
// - Badge desbloqueado
// - Puntaje alto en simulacro
// - Racha alcanzada
//
// Uso:
// ```dart
// CelebrationOverlay.show(
//   context,
//   type: CelebrationType.levelUp,
//   level: 5,
//   newBadges: [badge1, badge2],
//   xpEarned: 150,
// );
// ```

import 'package:flutter/material.dart' hide Badge;
import 'package:confetti/confetti.dart';
import '../../core/theme/app_colors.dart';
import '../../models/gamification_state.dart';

/// Tipo de celebración que determina el icono, título y mensaje.
enum CelebrationType {
  levelUp,           // "¡Subiste al nivel 5!"
  badgeUnlocked,     // "¡Nuevo logro desbloqueado!"
  simulacroComplete, // "¡Simulacro completado!"
  streakMilestone,   // "¡Racha de 7 días!"
  highScore,         // "¡Excelente puntaje!"
}

/// Overlay de celebración con confetti.
///
/// Se muestra como un diálogo modal no cancelable hasta que el usuario
/// toca "¡Genial!". Incluye:
/// - Confetti animado desde arriba
/// - Icono grande animado (aparece con bounce)
/// - Título y mensaje motivacional
/// - Lista de badges desbloqueados (si los hay)
/// - XP ganada
class CelebrationOverlay {
  /// Muestra el overlay de celebración.
  ///
  /// Parámetros:
  /// - [type]: tipo de celebración (determina icono y título)
  /// - [level]: nuevo nivel (solo para levelUp)
  /// - [newBadges]: lista de badges desbloqueados (opcional)
  /// - [xpEarned]: XP ganada en esta acción (opcional)
  /// - [streakDays]: días de racha (solo para streakMilestone)
  /// - [score]: puntaje obtenido (solo para highScore)
  static Future<void> show(
    BuildContext context, {
    required CelebrationType type,
    int? level,
    List<Badge>? newBadges,
    int? xpEarned,
    int? streakDays,
    int? score,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CelebrationDialog(
        type: type,
        level: level,
        newBadges: newBadges,
        xpEarned: xpEarned,
        streakDays: streakDays,
        score: score,
      ),
    );
  }
}

class _CelebrationDialog extends StatefulWidget {
  final CelebrationType type;
  final int? level;
  final List<Badge>? newBadges;
  final int? xpEarned;
  final int? streakDays;
  final int? score;

  const _CelebrationDialog({
    required this.type,
    this.level,
    this.newBadges,
    this.xpEarned,
    this.streakDays,
    this.score,
  });

  @override
  State<_CelebrationDialog> createState() => _CelebrationDialogState();
}

class _CelebrationDialogState extends State<_CelebrationDialog>
    with TickerProviderStateMixin {
  late final ConfettiController _confettiController;
  late final AnimationController _entranceController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Controlador de confetti
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );

    // Animación de entrada (icono aparece con bounce)
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.elasticOut,
      ),
    );
    _fadeAnimation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.easeIn,
      ),
    );

    // Iniciar animaciones
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entranceController.forward();
      _confettiController.play();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config = _getCelebrationConfig();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Confetti de fondo ──
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              maxBlastForce: 25,
              minBlastForce: 8,
              emissionFrequency: 0.05,
              numberOfParticles: 30,
              gravity: 0.3,
              shouldLoop: false,
              colors: config.confettiColors,
              minimumSize: const Size(8, 8),
              maximumSize: const Size(14, 14),
              particleDrag: 0.05,
              canvas: MediaQuery.of(context).size,
            ),
          ),

          // ── Contenido del diálogo ──
          FadeTransition(
            opacity: _fadeAnimation,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.surface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: config.primaryColor.withOpacity(0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Icono principal animado ──
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: _buildMainIcon(config, isDark),
                  ),
                  const SizedBox(height: 20),

                  // ── Título ──
                  Text(
                    config.title,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: config.primaryColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // ── Mensaje ──
                  Text(
                    config.message,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.textTertiary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // ── XP ganada (si aplica) ──
                  if (widget.xpEarned != null && widget.xpEarned! > 0) ...[
                    _buildXpBanner(),
                    const SizedBox(height: 16),
                  ],

                  // ── Badges desbloqueados (si los hay) ──
                  if (widget.newBadges != null && widget.newBadges!.isNotEmpty) ...[
                    _buildBadgesList(isDark),
                    const SizedBox(height: 16),
                  ],

                  // ── Botón cerrar ──
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: config.primaryColor,
                        foregroundColor: AppColors.textOnPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '¡Genial!',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Construye el icono principal con glow de fondo.
  Widget _buildMainIcon(_CelebrationConfig config, bool isDark) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Glow de fondo
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: config.primaryColor.withOpacity(0.15),
          ),
        ),
        // Glow interior
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: config.primaryColor.withOpacity(0.25),
          ),
        ),
        // Icono
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                config.primaryColor,
                config.primaryColor.withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: config.primaryColor.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            config.icon,
            color: AppColors.textOnPrimary,
            size: 32,
          ),
        ),
      ],
    );
  }

  /// Banner de XP ganada.
  Widget _buildXpBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.accent, AppColors.warning],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.bolt_rounded,
            color: AppColors.textOnPrimary,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            '+${widget.xpEarned} XP',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textOnPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Lista horizontal de badges desbloqueados.
  Widget _buildBadgesList(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.newBadges!.length == 1
              ? '¡Nuevo logro desbloqueado!'
              : '¡${widget.newBadges!.length} nuevos logros desbloqueados!',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.newBadges!.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final badge = widget.newBadges![index];
              return _buildBadgeChip(badge, isDark);
            },
          ),
        ),
      ],
    );
  }

  /// Chip individual de badge desbloqueado.
  Widget _buildBadgeChip(Badge badge, bool isDark) {
    final color = _parseColor(badge.color);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getBadgeIcon(badge.icon),
            color: color,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            badge.name,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (badge.xpReward > 0)
            Text(
              '+${badge.xpReward} XP',
              style: TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  /// Configuración según el tipo de celebración.
  _CelebrationConfig _getCelebrationConfig() {
    switch (widget.type) {
      case CelebrationType.levelUp:
        return _CelebrationConfig(
          title: '¡Subiste al nivel ${widget.level}!',
          message: '¡Sigue así! Tu esfuerzo te está llevando lejos.',
          icon: Icons.trending_up_rounded,
          primaryColor: AppColors.primary,
          confettiColors: const [
            AppColors.primary,
            AppColors.primaryLight,
            AppColors.accent,
            AppColors.success,
          ],
        );

      case CelebrationType.badgeUnlocked:
        return _CelebrationConfig(
          title: '¡Nuevo logro!',
          message: 'Has desbloqueado un nuevo logro. ¡Sigue coleccionando!',
          icon: Icons.emoji_events_rounded,
          primaryColor: AppColors.warning,
          confettiColors: const [
            AppColors.warning,
            AppColors.accent,
            AppColors.gold,
            AppColors.success,
          ],
        );

      case CelebrationType.simulacroComplete:
        return _CelebrationConfig(
          title: '¡Simulacro completado!',
          message: 'Has terminado un simulacro ICFES. ¡Buen trabajo!',
          icon: Icons.assignment_turned_in_rounded,
          primaryColor: AppColors.success,
          confettiColors: const [
            AppColors.success,
            AppColors.successDark,
            AppColors.accent,
            AppColors.primary,
          ],
        );

      case CelebrationType.streakMilestone:
        return _CelebrationConfig(
          title: '¡Racha de ${widget.streakDays} días!',
          message: '¡Eres imparable! Sigue practicando cada día.',
          icon: Icons.local_fire_department_rounded,
          primaryColor: AppColors.error,
          confettiColors: const [
            AppColors.error,
            AppColors.warning,
            AppColors.accent,
            AppColors.purple,
          ],
        );

      case CelebrationType.highScore:
        return _CelebrationConfig(
          title: '¡Excelente puntaje!',
          message: 'Obtuviste ${widget.score} puntos en tu simulacro. ¡Increíble!',
          icon: Icons.star_rounded,
          primaryColor: AppColors.accent,
          confettiColors: const [
            AppColors.gold,
            AppColors.accent,
            AppColors.warning,
            AppColors.success,
          ],
        );
    }
  }

  /// Convierte un string hex a Color.
  Color _parseColor(String hex) {
    try {
      final hexValue = hex.replaceAll('#', '');
      return Color(int.parse('FF$hexValue', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  /// Mapea el nombre del icono del backend a IconData.
  IconData _getBadgeIcon(String iconName) {
    const iconMap = {
      'assignment_turned_in': Icons.assignment_turned_in_rounded,
      'school': Icons.school_rounded,
      'workspace_premium': Icons.workspace_premium_rounded,
      'military_tech': Icons.military_tech_rounded,
      'local_fire_department': Icons.local_fire_department_rounded,
      'whatshot': Icons.whatshot_rounded,
      'bolt': Icons.bolt_rounded,
      'auto_awesome': Icons.auto_awesome_rounded,
      'trending_up': Icons.trending_up_rounded,
      'star': Icons.star_rounded,
      'emoji_events': Icons.emoji_events_rounded,
      'wb_sunny': Icons.wb_sunny_rounded,
      'nightlight': Icons.nightlight_rounded,
      'check_circle': Icons.check_circle_rounded,
      'balance': Icons.balance_rounded,
      'lock': Icons.lock_rounded,
    };
    return iconMap[iconName] ?? Icons.emoji_events_rounded;
  }
}

/// Configuración de una celebración.
class _CelebrationConfig {
  final String title;
  final String message;
  final IconData icon;
  final Color primaryColor;
  final List<Color> confettiColors;

  _CelebrationConfig({
    required this.title,
    required this.message,
    required this.icon,
    required this.primaryColor,
    required this.confettiColors,
  });
}
