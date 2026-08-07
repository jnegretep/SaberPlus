import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class RankingBarChart extends StatelessWidget {
  final Map<String, dynamic> ranking;

  const RankingBarChart({
    Key? key,
    required this.ranking,
  }) : super(key: key);

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> labels = {
      "colegio_rank": "Colegio",
      "ciudad_rank": "Ciudad",
      "departamento_rank": "Departamento",
      "nacional_rank": "Nacional",
    };

    final List<MapEntry<String, int>> data = labels.entries
        .map((entry) => MapEntry(entry.value, _toInt(ranking[entry.key])))
        .where((entry) => entry.value > 0) // Solo mostrar si hay ranking
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value)); // Ordenar por ranking

    if (data.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowMd,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.leaderboard_outlined,
              size: 48,
              color: AppColors.textDisabled,
            ),
            SizedBox(height: 12),
            Text(
              'No hay datos de ranking',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.borderDark,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Completa más simulacros para ver tu posición',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Encontrar el mejor ranking (más bajo es mejor)
    final bestRank = data.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    final worstRank = data.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    
    // Para la escala, usar el peor ranking + margen
    final maxRank = (worstRank * 1.2).ceil();

    // Crear los grupos de barras
    final barGroups = data.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final rank = item.value;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: rank.toDouble(),
            color: _getRankColor(rank, bestRank, worstRank),
            width: 28,
            borderRadius: BorderRadius.circular(6),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxRank.toDouble(),
              color: AppColors.surfaceClean,
            ),
          ),
        ],
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Título y leyenda
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowMd,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tu Posición en el Ranking',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildLegendItem(
                    color: AppColors.successDark,
                    label: 'Top 10%',
                  ),
                  _buildLegendItem(
                    color: AppColors.warning,
                    label: 'Top 50%',
                  ),
                  _buildLegendItem(
                    color: AppColors.error,
                    label: 'Por mejorar',
                  ),
                ],
              ),
            ],
          ),
        ),

        // Gráfico
        SizedBox(
          height: 280,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceBetween,
              groupsSpace: 40,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  tooltipPadding: const EdgeInsets.all(12),
                  tooltipMargin: 8,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final item = data[group.x.toInt()];
                    final rank = item.value;
                    final label = item.key;

                    return BarTooltipItem(
                      '$label\nPosición #$rank',
                      TextStyle(
                        color: AppColors.textOnPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '#${value.toInt()}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                    interval: (maxRank / 5).ceilToDouble(),
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value.toInt() < data.length) {
                        final item = data[value.toInt()];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SizedBox(
                            width: 80,
                            child: Text(
                              item.key,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.borderDark,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(
                  color: AppColors.border,
                  width: 1,
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                drawHorizontalLine: true,
                horizontalInterval: (maxRank / 5).ceilToDouble(),
                getDrawingHorizontalLine: (value) => FlLine(
                  color: AppColors.surfaceVariant,
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ),
              barGroups: barGroups,
              maxY: maxRank.toDouble(),
              minY: 0,
            ),
          ),
        ),

        // Análisis de ranking
        Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowMd,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Resumen de Posiciones',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              ...data.map((item) {
                final rank = item.value;
                final label = item.key;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getRankColor(rank, bestRank, worstRank).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '#$rank',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _getRankColor(rank, bestRank, worstRank),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }

  Color _getRankColor(int rank, int bestRank, int worstRank) {
    // Si no hay suficientes datos para comparar
    if (bestRank == worstRank) return AppColors.primary;
    
    final range = worstRank - bestRank;
    final position = (rank - bestRank) / range;
    
    if (position < 0.3) {
      return AppColors.successDark; // Top 30% - Verde
    } else if (position < 0.7) {
      return AppColors.warning; // Medio 40% - Amarillo
    } else {
      return AppColors.error; // Último 30% - Rojo
    }
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
  }) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}