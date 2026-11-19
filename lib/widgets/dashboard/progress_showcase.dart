// lib/widgets/dashboard/progress_showcase.dart
// Saber+ — Panel premium de progreso del estudiante (v1.7.1)
//
// Reemplaza las tarjetas de cursos de retos en el dashboard: esas tarjetas
// no eran accesibles directamente (los retos solo se juegan cuando un
// usuario reta a otro), así que ocupaban espacio sin función.
//
// En su lugar: una vitrina de progreso personal con estética premium —
// nivel con anillo de progreso, racha, insignias y XP total — conectada
// en vivo al GamificationProvider.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/gamification_provider.dart';

class ProgressShowcase extends StatelessWidget {
  const ProgressShowcase({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final gamif = context.watch<GamificationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final level = gamif.level;
    final progress = (gamif.levelProgressPct.clamp(0.0, 100.0)) / 100.0;
    final xpToNext = gamif.xpToNextLevel;
    final streak = gamif.currentStreak;
    final maxStreak = gamif.maxStreak;
    final badges = gamif.unlockedBadgesCount;
    final totalBadges = gamif.totalBadgesCount;
    final totalXp = gamif.totalXp;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E3A8A), // primaryDeep
            Color(0xFF1E4ED8), // primary
            Color(0xFF3B82F6), // primaryLight
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E4ED8).withOpacity(isDark ? 0.45 : 0.30),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            // ── Textura decorativa: círculos sutiles ──
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                    width: 18,
                  ),
                ),
              ),
            ),
            Positioned(
              left: -20,
              bottom: -40,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),

            // ── Contenido ──
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Encabezado
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.accent.withOpacity(0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.workspace_premium_rounded,
                                size: 14, color: AppColors.accent),
                            SizedBox(width: 5),
                            Text(
                              'SABER+ PRO',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _fechaBonita(),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.55),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Anillo de nivel ──
                      _LevelRing(level: level, progress: progress),
                      const SizedBox(width: 18),

                      // ── Texto central ──
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tu progreso',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$totalXp XP acumulados',
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Barra de progreso al siguiente nivel
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 7,
                                backgroundColor: Colors.white.withOpacity(0.18),
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                        AppColors.accent),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              xpToNext > 0
                                  ? 'Te faltan $xpToNext XP para el nivel ${level + 1}'
                                  : '¡Nivel $level desbloqueado!',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.accent.withOpacity(0.95),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // ── Fila de estadísticas ──
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.12),
                      ),
                    ),
                    child: Row(
                      children: [
                        _StatChip(
                          icon: Icons.local_fire_department_rounded,
                          value: '$streak',
                          label: 'Racha',
                          sub: streak > 0 ? 'máx $maxStreak' : 'empieza hoy',
                          iconColor: Colors.orangeAccent,
                        ),
                        _dividerVert(),
                        _StatChip(
                          icon: Icons.military_tech_rounded,
                          value: '$badges',
                          label: 'Insignias',
                          sub: 'de $totalBadges',
                          iconColor: AppColors.accent,
                        ),
                        _dividerVert(),
                        _StatChip(
                          icon: Icons.bolt_rounded,
                          value: '${gamif.todayXp}',
                          label: 'XP hoy',
                          sub: gamif.todaySimulacros > 0
                              ? '${gamif.todaySimulacros} simulacros'
                              : 'a practicar',
                          iconColor: Colors.lightGreenAccent,
                        ),
                      ],
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

  static Widget _dividerVert() {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white.withOpacity(0.14),
    );
  }

  static String _fechaBonita() {
    const meses = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
    ];
    final now = DateTime.now();
    return '${now.day} ${meses[now.month - 1]} ${now.year}';
  }
}

// ── Anillo de nivel con progreso ──
class _LevelRing extends StatelessWidget {
  final int level;
  final double progress;

  const _LevelRing({required this.level, required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 78,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 78,
            height: 78,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 5.5,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.white.withOpacity(0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'NIVEL',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: Colors.white.withOpacity(0.65),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '$level',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Chip de estadística ──
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String sub;
  final Color iconColor;

  const _StatChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.sub,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Colors.white.withOpacity(0.75),
            ),
          ),
          Text(
            sub,
            style: TextStyle(
              fontSize: 9,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
