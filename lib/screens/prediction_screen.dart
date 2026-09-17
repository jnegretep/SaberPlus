// lib/screens/prediction_screen.dart
// Saber+ - Pantalla de Prediccion ICFES y Comparativa Historica
//
// Muestra:
// 1. Card de prediccion con puntaje estimado, rango y confianza
// 2. Grafico de linea con la evolucion del puntaje
// 3. Analisis por area (fortalezas y debilidades con barras)
// 4. Recomendaciones personalizadas

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/theme/app_colors.dart';
import '../core/animations/app_animations.dart';
import '../core/utils/app_logger.dart';
import '../services/prediction_service.dart';
import '../models/icfes_prediction.dart';

class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key});

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  PredictionResponse? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await PredictionService.getPrediction();
      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.e('PredictionScreen: error', e);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'No se pudo cargar la prediccion';
      });
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
            _buildAppBar(context, isDark),
            Expanded(
              child: _isLoading
                  ? _buildLoading()
                  : _error != null
                      ? _buildError(isDark)
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          color: AppColors.primary,
                          child: _data == null
                              ? _buildEmpty(isDark)
                              : _buildContent(isDark),
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
            child: Text(
              'Prediccion ICFES',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
            color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Card de prediccion
          if (_data!.prediction != null) ...[
            _buildPredictionCard(_data!.prediction!, isDark),
            const SizedBox(height: 24),
          ],

          // 2. Grafico de evolucion
          if (_data!.history.isNotEmpty) ...[
            _buildSectionTitle(isDark, 'Evolucion del puntaje', Icons.trending_up_rounded),
            const SizedBox(height: 12),
            _buildHistoryChart(isDark),
            const SizedBox(height: 24),
          ],

          // 3. Analisis por area
          if (_data!.areaAnalysis.isNotEmpty) ...[
            _buildSectionTitle(isDark, 'Analisis por area', Icons.bar_chart_rounded),
            const SizedBox(height: 12),
            _buildAreaAnalysis(isDark),
            const SizedBox(height: 24),
          ],

          // 4. Recomendaciones
          if (_data!.recommendations.isNotEmpty) ...[
            _buildSectionTitle(isDark, 'Recomendaciones', Icons.lightbulb_outline_rounded),
            const SizedBox(height: 12),
            _buildRecommendations(isDark),
          ],
        ],
      ),
    );
  }

  /// Card principal con la prediccion del puntaje ICFES.
  Widget _buildPredictionCard(IcfesPrediction pred, bool isDark) {
    final trendIcon = pred.isAscending
        ? Icons.trending_up_rounded
        : pred.isDescending
            ? Icons.trending_down_rounded
            : Icons.trending_flat_rounded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primaryLight,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Tu puntaje ICFES estimado',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // Puntaje grande
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${pred.predictedScore}',
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/ 500',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.white.withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Rango
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Rango: ${pred.rangeMin} - ${pred.rangeMax}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Tendencia + confianza
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(trendIcon, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              Text(
                pred.trend == 'ascending'
                    ? 'Subiendo ${pred.trendPct}%'
                    : pred.trend == 'descending'
                        ? 'Bajando ${pred.trendPct.abs()}%'
                        : 'Estable',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.verified_rounded, color: Colors.white.withOpacity(0.8), size: 16),
              const SizedBox(width: 4),
              Text(
                'Confianza: ${pred.confidence} (${pred.confidencePct}%)',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Mensaje
          Text(
            pred.message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.85),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Grafico de linea con la evolucion del puntaje.
  Widget _buildHistoryChart(bool isDark) {
    final history = _data!.history;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textColor = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 100,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: textColor.withOpacity(0.1),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        '${value.toInt()}',
                        style: TextStyle(fontSize: 10, color: textColor),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: history.length > 1 ? 1 : null,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= history.length) {
                          return const SizedBox.shrink();
                        }
                        final date = history[idx].date;
                        final shortDate = date.length >= 5 ? date.substring(5) : date;
                        return Text(
                          shortDate,
                          style: TextStyle(fontSize: 9, color: textColor),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minY: 0,
                maxY: 500,
                lineBarsData: [
                  LineChartBarData(
                    spots: history.asMap().entries.map((e) {
                      return FlSpot(e.key.toDouble(), e.value.score);
                    }).toList(),
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    // 🔧 FIX fl_chart 1.1.1:
                    // - Se eliminó `dotColor` (ya no existe como parámetro).
                    // - Los puntos se personalizan vía `dotData.getDotPainter`.
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: AppColors.primary,
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withOpacity(0.1),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    // 🔧 FIX fl_chart 1.1.1:
                    // getTooltipItems ahora debe devolver `List<LineTooltipItem?>`
                    // (antes era `List<LineTooltipItem>` no-nullable).
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map<LineTooltipItem?>((spot) {
                        final idx = spot.spotIndex;
                        if (idx < 0 || idx >= history.length) return null;
                        final point = history[idx];
                        return LineTooltipItem(
                          '${point.score.toInt()}\n${point.simulacro}',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Analisis por area con barras horizontales.
  Widget _buildAreaAnalysis(bool isDark) {
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: _data!.areaAnalysis.map((area) {
          final color = _parseColor(area.color);
          final trendIcon = area.isUp
              ? Icons.arrow_upward_rounded
              : area.isDown
                  ? Icons.arrow_downward_rounded
                  : Icons.remove_rounded;
          final trendColor = area.isUp
              ? AppColors.success
              : (area.isDown ? AppColors.error : AppColors.textTertiary);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_getAreaIcon(area.icon), size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        area.area,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    Icon(trendIcon, size: 14, color: trendColor),
                    const SizedBox(width: 4),
                    Text(
                      '${area.avg.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (area.avg / 100).clamp(0.0, 1.0),
                    backgroundColor: color.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Lista de recomendaciones personalizadas.
  Widget _buildRecommendations(bool isDark) {
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: _data!.recommendations.map((rec) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded,
                    size: 18, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    rec,
                    style: TextStyle(
                      fontSize: 13,
                      color: textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionTitle(bool isDark, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
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
            const Icon(Icons.cloud_off_rounded,
                size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(fontSize: 14, color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
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
            const Icon(Icons.insights_outlined,
                size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(
              'Aun no tienes suficientes datos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Completa al menos 1 simulacro para ver tu prediccion ICFES.',
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
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  IconData _getAreaIcon(String name) {
    const map = {
      'menu_book_rounded': Icons.menu_book_rounded,
      'calculate_rounded': Icons.calculate_rounded,
      'public_rounded': Icons.public_rounded,
      'science_rounded': Icons.science_rounded,
      'translate_rounded': Icons.translate_rounded,
      'extension_rounded': Icons.extension_rounded,
    };
    return map[name] ?? Icons.extension_rounded;
  }
}