import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class AreaBarChart extends StatelessWidget {
  final Map<String, dynamic> user;
  final Map<String, dynamic> avg;
  final String scopeLabel;
  final bool useAbbreviations;

  const AreaBarChart({
    Key? key,
    required this.user,
    required this.avg,
    required this.scopeLabel,
    this.useAbbreviations = false,
  }) : super(key: key);

  String _getLabel(String area) {
    if (useAbbreviations) {
      final abbreviations = {
        "Lectura": "Lect.",
        "Matemáticas": "Mat.",
        "Sociales": "Soc.",
        "Naturales": "Nat.",
        "Inglés": "Ing.",
      };
      return abbreviations[area] ?? area;
    }
    return area;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  List<BarChartGroupData> _buildBarGroups(List<String> areas) {
    final List<BarChartGroupData> barGroups = [];

    for (int i = 0; i < areas.length; i++) {
      final area = areas[i];
      final userValue = _toDouble(user[area]);
      final avgValue = _toDouble(avg[area]);

      barGroups.add(
        BarChartGroupData(
          x: i,
          groupVertically: true,
          barRods: [
            // Barra del promedio (fondo claro)
            BarChartRodData(
              toY: avgValue,
              color: AppColors.border, // Gris claro
              width: 24,
              borderRadius: BorderRadius.circular(6),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: 100, // Altura máxima fija para mejor comparación
                color: AppColors.surfaceClean,
              ),
            ),
            // Barra del usuario (encima del promedio)
            BarChartRodData(
              toY: userValue,
              color: _getBarColor(userValue, avgValue),
              width: 24,
              borderRadius: BorderRadius.circular(6),
            ),
          ],
        ),
      );
    }

    return barGroups;
  }

  Color _getBarColor(double userValue, double avgValue) {
    if (userValue > avgValue) {
      return AppColors.successDark; // Verde - por encima del promedio
    } else if (userValue < avgValue) {
      return AppColors.error; // Rojo - por debajo del promedio
    } else {
      return AppColors.warning; // Amarillo - igual al promedio
    }
  }

  String _getPerformanceText(double userValue, double avgValue) {
    final difference = userValue - avgValue;
    
    if (difference > 10) {
      return 'Muy arriba';
    } else if (difference > 5) {
      return 'Arriba';
    } else if (difference > 0) {
      return 'Lig. arriba';
    } else if (difference < -10) {
      return 'Muy abajo';
    } else if (difference < -5) {
      return 'Abajo';
    } else if (difference < 0) {
      return 'Lig. abajo';
    } else {
      return 'Igual';
    }
  }

  @override
  Widget build(BuildContext context) {
    final areas = ["Lectura", "Matemáticas", "Sociales", "Naturales", "Inglés"];
    final barGroups = _buildBarGroups(areas);

    // Calcular valor máximo para escala
    double maxValue = 0;
    for (final area in areas) {
      final userValue = _toDouble(user[area]);
      final avgValue = _toDouble(avg[area]);
      if (userValue > maxValue) maxValue = userValue;
      if (avgValue > maxValue) maxValue = avgValue;
    }
    
    // Usar una escala fija de 0-100 para consistencia, pero ajustar si hay valores mayores
    final maxY = maxValue > 100 ? (maxValue * 1.2).ceilToDouble() : 100;
    final interval = maxY > 100 ? 25 : 20;

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
                color: AppColors.shadowSm,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Comparación con promedio $scopeLabel',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              // Leyenda con Wrap para evitar overflow
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildLegendItem(
                    color: AppColors.successDark,
                    label: 'Por encima',
                  ),
                  _buildLegendItem(
                    color: AppColors.warning,
                    label: 'Igual',
                  ),
                  _buildLegendItem(
                    color: AppColors.error,
                    label: 'Por debajo',
                  ),
                  _buildLegendItem(
                    color: AppColors.border,
                    label: 'Promedio',
                    isDashed: true,
                  ),
                ],
              ),
            ],
          ),
        ),

// Gráfico
SizedBox(
  height: 340,
  child: BarChart(
    BarChartData(
      alignment: BarChartAlignment.spaceBetween,
      groupsSpace: 32,
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          tooltipPadding: const EdgeInsets.all(12),
          tooltipMargin: 8,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final area = areas[group.x.toInt()];
            final userValue = _toDouble(user[area]);
            final avgValue = _toDouble(avg[area]);

            final isUserBar = rodIndex == 1; // Índice 1 es la barra del usuario
            final value = rod.toY;

            String label;
            String differenceText = '';

            if (isUserBar) {
              label = 'Tu puntaje';
              final difference = userValue - avgValue;
              differenceText = difference >= 0
                  ? '+${difference.toStringAsFixed(1)}'
                  : difference.toStringAsFixed(1);
            } else {
              label = 'Promedio';
            }

            return BarTooltipItem(
              '${_getLabel(area)}\n$label: ${value.toStringAsFixed(1)}\n'
              '${isUserBar ? 'Diferencia: $differenceText' : ''}',
              TextStyle(
                color: AppColors.textOnPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                backgroundColor: AppColors.textSecondary,
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
                  value.toInt().toString(),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            },
            interval: interval.toDouble(),
          ),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          axisNameWidget: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Áreas del Conocimiento',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48, // ↑ Aumenta espacio reservado para evitar overflow
            getTitlesWidget: (value, meta) {
              final area = areas[value.toInt()];
              final userValue = _toDouble(user[area]);
              final avgValue = _toDouble(avg[area]);

              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: 60,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _getLabel(area),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.borderDark,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: _getBarColor(userValue, avgValue).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _getPerformanceText(userValue, avgValue),
                            style: TextStyle(
                              fontSize: 7,
                              color: _getBarColor(userValue, avgValue),
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
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
        horizontalInterval: interval.toDouble(),
        getDrawingHorizontalLine: (value) => FlLine(
          color: AppColors.surfaceVariant,
          strokeWidth: 1,
          dashArray: const [4, 4],
        ),
      ),
      barGroups: barGroups,
      maxY: maxY.toDouble(),
      minY: 0,
    ),
  ),
),


        // Análisis de rendimiento
        Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowSm,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Análisis de Rendimiento',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              ...areas.map((area) {
                final userValue = _toDouble(user[area]);
                final avgValue = _toDouble(avg[area]);
                final difference = userValue - avgValue;
                final percentage = avgValue > 0 ? (difference / avgValue * 100) : 0;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          _getLabel(area),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                value: userValue / maxY,
                                backgroundColor: AppColors.border,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _getBarColor(userValue, avgValue),
                                ),
                                minHeight: 8,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getBarColor(userValue, avgValue).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                difference >= 0 
                                  ? '+${difference.toStringAsFixed(1)}'
                                  : difference.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _getBarColor(userValue, avgValue),
                                ),
                              ),
                            ),
                          ],
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

  Widget _buildLegendItem({
    required Color color,
    required String label,
    bool isDashed = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min, // Importante: usar min para evitar overflow
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: isDashed
                ? Border.all(color: AppColors.textTertiary, width: 1, style: BorderStyle.solid)
                : null,
          ),
          child: isDashed
              ? Center(
                  child: Container(
                    height: 1,
                    color: AppColors.textTertiary,
                  ),
                )
              : null,
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