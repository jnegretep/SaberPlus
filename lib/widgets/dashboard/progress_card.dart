// lib/widgets/dashboard/progress_card.dart
// Premium progress card with animated score circle

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/animations/app_animations.dart';

class ProgressCard extends StatelessWidget {
  final double? scoreGlobal; // ej: 302.9
  final Map<String, double>? areas; // 0–100
  final DateTime? ultimaFecha;
  final int? tiempoPromedioSeg;

  const ProgressCard({
    super.key,
    required this.scoreGlobal,
    required this.areas,
    this.ultimaFecha,
    this.tiempoPromedioSeg,
  });

  @override
  Widget build(BuildContext context) {
    final areaStats = _topAndBottomAreas(areas);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.transparent : AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ───── TÍTULO ─────
          Text(
            'Tu progreso general',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 16),

          // ───── TARJETA SUPERIOR (CÍRCULO + ÁREAS) ─────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceClean,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ⭕ ANIMATED CÍRCULO GRANDE
                AnimatedScoreCircle(
                  score: scoreGlobal ?? 0,
                  maxScore: 500,
                  color: AppColors.primary,
                  size: 85,
                  strokeWidth: 12,
                ),

                const SizedBox(width: 20),

                // 📊 BARRAS DE ÁREAS
                Expanded(
                  child: Column(
                    children: areaStats.map((e) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _AreaBar(
                          label: _labelArea(e.key),
                          value: e.value,
                          color: e.isTop
                              ? AppColors.primary
                              : AppColors.accent,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ───── TARJETA INFERIOR (ÚLTIMO SIMULACRO) ─────
          _LastSimulacroCard(
            fecha: ultimaFecha,
            tiempoSeg: tiempoPromedioSeg,
          ),
        ],
      ),
    );
  }

  // ───────────────── HELPERS ─────────────────

  List<_AreaStat> _topAndBottomAreas(Map<String, double>? areas) {
    if (areas == null || areas.isEmpty) return [];

    final list = areas.entries
        .where((e) => e.value != null)
        .map((e) => _AreaStat(e.key, e.value!))
        .toList();

    list.sort((a, b) => b.value.compareTo(a.value));

    if (list.length == 1) {
      list.first.isTop = true;
      return list;
    }

    list.first.isTop = true;
    list.last.isTop = false;

    return [list.first, list.last];
  }

  String _labelArea(String key) {
    const map = {
      'lectura': 'Lectura',
      'matematicas': 'Matemáticas',
      'sociales': 'Sociales',
      'naturales': 'Naturales',
      'ingles': 'Inglés',
    };
    return map[key] ?? key;
  }
}

/// ─────────────────────────────
/// BARRA DE ÁREA CON VALOR
/// ─────────────────────────────
class _AreaBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _AreaBar({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextTertiary : AppColors.borderMedium;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor,
                  ),
                ),
              ),
              Text(
                value.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: isDark ? AppColors.darkSurfaceVariant : AppColors.divider,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────
/// TARJETA ÚLTIMO SIMULACRO
/// ─────────────────────────────
class _LastSimulacroCard extends StatelessWidget {
  final DateTime? fecha;
  final int? tiempoSeg;

  const _LastSimulacroCard({this.fecha, this.tiempoSeg});

  @override
  Widget build(BuildContext context) {
    final fechaTxt = fecha != null
        ? '${fecha!.day}/${fecha!.month}/${fecha!.year}'
        : '—';

    final tiempoTxt = tiempoSeg != null
        ? '${(tiempoSeg! / 60).floor()}m ${tiempoSeg! % 60}s'
        : '—';

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceClean,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.trending_up,
              size: 18,
              color: AppColors.textOnPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Último simulacro',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$fechaTxt\n$tiempoTxt',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkTextTertiary : AppColors.borderMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────
/// MODELO INTERNO
/// ─────────────────────────────
class _AreaStat {
  final String key;
  final double value;
  bool isTop;

  _AreaStat(this.key, this.value, {this.isTop = false});
}
