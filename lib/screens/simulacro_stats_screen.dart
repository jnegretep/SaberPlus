import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../widgets/area_bar_chart.dart';
import '../widgets/area_radar_chart.dart';
import '../core/theme/app_colors.dart';
// ELIMINADO: import '../widgets/ranking_bar_chart.dart';

class SimulacroStatsScreen extends StatefulWidget {
  final int simulacroId;
  final int courseId;
  final ApiService api;

  const SimulacroStatsScreen({
    Key? key,
    required this.simulacroId,
    required this.courseId,
    required this.api,
  }) : super(key: key);

  @override
  State<SimulacroStatsScreen> createState() => _SimulacroStatsScreenState();
}

class _SimulacroStatsScreenState extends State<SimulacroStatsScreen> {
  bool _loading = true;
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _ranking;
  String _selectedScope = "colegio";
  int _selectedChartView = 0; // 0 = Barras, 1 = Radar

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);

    try {
      final stats = await widget.api.fetchSimulacroStats(widget.simulacroId);
      final ranking = await widget.api.fetchSimulacroRanking(widget.simulacroId);

      setState(() {
        _stats = stats;
        _ranking = ranking;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error cargando estadísticas: $e"),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Convertir valores a double de manera segura
  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  // Obtener el label del ámbito seleccionado
  String _getScopeLabel() {
    switch (_selectedScope) {
      case "colegio":
        return "del Colegio";
      case "ciudad":
        return "de la Ciudad";
      case "departamento":
        return "del Departamento";
      case "nacional":
        return "Nacional";
      default:
        return "";
    }
  }

  // Tarjeta de puntaje por área optimizada
  Widget _buildAreaScoreCard(String title, double? value, IconData icon) {
    return Container(
      width: double.infinity,
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value == null ? "—" : value.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Tarjeta de posición en ranking
  Widget _buildRankingPositionCard(String title, int? rank, IconData icon) {
    final hasRank = rank != null && rank > 0;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMd,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: hasRank ? AppColors.surfaceVariant : AppColors.errorFaint,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              color: hasRank ? AppColors.primary : AppColors.errorDark,
              size: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            rank == null ? "—" : "#$rank",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: hasRank ? AppColors.primary : AppColors.errorDark,
            ),
          ),
        ],
      ),
    );
  }

  // Selector de ámbito de comparación
  Widget _buildScopeSelector() {
    final Map<String, String> scopeLabels = {
      "colegio": "Colegio",
      "ciudad": "Ciudad",
      "departamento": "Departamento",
      "nacional": "Nacional",
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
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
            'Comparar con promedio:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: scopeLabels.entries.map((entry) {
              final isSelected = _selectedScope == entry.key;
              return GestureDetector(
                onTap: () => setState(() => _selectedScope = entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.surfaceClean,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.textOnPrimary : AppColors.textTertiary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // Selector de vista de gráfico
// Selector de vista de gráfico
Widget _buildChartViewSelector() {
  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedChartView = 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _selectedChartView == 0 ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedChartView == 0 ? AppColors.primary : AppColors.border,
                  width: 2,
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  children: [
                    Icon(
                      Icons.bar_chart,
                      color: _selectedChartView == 0 ? AppColors.textOnPrimary : AppColors.textTertiary,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Vista de Barras',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _selectedChartView == 0 ? AppColors.textOnPrimary : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedChartView = 1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _selectedChartView == 1 ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedChartView == 1 ? AppColors.primary : AppColors.border,
                  width: 2,
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  children: [
                    Icon(
                      Icons.polyline,
                      color: _selectedChartView == 1 ? AppColors.textOnPrimary : AppColors.textTertiary,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Vista de Radar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _selectedChartView == 1 ? AppColors.textOnPrimary : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    final user = _stats?["user"];
    final stats = _stats?["stats"];
    final ranking = _ranking?["user"];
    final top = _ranking?["top"];

    final scopeStats = stats != null ? stats[_selectedScope] : null;

    if (user == null || stats == null) {
      return _buildNoDataScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
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
                  const Text(
                    'Estadísticas del Simulacro',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Contenido
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadAll,
                color: AppColors.primary,
                backgroundColor: AppColors.surface,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Puntaje global destacado
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tu Puntaje Global',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textOnPrimarySubtle,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _toDouble(user["puntaje_global"]).toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textOnPrimary,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.surface.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today_rounded,
                                    size: 14,
                                    color: AppColors.textOnPrimarySubtle,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    user["fecha_realizacion"] ?? "—",
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textOnPrimarySubtle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Puntajes por área
                      const Text(
                        'Puntajes por Área',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),

                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        childAspectRatio: 1.8,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        children: [
                          _buildAreaScoreCard(
                            "Lectura",
                            _toDouble(user["lectura_puntaje"]),
                            Icons.menu_book_rounded,
                          ),
                          _buildAreaScoreCard(
                            "Matemáticas",
                            _toDouble(user["matematicas_puntaje"]),
                            Icons.calculate_rounded,
                          ),
                          _buildAreaScoreCard(
                            "Sociales",
                            _toDouble(user["sociales_puntaje"]),
                            Icons.public_rounded,
                          ),
                          _buildAreaScoreCard(
                            "Naturales",
                            _toDouble(user["naturales_puntaje"]),
                            Icons.eco_rounded,
                          ),
                          _buildAreaScoreCard(
                            "Inglés",
                            _toDouble(user["ingles_puntaje"]),
                            Icons.language_rounded,
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Selector de ámbito
                      _buildScopeSelector(),

                      const SizedBox(height: 24),

                      // Comparación con promedios
                      if (scopeStats != null) ...[
                        const Text(
                          'Comparación de Desempeño',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Selector de vista de gráfico
                        _buildChartViewSelector(),

                        Container(
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
                          constraints: const BoxConstraints(
                            minHeight: 350,
                          ),
                          child: _selectedChartView == 0
                              ? AreaBarChart(
                                  user: {
                                    "Lectura": _toDouble(user["lectura_puntaje"]),
                                    "Matemáticas": _toDouble(user["matematicas_puntaje"]),
                                    "Sociales": _toDouble(user["sociales_puntaje"]),
                                    "Naturales": _toDouble(user["naturales_puntaje"]),
                                    "Inglés": _toDouble(user["ingles_puntaje"]),
                                  },
                                  avg: {
                                    "Lectura": _toDouble(scopeStats["lectura_puntaje"]),
                                    "Matemáticas": _toDouble(scopeStats["matematicas_puntaje"]),
                                    "Sociales": _toDouble(scopeStats["sociales_puntaje"]),
                                    "Naturales": _toDouble(scopeStats["naturales_puntaje"]),
                                    "Inglés": _toDouble(scopeStats["ingles_puntaje"]),
                                  },
                                  scopeLabel: _getScopeLabel(),
                                  useAbbreviations: true,
                                )
                              : AreaRadarChart(
                                  user: {
                                    "Lectura": _toDouble(user["lectura_puntaje"]),
                                    "Matemáticas": _toDouble(user["matematicas_puntaje"]),
                                    "Sociales": _toDouble(user["sociales_puntaje"]),
                                    "Naturales": _toDouble(user["naturales_puntaje"]),
                                    "Inglés": _toDouble(user["ingles_puntaje"]),
                                  },
                                  avg: {
                                    "Lectura": _toDouble(scopeStats["lectura_puntaje"]),
                                    "Matemáticas": _toDouble(scopeStats["matematicas_puntaje"]),
                                    "Sociales": _toDouble(scopeStats["sociales_puntaje"]),
                                    "Naturales": _toDouble(scopeStats["naturales_puntaje"]),
                                    "Inglés": _toDouble(scopeStats["ingles_puntaje"]),
                                  },
                                  scopeLabel: _getScopeLabel(),
                                  useAbbreviations: true,
                                ),
                        ),

                        const SizedBox(height: 24),
                      ],

                      // Ranking por ámbitos (solo tarjetas)
                      if (ranking != null) ...[
                        const Text(
                          'Tu Posición en el Ranking',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ELIMINADO: Gráfico de barras de ranking
                        // MANTENIDO: Tarjetas de posición
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 2,
                          childAspectRatio: 1.3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          children: [
                            _buildRankingPositionCard(
                              "Colegio",
                              ranking["colegio_rank"],
                              Icons.school_rounded,
                            ),
                            _buildRankingPositionCard(
                              "Ciudad",
                              ranking["ciudad_rank"],
                              Icons.location_city_rounded,
                            ),
                            _buildRankingPositionCard(
                              "Departamento",
                              ranking["departamento_rank"],
                              Icons.map_rounded,
                            ),
                            _buildRankingPositionCard(
                              "Nacional",
                              ranking["nacional_rank"],
                              Icons.flag_rounded,
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                      ],

                      // Top 10 estudiantes
                      if (top != null && top[_selectedScope] != null) ...[
                        const Text(
                          'Top 10 Estudiantes',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        Container(
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
                            children: (top[_selectedScope] as List)
                                .asMap()
                                .entries
                                .take(10)
                                .map((entry) => _buildTopStudentCard(entry.key, entry.value))
                                .toList(),
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopStudentCard(int index, Map<String, dynamic> student) {
    final score = _toDouble(student["puntaje_global"]);
    final isTop3 = index < 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMd,
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isTop3 ? AppColors.primary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                "${index + 1}",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isTop3 ? AppColors.textOnPrimary : AppColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  student["nombre"]?.toString().split(" ").first ?? "Estudiante",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  "Puntaje: ${score.toStringAsFixed(1)}",
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              score.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
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
                  const Text(
                    'Estadísticas del Simulacro',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
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
                          Icons.bar_chart_outlined,
                          color: AppColors.textDisabled,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No hay estadísticas disponibles',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.borderDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Completa el simulacro para ver tus estadísticas',
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
            ),
          ],
        ),
      ),
    );
  }
}