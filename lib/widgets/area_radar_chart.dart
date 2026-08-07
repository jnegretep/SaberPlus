import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class AreaRadarChart extends StatelessWidget {
  final Map<String, dynamic> user;
  final Map<String, dynamic> avg;
  final String scopeLabel;
  final bool useAbbreviations;

  const AreaRadarChart({
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

  @override
  Widget build(BuildContext context) {
    final areas = ["Lectura", "Matemáticas", "Sociales", "Naturales", "Inglés"];
    
    // Calcular el valor máximo para la escala
    double maxUserValue = 0;
    double maxAvgValue = 0;
    for (final area in areas) {
      final userValue = _toDouble(user[area]);
      final avgValue = _toDouble(avg[area]);
      if (userValue > maxUserValue) maxUserValue = userValue;
      if (avgValue > maxAvgValue) maxAvgValue = avgValue;
    }
    
    // Usar el valor máximo entre usuario y promedio
    double maxValue = maxUserValue > maxAvgValue ? maxUserValue : maxAvgValue;
    
    // Asegurar que el máximo sea múltiplo de 10 para mejor visualización
    maxValue = (maxValue / 10).ceil() * 10;
    if (maxValue < 20) maxValue = 20;

    return Column(
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
                'Perfil de Competencias vs Promedio $scopeLabel',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegendItem(
                    color: AppColors.primary,
                    borderColor: AppColors.primary,
                    label: 'Tu perfil',
                  ),
                  const SizedBox(width: 20),
                  _buildLegendItem(
                    color: AppColors.textDisabled.withOpacity(0.3),
                    borderColor: AppColors.textDisabled,
                    label: 'Promedio',
                  ),
                ],
              ),
            ],
          ),
        ),

        // Gráfico Radar
        SizedBox(
          height: 340,
          child: RadarChart(
            RadarChartData(
              radarShape: RadarShape.circle,
              radarBorderData: BorderSide(
                color: AppColors.border,
                width: 1.5,
              ),
              gridBorderData: BorderSide(
                color: AppColors.border,
                width: 0.8,
              ),
              titlePositionPercentageOffset: 0.2,
              titleTextStyle: TextStyle(
                color: AppColors.borderDark,
                fontSize: useAbbreviations ? 12 : 11,
                fontWeight: FontWeight.w600,
              ),
              tickCount: 5,
              ticksTextStyle: TextStyle(
                color: AppColors.textDisabled,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              tickBorderData: BorderSide(
                color: AppColors.surfaceVariant,
                width: 0.5,
              ),
              getTitle: (index, angle) {
                final area = areas[index];
                return RadarChartTitle(
                  text: _getLabel(area),
                  angle: angle,
                );
              },
              dataSets: [
                // Promedio (fondo)
                RadarDataSet(
                  fillColor: AppColors.textDisabled.withOpacity(0.15),
                  borderColor: AppColors.textDisabled,
                  borderWidth: 1.5,
                  entryRadius: 3,
                  dataEntries: areas.map((area) {
                    return RadarEntry(
                      value: _toDouble(avg[area]),
                    );
                  }).toList(),
                ),
                // Usuario (principal)
                RadarDataSet(
                  fillColor: AppColors.primary.withOpacity(0.3),
                  borderColor: AppColors.primary,
                  borderWidth: 2.5,
                  entryRadius: 5,
                  dataEntries: areas.map((area) {
                    return RadarEntry(
                      value: _toDouble(user[area]),
                    );
                  }).toList(),
                ),
              ],
              radarBackgroundColor: Colors.transparent,
            ),
            swapAnimationDuration: const Duration(milliseconds: 400),
            swapAnimationCurve: Curves.easeInOut,
          ),
        ),

        // Escala de valores y análisis
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
            children: [
              // Escala
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '0',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${(maxValue * 0.25).toInt()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${(maxValue * 0.5).toInt()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${(maxValue * 0.75).toInt()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${maxValue.toInt()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 12),
              
              // Análisis por área
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Análisis por Competencia',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...areas.asMap().entries.map((entry) {
                    final area = entry.value;
                    final userValue = _toDouble(user[area]);
                    final avgValue = _toDouble(avg[area]);
                    final difference = userValue - avgValue;
                    final percentage = avgValue > 0 ? (difference / avgValue * 100) : 0;
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Text(
                                  _getLabel(area),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: _getDifferenceColor(difference).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    difference >= 0 
                                      ? '+${difference.toStringAsFixed(1)}'
                                      : difference.toStringAsFixed(1),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: _getDifferenceColor(difference),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      // Barra de promedio (fondo)
                                      Container(
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: AppColors.border,
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                      // Barra del usuario
                                      Positioned(
                                        left: 0,
                                        child: Container(
                                          width: (userValue / maxValue) * 100,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: _getDifferenceColor(difference),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                        ),
                                      ),
                                      // Indicador del promedio
                                      Positioned(
                                        left: (avgValue / maxValue) * 100 - 2,
                                        child: Container(
                                          width: 4,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: AppColors.textDisabled,
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getDifferenceColor(difference).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        difference >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                                        size: 10,
                                        color: _getDifferenceColor(difference),
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${percentage.abs().toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: _getDifferenceColor(difference),
                                        ),
                                      ),
                                    ],
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
            ],
          ),
        ),
      ],
    );
  }

  Color _getDifferenceColor(double difference) {
    if (difference > 10) {
      return AppColors.successDark; // Verde fuerte
    } else if (difference > 5) {
      return AppColors.successFg; // Verde medio
    } else if (difference > 0) {
      return AppColors.successFg; // Verde claro
    } else if (difference < -10) {
      return AppColors.error; // Rojo fuerte
    } else if (difference < -5) {
      return AppColors.error; // Rojo medio
    } else if (difference < 0) {
      return AppColors.errorFg; // Rojo claro
    } else {
      return AppColors.warning; // Amarillo - igual
    }
  }

  Widget _buildLegendItem({
    required Color color,
    required Color borderColor,
    required String label,
  }) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: borderColor, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.borderDark,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}