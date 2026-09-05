// lib/screens/daily_challenges_screen.dart
// Saber+ — Pantalla de Retos Diarios
//
// Muestra los retos diarios disponibles organizados por estado:
// - Disponibles (pendientes de completar)
// - Completados hoy
//
// Cada reto muestra:
// - Área/materia con color e icono
// - Nombre del reto
// - Número de preguntas
// - Tiempo límite
// - Tiempo restante antes de que expire
// - Botón "Iniciar reto" o badge "Completado"

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../core/animations/app_animations.dart';
import '../core/utils/app_logger.dart';
import '../services/daily_challenge_service.dart';
import '../models/daily_challenge.dart';
import '../config/navigation.dart';
import '../models/course.dart';
import '../providers/gamification_provider.dart';
import '../widgets/gamification/celebration_overlay.dart';

class DailyChallengesScreen extends StatefulWidget {
  const DailyChallengesScreen({super.key});

  @override
  State<DailyChallengesScreen> createState() => _DailyChallengesScreenState();
}

class _DailyChallengesScreenState extends State<DailyChallengesScreen>
    with SingleTickerProviderStateMixin {
  DailyChallengesResponse? _response;
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadChallenges();
  }

  Future<void> _loadChallenges({bool forceRefresh = false}) async {
    if (!forceRefresh && _isRefreshing) return;

    setState(() {
      if (_response == null) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
      _error = null;
    });

    try {
      final data = await DailyChallengeService.getDailyChallenges();
      if (!mounted) return;

      setState(() {
        _response = data;
        _isLoading = false;
        _isRefreshing = false;
      });

      if (data != null) {
        AppLogger.i('DailyChallenges: cargados ${data.totalAvailable} disponibles, '
            '${data.totalCompleted} completados');
      }
    } catch (e) {
      AppLogger.e('DailyChallenges: error', e);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _error = 'No se pudieron cargar los retos. Inténtalo de nuevo.';
      });
    }
  }

  /// Inicia un reto diario — navega al cuestionario.
  Future<void> _startChallenge(DailyChallenge challenge) async {
    try {
      // Crear un Course temporal para el QuizListScreen
      final course = Course(
        id: challenge.courseId,
        fullname: challenge.area,
        shortname: challenge.area,
        startdate: 0,
        enddate: 0,
        visible: true,
      );

      // Navegar a la lista de quizzes del curso
      Nav.goQuizzes(context, course: course);
    } catch (e) {
      AppLogger.e('DailyChallenges: error iniciando reto', e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al iniciar el reto: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Otorga XP por completar un reto diario.
  Future<void> _awardDailyChallengeXp(DailyChallenge challenge) async {
    final gamif = context.read<GamificationProvider>();
    final result = await gamif.awardXp(
      reason: 'reto',
      xpAmount: 50, // XP fija por reto diario
      referenceId: challenge.id,
      description: 'Completaste el reto diario de ${challenge.area}',
    );

    if (result != null && mounted) {
      // Mostrar celebración
      if (result.leveledUp && result.newBadges.isNotEmpty) {
        await CelebrationOverlay.show(
          context,
          type: CelebrationType.levelUp,
          level: result.newLevel,
          newBadges: result.newBadges,
          xpEarned: result.xpAwarded,
        );
      } else if (result.newBadges.isNotEmpty) {
        await CelebrationOverlay.show(
          context,
          type: CelebrationType.badgeUnlocked,
          newBadges: result.newBadges,
          xpEarned: result.xpAwarded,
        );
      } else {
        await CelebrationOverlay.show(
          context,
          type: CelebrationType.simulacroComplete,
          xpEarned: result.xpAwarded,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── App Bar ──
            _buildAppBar(context, isDark),

            // ── Contenido ──
            Expanded(
              child: _isLoading
                  ? _buildLoading(isDark)
                  : _error != null
                      ? _buildError(isDark)
                      : _response == null || _response!.totalChallenges == 0
                          ? _buildEmpty(isDark)
                          : RefreshIndicator(
                              onRefresh: () => _loadChallenges(forceRefresh: true),
                              color: AppColors.primary,
                              backgroundColor:
                                  isDark ? AppColors.darkSurface : AppColors.surface,
                              child: _buildContent(isDark),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // WIDGETS
  // ═══════════════════════════════════════════════════

  Widget _buildAppBar(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
            color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Retos Diarios',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                  ),
                ),
                if (_response != null)
                  Text(
                    _response!.allCompleted
                        ? '¡Completaste todos los retos de hoy! 🎉'
                        : '${_response!.totalAvailable} retos disponibles',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: _isRefreshing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
                    ),
                  )
                : Icon(Icons.refresh_rounded),
            onPressed: _isRefreshing ? null : () => _loadChallenges(forceRefresh: true),
            color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    final available = _response!.available;
    final completed = _response!.completed;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Banner de progreso del día ──
          if (_response != null) _buildProgressBanner(isDark),
          const SizedBox(height: 24),

          // ── Retos disponibles ──
          if (available.isNotEmpty) ...[
            _buildSectionHeader(
              isDark,
              icon: Icons.flash_on_rounded,
              title: 'Disponibles ahora',
              count: available.length,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            ...available.map((c) => _buildChallengeCard(c, isDark)),
          ],

          // ── Retos completados ──
          if (completed.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildSectionHeader(
              isDark,
              icon: Icons.check_circle_rounded,
              title: 'Completados hoy',
              count: completed.length,
              color: AppColors.success,
            ),
            const SizedBox(height: 12),
            ...completed.map((c) => _buildChallengeCard(c, isDark, isCompleted: true)),
          ],

          // ── Mensaje de "todos completados" ──
          if (_response!.allCompleted) ...[
            const SizedBox(height: 32),
            _buildAllCompletedWidget(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressBanner(bool isDark) {
    final total = _response!.totalChallenges;
    final completed = _response!.totalCompleted;
    final pct = total > 0 ? (completed / total * 100).round() : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: pct == 100
              ? [AppColors.success, AppColors.successDark]
              : [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (pct == 100 ? AppColors.success : AppColors.primary).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                pct == 100 ? Icons.emoji_events_rounded : Icons.today_rounded,
                color: AppColors.textOnPrimary,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pct == 100
                          ? '¡Día completado!'
                          : 'Progreso de hoy',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                    Text(
                      '$completed de $total retos completados',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textOnPrimary.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textOnPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total > 0 ? completed / total : 0,
              backgroundColor: AppColors.textOnPrimary.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.textOnPrimary),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    bool isDark, {
    required IconData icon,
    required String title,
    required int count,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChallengeCard(DailyChallenge challenge, bool isDark,
      {bool isCompleted = false}) {
    final areaColor = _parseColor(challenge.areaColor);
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: PressScale(
        onTap: isCompleted ? null : () => _startChallenge(challenge),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCompleted
                  ? AppColors.success.withOpacity(0.3)
                  : areaColor.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowSm,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // ── Icono del área ──
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: areaColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _getAreaIcon(challenge.areaIcon),
                  color: areaColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),

              // ── Información del reto ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.area,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: areaColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      challenge.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.help_outline_rounded, size: 14, color: textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          '${challenge.questions} preguntas',
                          style: TextStyle(fontSize: 11, color: textTertiary),
                        ),
                        if (challenge.timelimit > 0) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.timer_outlined, size: 14, color: textTertiary),
                          const SizedBox(width: 4),
                          Text(
                            '${(challenge.timelimit / 60).round()} min',
                            style: TextStyle(fontSize: 11, color: textTertiary),
                          ),
                        ],
                        if (!isCompleted && challenge.remainingTime > 0) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.schedule_rounded, size: 14, color: AppColors.warning),
                          const SizedBox(width: 4),
                          Text(
                            challenge.remainingTimeFormatted,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // ── Badge de estado / Botón iniciar ──
              if (isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 16, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text(
                        'Completado',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.successDark,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: areaColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: areaColor.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded, size: 18, color: AppColors.textOnPrimary),
                      const SizedBox(width: 4),
                      Text(
                        'Iniciar',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textOnPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllCompletedWidget(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success.withOpacity(0.1),
            ),
            child: Icon(
              Icons.emoji_events_rounded,
              size: 48,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '¡Felicitaciones!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Has completado todos los retos diarios de hoy. '
            '¡Vuelve mañana para nuevos desafíos!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '+${_response!.totalCompleted * 50} XP ganados hoy',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'Cargando retos diarios...',
            style: TextStyle(
              color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(fontSize: 14, color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _loadChallenges(forceRefresh: true),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.today_outlined,
              size: 64,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              'No hay retos diarios disponibles ahora',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Vuelve más tarde para nuevos desafíos.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──

  Color _parseColor(String hex) {
    try {
      final hexValue = hex.replaceAll('#', '');
      return Color(int.parse('FF$hexValue', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  IconData _getAreaIcon(String iconName) {
    const iconMap = {
      'calculate_rounded': Icons.calculate_rounded,
      'public_rounded': Icons.public_rounded,
      'translate_rounded': Icons.translate_rounded,
      'science_rounded': Icons.science_rounded,
      'menu_book_rounded': Icons.menu_book_rounded,
      'extension_rounded': Icons.extension_rounded,
    };
    return iconMap[iconName] ?? Icons.extension_rounded;
  }
}
