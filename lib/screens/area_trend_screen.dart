import '../config/env.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/area_trend_point.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/theme/app_colors.dart';

class AreaTrendScreen extends StatefulWidget {
  final String area;
  const AreaTrendScreen({super.key, required this.area});

  @override
  State<AreaTrendScreen> createState() => _AreaTrendScreenState();
}

class _AreaTrendScreenState extends State<AreaTrendScreen> {
  late Future<List<AreaTrendPoint>> _future;
  final ScrollController _horizontalScrollController = ScrollController();

  // Variables para la IA
  String? _aiRecommendation;
  bool _isLoadingAI = false;

  Future<void> _fetchAIAnalysis(List<AreaTrendPoint> points) async {
    setState(() => _isLoadingAI = true);
    
    final validScores = points.where((p) => p.puntaje != null).map((p) => p.puntaje!).toList();
    final avg = validScores.isNotEmpty ? validScores.reduce((a, b) => a + b) / validScores.length : 0;
    final best = validScores.isNotEmpty ? validScores.reduce((a, b) => a > b ? a : b) : 0;
    
    double tendencia = 0;
    if (validScores.length >= 2) {
      final ultimo = validScores.last;
      final anteriores = validScores.sublist(0, validScores.length - 1);
      final promAnterior = anteriores.reduce((a, b) => a + b) / anteriores.length;
      tendencia = ultimo - promAnterior;
    }

    try {
      final auth = context.read<AuthService>();
      final moodleIdValue = auth.moodleId ?? 1;
      
      debugPrint('[IA] Enviando análisis para moodle_id: $moodleIdValue');
      
      final response = await http.post(
        Uri.parse(Env.aiApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'moodle_id': moodleIdValue,
          'mensaje': 'Analiza mi rendimiento en ${_labelAreaShort(widget.area)} y dame mi plan de acción.',
          'area_enfoque': widget.area,
          'area_stats': {
            'promedio': avg.toStringAsFixed(1),
            'tendencia': tendencia.toStringAsFixed(1),
            'mejor': best.toStringAsFixed(1),
          }
        }),
      );

      debugPrint('[IA] Respuesta código: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['exito'] == true) {
          setState(() {
            _aiRecommendation = data['respuesta'];
          });
        } else {
          throw Exception(data['mensaje'] ?? 'Error desconocido de la IA');
        }
      } else {
        throw Exception('Error HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[IA] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Error con la IA: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingAI = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiService>();
    _future = api.fetchAreaTrend(widget.area);
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  // 🔥 CORREGIDO: Versión corta para títulos y botones
  String _labelAreaShort(String key) {
    switch (key) {
      case 'lectura':
        return 'Lectura';
      case 'matematicas':
        return 'Matemáticas';
      case 'sociales':
        return 'Sociales';  // 🔥 CORREGIDO: Version corta
      case 'naturales':
        return 'Naturales';
      case 'ingles':
        return 'Inglés';
      default:
        return key;
    }
  }

  // 🔥 NUEVO: Versión larga solo para detalles donde quepa
  String _labelAreaLong(String key) {
    switch (key) {
      case 'lectura':
        return 'Lectura crítica';
      case 'matematicas':
        return 'Matemáticas';
      case 'sociales':
        return 'Sociales y ciudadanas';
      case 'naturales':
        return 'Ciencias naturales';
      case 'ingles':
        return 'Inglés';
      default:
        return key;
    }
  }

  IconData _getAreaIcon(String area) {
    switch (area) {
      case 'lectura':
        return Icons.menu_book_rounded;
      case 'matematicas':
        return Icons.calculate_rounded;
      case 'sociales':
        return Icons.public_rounded;
      case 'naturales':
        return Icons.eco_rounded;
      case 'ingles':
        return Icons.language_rounded;
      default:
        return Icons.trending_up_rounded;
    }
  }

  Color _getAreaColor(String area) {
    switch (area) {
      case 'lectura':
        return AppColors.primary;
      case 'matematicas':
        return AppColors.primaryLight;
      case 'sociales':
        return AppColors.successDark;
      case 'naturales':
        return AppColors.purple;
      case 'ingles':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  Widget _buildStatsCard(List<AreaTrendPoint> points) {
    final validScores = points.where((p) => p.puntaje != null).map((p) => p.puntaje!).toList();
    final avg = validScores.isNotEmpty
        ? validScores.reduce((a, b) => a + b) / validScores.length
        : 0;
    
    final lastScore = points.isNotEmpty && points.last.puntaje != null
        ? points.last.puntaje!
        : 0;
    
    final bestScore = validScores.isNotEmpty
        ? validScores.reduce((a, b) => a > b ? a : b)
        : 0;
    
    final int totalSimulacros = points.length;
    final int completados = validScores.length;
    
    double tendencia = 0;
    if (validScores.length >= 2) {
      final ultimoValor = lastScore;
      final promedioAnterior = (validScores.reduce((a, b) => a + b) - ultimoValor) / (validScores.length - 1);
      tendencia = ultimoValor - promedioAnterior;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getAreaColor(widget.area).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _getAreaColor(widget.area).withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  _getAreaIcon(widget.area),
                  color: _getAreaColor(widget.area),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Evolución en ${_labelAreaShort(widget.area)}', // 🔥 CORREGIDO: Usa versión corta
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$completados de $totalSimulacros completados',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          Divider(color: AppColors.border),
          const SizedBox(height: 12),
          
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            padding: EdgeInsets.zero,
            children: [
              _buildStatItem(
                title: 'Puntaje promedio',
                value: avg.toStringAsFixed(1),
                icon: Icons.bar_chart_rounded,
                color: AppColors.primary,
              ),
              _buildStatItem(
                title: 'Último puntaje',
                value: lastScore.toStringAsFixed(1),
                icon: Icons.timeline_rounded,
                color: AppColors.successDark,
              ),
              _buildStatItem(
                title: 'Mejor puntaje',
                value: bestScore.toStringAsFixed(1),
                icon: Icons.emoji_events_rounded,
                color: AppColors.warning,
              ),
              _buildStatItem(
                title: 'Tendencia',
                value: '${tendencia >= 0 ? '+' : ''}${tendencia.toStringAsFixed(1)}',
                icon: tendencia >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                color: tendencia >= 0 ? AppColors.successDark : AppColors.error,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceClean,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart(List<AreaTrendPoint> points) {
    final needScroll = points.length > 5;
    final chartWidth = needScroll
        ? points.length * 90.0
        : max(MediaQuery.of(context).size.width - 48, points.length * 90.0);

    const maxY = 110.0;
    final areaColor = _getAreaColor(widget.area);

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Evolución del puntaje',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Progreso en los últimos simulacros',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          
          SizedBox(
            height: 250,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: chartWidth,
                child: BarChart(
                  BarChartData(
                    maxY: maxY,
                    alignment: BarChartAlignment.spaceAround,
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final p = points[groupIndex];
                          return BarTooltipItem(
                            'Simulacro ${groupIndex + 1}\n${p.fecha.day}/${p.fecha.month}/${p.fecha.year}\nPuntaje: ${p.puntaje?.toStringAsFixed(1) ?? "N/A"}',
                            TextStyle(
                              color: AppColors.textOnPrimary,
                              fontSize: 12,
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
                          interval: 20,
                          reservedSize: 36,
                          getTitlesWidget: (value, meta) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                value.toInt().toString(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textTertiary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 42,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= points.length) {
                              return const SizedBox();
                            }

                            final fecha = points[idx].fecha;
                            final hasScore = points[idx].puntaje != null;

                            return SizedBox(
                              width: 40,
                              height: 42,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    margin: const EdgeInsets.only(bottom: 2),
                                    decoration: BoxDecoration(
                                      color: hasScore ? areaColor.withOpacity(0.1) : AppColors.surfaceVariant,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: hasScore ? areaColor : AppColors.border,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${idx + 1}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: hasScore ? areaColor : AppColors.textDisabled,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    height: 12,
                                    alignment: Alignment.center,
                                    child: Text(
                                      '${fecha.day}/${fecha.month}',
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: AppColors.textTertiary,
                                        height: 1.0,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                    ),
                                  ),
                                ],
                              ),
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
                    gridData: FlGridData(
                      show: true,
                      horizontalInterval: 20,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) {
                        return FlLine(
                          color: AppColors.surfaceVariant,
                          strokeWidth: 1,
                          dashArray: value % 20 == 0 ? null : [4, 4],
                        );
                      },
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(
                        color: AppColors.border,
                        width: 1,
                      ),
                    ),
                    barGroups: [
                      for (int i = 0; i < points.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: points[i].puntaje ?? 0,
                              width: 20,
                              color: points[i].puntaje != null
                                  ? areaColor
                                  : AppColors.border,
                              borderRadius: BorderRadius.circular(6),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: maxY,
                                color: AppColors.surfaceClean,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  swapAnimationDuration: const Duration(milliseconds: 700),
                  swapAnimationCurve: Curves.easeOutCubic,
                ),
              ),
            ),
          ),
          
          if (needScroll)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.swipe_rounded,
                    color: AppColors.textDisabled,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Desliza para ver más simulacros',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSimulacrosTable(List<AreaTrendPoint> points) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Historial de simulacros',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Detalle por intento',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceClean,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  child: Text(
                    '#',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Fecha',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Puntaje',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Estado',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 6),
          
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: min(points.length, 10),
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final point = points[index];
              final hasScore = point.puntaje != null;
              final score = point.puntaje ?? 0;
              
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.surfaceVariant),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowMd,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.borderDark,
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    Expanded(
                      flex: 3,
                      child: Text(
                        '${point.fecha.day}/${point.fecha.month}/${point.fecha.year}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    Expanded(
                      flex: 2,
                      child: hasScore
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getAreaColor(widget.area).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                score.toStringAsFixed(1),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _getAreaColor(widget.area),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : Text(
                              'N/A',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textDisabled,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                    ),
                    
                    const SizedBox(width: 8),
                    
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          Icon(
                            hasScore ? Icons.check_circle_rounded : Icons.pending_rounded,
                            size: 14,
                            color: hasScore ? AppColors.successDark : AppColors.warning,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              hasScore ? 'Completado' : 'Pendiente',
                              style: TextStyle(
                                fontSize: 11,
                                color: hasScore ? AppColors.successDark : AppColors.warning,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendations(List<AreaTrendPoint> points) {
    final validScores = points.where((p) => p.puntaje != null).map((p) => p.puntaje!).toList();
    final avg = validScores.isNotEmpty
        ? validScores.reduce((a, b) => a + b) / validScores.length
        : 0;
    
    String titulo;
    String mensaje;
    IconData icon;
    Color color;
    List<String> acciones = [];

    if (avg < 50) {
      titulo = 'Necesitas reforzar esta área';
      mensaje = 'Tu desempeño indica que necesitas práctica adicional para mejorar tus habilidades.';
      icon = Icons.warning_amber_rounded;
      color = AppColors.error;
      acciones = [
        'Revisa las lecciones teóricas de ${_labelAreaShort(widget.area)}',
        'Practica con ejercicios específicos del área',
        'Solicita ayuda a tu tutor en temas difíciles',
        'Realiza al menos 2 simulacros más esta semana'
      ];
    } else if (avg < 80) {
      titulo = 'Buen progreso, sigue mejorando';
      mensaje = 'Vas por buen camino, pero aún hay margen de mejora para alcanzar la excelencia.';
      icon = Icons.trending_up_rounded;
      color = AppColors.warning;
      acciones = [
        'Identifica los temas donde tienes más errores',
        'Repasa los conceptos clave de ${_labelAreaShort(widget.area)}',
        'Participa en sesiones de refuerzo grupales',
        'Establece metas semanales de mejora'
      ];
    } else {
      titulo = 'Excelente desempeño';
      mensaje = 'Has demostrado dominio en esta área. Ahora puedes enfocarte en mantener tu nivel y apoyar a otros.';
      icon = Icons.emoji_events_rounded;
      color = AppColors.successDark;
      acciones = [
        'Mantén tu rutina de práctica constante',
        'Ayuda a compañeros con dificultades en ${_labelAreaShort(widget.area)}',
        'Explora temas avanzados del área',
        'Prepara material de repaso para otros'
      ];
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    Text(
                      'Recomendaciones personalizadas',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          Divider(color: AppColors.border),
          const SizedBox(height: 16),
          
          Text(
            mensaje,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.borderDark,
              height: 1.5,
            ),
          ),
          
          const SizedBox(height: 20),
          
          const Text(
            'Acciones recomendadas:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          
          const SizedBox(height: 12),
          
          ...acciones.asMap().entries.map((entry) {
            final index = entry.key;
            final accion = entry.value;
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      accion,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.borderDark,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          
          const SizedBox(height: 24),

          // 🔥 CORREGIDO: Botón de IA con mejor manejo de espacio
          if (_aiRecommendation == null && !_isLoadingAI)
            GestureDetector(
              onTap: () => _fetchAIAnalysis(points),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.accent.withOpacity(0.4), width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.auto_awesome, color: AppColors.accent, size: 20),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'Generar análisis con Saber+ IA',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 🔥 CORREGIDO: Estado de carga de IA - Ahora con Expanded y Flexible
          if (_isLoadingAI)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceClean,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
                  const SizedBox(width: 12),
                  const Flexible(  // 🔥 CORREGIDO: Agregado Flexible para evitar overflow
                    child: Text(
                      'Saber+ IA está analizando tu tendencia...',
                      style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          if (_aiRecommendation != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: AppColors.textSecondary,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textSecondary.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.auto_awesome, color: AppColors.accent, size: 16),
                      SizedBox(width: 6),
                      Text('Análisis de Saber+ IA', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    _aiRecommendation!,
                    style: TextStyle(color: AppColors.textOnPrimary, fontSize: 14, height: 1.5),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FutureBuilder<List<AreaTrendPoint>>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              );
            }
            
            if (snap.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.error,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Error al cargar datos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.borderDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snap.error}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            final points = snap.data!;
            if (points.isEmpty) {
              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowSm,
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: AppColors.textSecondary,
                            size: 24,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(  // 🔥 CORREGIDO: Agregado Expanded
                          child: Text(
                            'Evolución en ${_labelAreaShort(widget.area)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _getAreaIcon(widget.area),
                              color: AppColors.textDisabled,
                              size: 56,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Aún no hay datos de evolución',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.borderDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Completa algunos simulacros para ver tu progreso',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textTertiary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadowSm,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.textSecondary,
                          size: 24,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(  // 🔥 CORREGIDO: Agregado Expanded
                        child: Text(
                          'Evolución en ${_labelAreaShort(widget.area)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildStatsCard(points),
                        const SizedBox(height: 20),
                        _buildTrendChart(points),
                        const SizedBox(height: 20),
                        _buildSimulacrosTable(points),
                        const SizedBox(height: 20),
                        _buildRecommendations(points),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}