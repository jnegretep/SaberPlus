// lib/screens/error_analysis_screen.dart
// Saber+ - Pantalla de Analisis de Errores
//
// Muestra:
// 1. Resumen general (precision, total errores, area mas debil)
// 2. Grafico de dona con tipos de error
// 3. Barras por area (correctas vs incorrectas)
// 4. Evolucion de precision (grafico de linea)
// 5. Recomendaciones personalizadas

// 🔧 FIX #1: Flutter exporta su propia clase ErrorSummary desde
// package:flutter/foundation.dart (usada en diagnósticos). Hay que
// ocultarla para que solo quede visible la de nuestro modelo local.
import 'package:flutter/material.dart' hide ErrorSummary;
import 'package:fl_chart/fl_chart.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/app_logger.dart';
import '../services/error_analysis_service.dart';
import '../models/error_analysis.dart';

class ErrorAnalysisScreen extends StatefulWidget {
  const ErrorAnalysisScreen({super.key});

  @override
  State<ErrorAnalysisScreen> createState() => _ErrorAnalysisScreenState();
}

class _ErrorAnalysisScreenState extends State<ErrorAnalysisScreen> {
  ErrorAnalysisResponse? _data;
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
      final data = await ErrorAnalysisService.getAnalysis();
      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.e('ErrorAnalysisScreen: error', e);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'No se pudo cargar el analisis';
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
                          child: _data == null || _data!.summary == null
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
              'Analisis de Errores',
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
          // 1. Resumen general
          if (_data!.summary != null) ...[
            _buildSummaryCard(_data!.summary!, isDark),
            const SizedBox(height: 24),
          ],

          // 2. Tipos de error (grafico de dona)
          if (_data!.errorTypes.isNotEmpty &&
              _data!.errorTypes.first.type != 'none') ...[
            _buildSectionTitle(isDark, 'Tipos de Error', Icons.category_rounded),
            const SizedBox(height: 12),
            _buildErrorTypesCard(isDark),
            const SizedBox(height: 24),
          ],

          // 3. Errores por area (barras)
          if (_data!.byArea.isNotEmpty) ...[
            _buildSectionTitle(isDark, 'Errores por Area', Icons.bar_chart_rounded),
            const SizedBox(height: 12),
            _buildByAreaCard(isDark),
            const SizedBox(height: 24),
          ],

          // 4. Evolucion de precision
          if (_data!.evolution.length >= 2) ...[
            _buildSectionTitle(isDark, 'Evolucion de Precision', Icons.trending_up_rounded),
            const SizedBox(height: 12),
            _buildEvolutionChart(isDark),
            const SizedBox(height: 24),
          ],

          // 5. Recomendaciones
          if (_data!.recommendations.isNotEmpty) ...[
            _buildSectionTitle(isDark, 'Recomendaciones', Icons.lightbulb_outline_rounded),
            const SizedBox(height: 12),
            _buildRecommendations(isDark),
          ],
        ],
      ),
    );
  }

  /// Card de resumen general con precision circular.
  Widget _buildSummaryCard(ErrorSummary summary, bool isDark) {
    final accuracyColor = summary.accuracyPct >= 70
        ? AppColors.success
        : summary.accuracyPct >= 50
            ? AppColors.warning
            : AppColors.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Precision circular
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatCircle(
                'Precision',
                '${summary.accuracyPct.toStringAsFixed(0)}%',
                accuracyColor,
              ),
              Column(
                children: [
                  _buildMiniStat('Correctas', '${summary.correct}', AppColors.success),
                  const SizedBox(height: 8),
                  _buildMiniStat('Incorrectas', '${summary.incorrect}', AppColors.error),
                  const SizedBox(height: 8),
                  _buildMiniStat('Sin responder', '${summary.unanswered}', AppColors.warning),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: isDark ? AppColors.darkBorder : AppColors.border),
          const SizedBox(height: 16),
          // Area mas debil y fuerte
          Row(
            children: [
              Expanded(
                child: _buildAreaTag(
                  'Mas debil',
                  summary.weakestArea,
                  AppColors.error,
                  Icons.trending_down_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAreaTag(
                  'Mas fuerte',
                  summary.strongestArea,
                  AppColors.success,
                  Icons.trending_up_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCircle(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 4),
          ),
          child: Center(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildAreaTag(String label, String area, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            area,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Card con tipos de error (lista con porcentajes).
  Widget _buildErrorTypesCard(bool isDark) {
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;

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
        children: _data!.errorTypes.map((err) {
          final color = _parseColor(err.color);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_getIcon(err.icon), size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        err.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${err.pct.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  err.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (err.pct / 100).clamp(0.0, 1.0),
                    backgroundColor: color.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Card con barras por area.
  Widget _buildByAreaCard(bool isDark) {
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;

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
        children: _data!.byArea.map((area) {
          final color = _parseColor(area.color);
          final correctPct = area.total > 0 ? area.correct / area.total : 0.0;
          final incorrectPct = area.total > 0 ? area.incorrect / area.total : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_getIcon(area.icon), size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        area.area,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${area.accuracy.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Barra dual: correctas (verde) + incorrectas (rojo)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        Expanded(
                          flex: (correctPct * 100).round(),
                          child: Container(color: AppColors.success),
                        ),
                        Expanded(
                          flex: (incorrectPct * 100).round(),
                          child: Container(color: AppColors.error),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${area.correct} correctas',
                      style: TextStyle(fontSize: 10, color: AppColors.success),
                    ),
                    const Spacer(),
                    Text(
                      '${area.incorrect} incorrectas',
                      style: TextStyle(fontSize: 10, color: AppColors.error),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Grafico de linea con la evolucion de precision.
  Widget _buildEvolutionChart(bool isDark) {
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textColor = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;
    final evolution = _data!.evolution;

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
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 25,
              getDrawingHorizontalLine: (v) => FlLine(
                color: textColor.withOpacity(0.1),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) => Text(
                    '${value.toInt()}%',
                    style: TextStyle(fontSize: 10, color: textColor),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 25,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= evolution.length) return const SizedBox.shrink();
                    final date = evolution[idx].date;
                    return Text(
                      date.length >= 5 ? date.substring(5) : date,
                      style: TextStyle(fontSize: 9, color: textColor),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            minY: 0,
            maxY: 100,
            lineBarsData: [
              LineChartBarData(
                spots: evolution.asMap().entries.map((e) {
                  return FlSpot(e.key.toDouble(), e.value.accuracy);
                }).toList(),
                isCurved: true,
                color: AppColors.primary,
                barWidth: 3,
                // 🔧 FIX #3: fl_chart 1.1.1 eliminó `dotColor`. Los puntos
                // se personalizan vía dotData.getDotPainter → FlDotCirclePainter.
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
                // 🔧 FIX: getTooltipItems debe devolver List<LineTooltipItem?>.
                getTooltipItems: (spots) {
                  return spots.map<LineTooltipItem?>((spot) {
                    final idx = spot.spotIndex;
                    if (idx < 0 || idx >= evolution.length) return null;
                    final point = evolution[idx];
                    return LineTooltipItem(
                      '${point.accuracy.toStringAsFixed(0)}%\n${point.errors} errores',
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
    );
  }

  /// Lista de recomendaciones.
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
                Icon(Icons.lightbulb_outline_rounded, size: 18, color: AppColors.warning),
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

  // ── Helpers ──

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
            const Icon(Icons.cloud_off_rounded, size: 64, color: AppColors.textDisabled),
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
            Icon(Icons.analytics_outlined, size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(
              'Aun no tienes datos de errores',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Completa al menos 1 simulacro para ver tu analisis de errores.',
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

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  IconData _getIcon(String name) {
    const map = {
      'menu_book_rounded': Icons.menu_book_rounded,
      'calculate_rounded': Icons.calculate_rounded,
      'public_rounded': Icons.public_rounded,
      'science_rounded': Icons.science_rounded,
      'translate_rounded': Icons.translate_rounded,
      'school_rounded': Icons.school_rounded,
      'timer_rounded': Icons.timer_rounded,
      'error_outline_rounded': Icons.error_outline_rounded,
      'extension_rounded': Icons.extension_rounded,
    };
    return map[name] ?? Icons.error_outline_rounded;
  }
}