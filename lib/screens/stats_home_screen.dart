import '../config/env.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/summary_stats.dart';
import '../widgets/global_scaffold.dart';
import 'area_trend_screen.dart';
import 'comparativas_screen.dart';
import 'ranking_screen.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/theme/app_colors.dart';

class StatsHomeScreen extends StatefulWidget {
  const StatsHomeScreen({super.key});

  @override
  State<StatsHomeScreen> createState() => _StatsHomeScreenState();
}

class _StatsHomeScreenState extends State<StatsHomeScreen> {
  late Future<SummaryStats> _future;

  // Variables para la IA
  String? _aiRecommendation;
  bool _isLoadingAI = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<ApiService>().fetchSummaryStats();
  }

  Future<void> _reload() async {
    setState(() {
      _future = context.read<ApiService>().fetchSummaryStats();
    });
    await _future;
  }

  // Función para llamar a la IA (análisis global)
  Future<void> _fetchAIAnalysis(SummaryStats stats) async {
    setState(() => _isLoadingAI = true);

    try {
      final auth = context.read<AuthService>();
      final moodleIdValue = auth.moodleId ?? 1;

      final areasOrdenadas = stats.areas.entries
          .where((e) => e.value != null)
          .toList()
        ..sort((a, b) => b.value!.compareTo(a.value!));

      final mejorArea = areasOrdenadas.isNotEmpty ? areasOrdenadas.first.key : 'ninguna';
      final mejorPuntaje = areasOrdenadas.isNotEmpty ? areasOrdenadas.first.value : 0;
      final peorArea = areasOrdenadas.length > 1 ? areasOrdenadas.last.key : mejorArea;
      final peorPuntaje = areasOrdenadas.length > 1 ? areasOrdenadas.last.value : mejorPuntaje;

      String nivelProgreso = 'estable';
      if (stats.promedioGlobal != null) {
        if (stats.promedioGlobal! >= 80) nivelProgreso = 'excelente';
        else if (stats.promedioGlobal! >= 60) nivelProgreso = 'bueno';
        else if (stats.promedioGlobal! >= 40) nivelProgreso = 'regular';
        else nivelProgreso = 'necesita mejorar';
      }

      debugPrint('[IA Stats] Enviando análisis global para moodle_id: $moodleIdValue');

      final response = await http.post(
        Uri.parse(Env.aiApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'moodle_id': moodleIdValue,
          'mensaje': 'Analiza mi rendimiento general y dame un plan de acción personalizado para mejorar en todas las áreas.',
          'area_enfoque': 'global',
          'area_stats': {
            'promedio_global': stats.promedioGlobal?.toStringAsFixed(1) ?? '0',
            'simulacros_realizados': stats.simulacrosRealizados,
            'tiempo_promedio_seg': stats.tiempoPromedioSeg ?? 0,
            'mejor_area': _labelAreaShort(mejorArea),
            'mejor_puntaje': mejorPuntaje?.toStringAsFixed(1) ?? '0',
            'peor_area': _labelAreaShort(peorArea),
            'peor_puntaje': peorPuntaje?.toStringAsFixed(1) ?? '0',
            'nivel_progreso': nivelProgreso,
          }
        }),
      );

      debugPrint('[IA Stats] Respuesta código: ${response.statusCode}');

      if (response.statusCode == 200) {
        String rawBody = response.body;
        if (rawBody.startsWith('\uFEFF')) rawBody = rawBody.substring(1);
        if (rawBody.startsWith('ï»¿')) rawBody = rawBody.substring(3);
        rawBody = rawBody.trim();

        final jsonStart = rawBody.indexOf('{');
        if (jsonStart != -1 && jsonStart > 0) {
          rawBody = rawBody.substring(jsonStart);
        }

        final data = jsonDecode(rawBody);
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
      debugPrint('[IA Stats] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ Error con la IA: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingAI = false);
    }
  }

  Widget _buildLoading() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildError(String error) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.errorFaint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                color: AppColors.errorDark,
                size: 48,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Error cargando estadísticas',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                error,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _reload,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'Reintentar',
                style: TextStyle(color: AppColors.textOnPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtScore(double? v) => v != null ? '${v.toStringAsFixed(1)}' : '—';

  String _fmtTime(int? s) =>
      s == null ? '—' : '${(s / 60).floor()}m ${s % 60}s';

  int _areasConDatos(Map<String, double?> areas) =>
      areas.values.where((v) => v != null).length;

  // 🔥 VERSIÓN CORTA para botones y espacios pequeños
  String _labelAreaShort(String key) {
    const map = {
      'lectura': 'Lectura',
      'matematicas': 'Matemáticas',
      'sociales': 'Sociales',
      'naturales': 'Naturales',
      'ingles': 'Inglés',
    };
    return map[key] ?? key;
  }

  // 🔥 VERSIÓN LARGA para títulos donde quepa
  String _labelAreaLong(String key) {
    const map = {
      'lectura': 'Lectura Crítica',
      'matematicas': 'Matemáticas',
      'sociales': 'Sociales y Ciudadanas',
      'naturales': 'Ciencias Naturales',
      'ingles': 'Inglés',
    };
    return map[key] ?? key;
  }

  Widget _buildHeader(SummaryStats s) {
    final fecha = s.ultimaFecha != null
        ? '${s.ultimaFecha!.day.toString().padLeft(2, '0')}/${s.ultimaFecha!.month.toString().padLeft(2, '0')}/${s.ultimaFecha!.year}'
        : '—';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.analytics_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Simulacros realizados: ${s.simulacrosRealizados}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Última fecha: $fecha',
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
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
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
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.3), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 2),
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAreasGrid(Map<String, double?> areas) {
    final ordenadas = areas.entries.where((e) => e.value != null).toList()
      ..sort((a, b) => b.value!.compareTo(a.value!));

    return Container(
      padding: const EdgeInsets.all(12),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Puntajes por área',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            padding: EdgeInsets.zero,
            children: ordenadas.map((entry) {
              final area = entry.key;
              final score = entry.value;
              final isTop = ordenadas.indexOf(entry) == 0;
              
              IconData icon;
              Color color;
              
              switch (area) {
                case 'lectura':
                  icon = Icons.menu_book_rounded;
                  color = AppColors.primary;
                  break;
                case 'matematicas':
                  icon = Icons.calculate_rounded;
                  color = AppColors.successDark;
                  break;
                case 'sociales':
                  icon = Icons.public_rounded;
                  color = AppColors.purple;
                  break;
                case 'naturales':
                  icon = Icons.eco_rounded;
                  color = AppColors.warning;
                  break;
                case 'ingles':
                  icon = Icons.language_rounded;
                  color = AppColors.error;
                  break;
                default:
                  icon = Icons.category_rounded;
                  color = AppColors.textTertiary;
              }

              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isTop ? color : AppColors.border,
                    width: isTop ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowMd,
                      blurRadius: isTop ? 6 : 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: color, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _labelAreaShort(area), // 🔥 Usa versión corta
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isTop ? color : AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            score != null ? score.toStringAsFixed(1) : '—',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isTop)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'TOP',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAreaSelector(Map<String, double?> areas) {
    final areasConDatos = areas.entries.where((e) => e.value != null).toList();

    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Evolución por área',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: areasConDatos.map((entry) {
              final area = entry.key;
              final icon = _getAreaIcon(area);
              final color = _getAreaColor(area);

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AreaTrendScreen(area: area),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.3), width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: color, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        _labelAreaShort(area), // 🔥 Usa versión corta
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.trending_up_rounded,
                        color: color,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildExtraAccessButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Explora más estadísticas',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Análisis avanzados y comparativas',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildAccessButton(
                  icon: Icons.compare_arrows_rounded,
                  label: 'Comparativas',
                  color: AppColors.purple,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ComparativasScreen(
                          area: 'global',
                          scope: 'national',
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAccessButton(
                  icon: Icons.leaderboard_rounded,
                  label: 'Ranking',
                  color: AppColors.successDark,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RankingScreen(
                          area: 'global',
                          scope: 'national',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAccessButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: AppColors.textOnPrimary, size: 22),
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 🔥 SECCIÓN DE IA CORREGIDA con Flexible para evitar overflow
  Widget _buildIACard(SummaryStats stats) {
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
                  color: AppColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent.withOpacity(0.3), width: 1.5),
                ),
                child: Icon(Icons.auto_awesome, color: AppColors.accent, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Saber+ IA',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      'Análisis personalizado de tu rendimiento',
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
          
          const SizedBox(height: 20),
          Divider(color: AppColors.border),
          const SizedBox(height: 20),

          // 🔥 Botón de IA CORREGIDO con Flexible
          if (_aiRecommendation == null && !_isLoadingAI)
            GestureDetector(
              onTap: () => _fetchAIAnalysis(stats),
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

          // 🔥 Estado de carga CORREGIDO con Flexible
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
                children: const [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Saber+ IA está analizando tu rendimiento...',
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
        return Icons.category_rounded;
    }
  }

  Color _getAreaColor(String area) {
    switch (area) {
      case 'lectura':
        return AppColors.primary;
      case 'matematicas':
        return AppColors.successDark;
      case 'sociales':
        return AppColors.purple;
      case 'naturales':
        return AppColors.warning;
      case 'ingles':
        return AppColors.error;
      default:
        return AppColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final userName = (auth.nombre ?? 'Usuario').split(' ').first;
    final avatarUrl = auth.avatarUrl;

    return FutureBuilder<SummaryStats>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _buildLoading();
        }

        if (snap.hasError) {
          return _buildError(snap.error.toString());
        }

        if (!snap.hasData) {
          return _buildError('No se encontraron datos');
        }

        final s = snap.data!;

        return GlobalScaffold(
          currentIndex: 2,
          body: Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: RefreshIndicator(
                onRefresh: _reload,
                color: AppColors.primary,
                backgroundColor: AppColors.surface,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header con usuario
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
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
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.border,
                                  width: 2,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 26,
                                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                    ? NetworkImage(avatarUrl)
                                    : const AssetImage('assets/avatars/default.png')
                                        as ImageProvider,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '¡Hola, $userName!',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Aquí tienes tus estadísticas de aprendizaje',
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
                      ),

                      const SizedBox(height: 24),

                      // Información general
                      _buildHeader(s),

                      const SizedBox(height: 24),

                      // KPIs principales
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        childAspectRatio: 0.9,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        children: [
                          _buildKpiCard(
                            'Promedio global',
                            _fmtScore(s.promedioGlobal),
                            Icons.bar_chart_rounded,
                            AppColors.primary,
                          ),
                          _buildKpiCard(
                            'Tiempo promedio',
                            _fmtTime(s.tiempoPromedioSeg),
                            Icons.access_time_rounded,
                            AppColors.successDark,
                          ),
                          _buildKpiCard(
                            'Áreas con datos',
                            _areasConDatos(s.areas).toString(),
                            Icons.layers_rounded,
                            AppColors.purple,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // 🔥 TARJETA DE IA (CORREGIDA)
                      _buildIACard(s),

                      const SizedBox(height: 24),

                      // Puntajes por área
                      _buildAreasGrid(s.areas),

                      const SizedBox(height: 24),

                      // Evolución por área
                      _buildAreaSelector(s.areas),

                      const SizedBox(height: 24),

                      // Acceso a más estadísticas
                      _buildExtraAccessButtons(),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}