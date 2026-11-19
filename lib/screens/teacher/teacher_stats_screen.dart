import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart' as sf;
import '../../services/auth_service.dart';
import '../../services/teacher_service.dart';
import '../../widgets/global_scaffold.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_logger.dart';

class TeacherStatsScreen extends StatefulWidget {
  const TeacherStatsScreen({Key? key}) : super(key: key);

  @override
  State<TeacherStatsScreen> createState() => _TeacherStatsScreenState();
}

class _TeacherStatsScreenState extends State<TeacherStatsScreen> {
  TeacherService get _teacherService => Provider.of<TeacherService>(context, listen: false);
  Map<String, dynamic> _stats = {};
  bool _loading = true;
  String? _selectedGrado;
  String? _selectedAnio;
  String _chartType = 'radar';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    
    final auth = Provider.of<AuthService>(context, listen: false);
    final colegio = auth.colegio ?? '';
    
    final gradosDynamic = auth.user?['grados_disponibles'] as List<dynamic>? ?? [];
    final List<String> grados = gradosDynamic.map((e) => e.toString()).toList();
    
    final aniosDynamic = auth.user?['anios_disponibles'] as List<dynamic>? ?? [];
    final List<String> anios = aniosDynamic.map((e) => e.toString()).toList();
    
    if (grados.isNotEmpty && _selectedGrado == null) {
      _selectedGrado = grados[0];
    }
    if (anios.isNotEmpty && _selectedAnio == null) {
      _selectedAnio = anios[0];
    }
    
    try {
      AppLogger.d('Cargando estadísticas con filtros: colegio=$colegio, grado=$_selectedGrado, anio=$_selectedAnio');
      
      _stats = await _teacherService.fetchGroupStats(colegio, _selectedGrado, _selectedAnio);
      
      AppLogger.d('Estadísticas cargadas: ${_stats.isNotEmpty ? "SI" : "NO"}');
      
      if (_stats.isEmpty) {
        AppLogger.d('No hay datos, usando muestra...');
        _stats = _getSampleStats();
      }
      
    } catch (e) {
      AppLogger.e('Error cargando estadísticas', e);
      _stats = _getSampleStats();
    } finally {
      setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _getSampleStats() {
    return {
      'total_estudiantes': 32,
      'total_simulacros': 156,
      'promedio_global': 78.4,
      'promedios_por_area': {
        'lectura': 85.2,
        'matematicas': 78.5,
        'sociales': 82.1,
        'naturales': 76.8,
        'ingles': 71.4,
      },
      'distribucion_puntajes': [
        {'rango': '0-200', 'cantidad': 2, 'color': '#EF4444'},
        {'rango': '201-300', 'cantidad': 5, 'color': '#F59E0B'},
        {'rango': '301-400', 'cantidad': 12, 'color': '#10B981'},
        {'rango': '401-500', 'cantidad': 10, 'color': '#1E4ED8'},
        {'rango': '501-600', 'cantidad': 3, 'color': '#8B5CF6'},
      ],
      'evolucion_mensual': [
        {'mes': 'Sep', 'promedio': 72.3, 'lectura': 78.1, 'matematicas': 70.2, 'sociales': 75.4, 'naturales': 68.9, 'ingles': 65.3},
        {'mes': 'Oct', 'promedio': 74.8, 'lectura': 80.3, 'matematicas': 73.1, 'sociales': 77.2, 'naturales': 71.5, 'ingles': 68.9},
        {'mes': 'Nov', 'promedio': 76.2, 'lectura': 82.7, 'matematicas': 75.8, 'sociales': 79.4, 'naturales': 73.8, 'ingles': 70.5},
        {'mes': 'Dic', 'promedio': 78.4, 'lectura': 85.2, 'matematicas': 78.5, 'sociales': 82.1, 'naturales': 76.8, 'ingles': 71.4},
      ],
      'mejores_estudiantes': [
        {'nombre': 'Ana Rodríguez', 'puntaje': 452, 'avatar': null},
        {'nombre': 'Carlos López', 'puntaje': 438, 'avatar': null},
        {'nombre': 'María González', 'puntaje': 425, 'avatar': null},
      ],
      'areas_mejorar': ['Inglés', 'Ciencias Naturales'],
      'tendencias': {
        'global': '+8.4%',
        'lectura': '+9.1%',
        'matematicas': '+11.8%',
        'sociales': '+8.9%',
        'naturales': '+11.5%',
        'ingles': '+9.3%',
      }
    };
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.surface.withOpacity(0.3)),
                ),
                child: Icon(Icons.analytics_rounded, color: AppColors.surface, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dashboard de Estadísticas',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Análisis avanzado del rendimiento académico',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.surface.withOpacity(0.9),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatMiniCard(
                  icon: Icons.people_alt_rounded,
                  value: _stats['total_estudiantes']?.toString() ?? '0',
                  label: 'Estudiantes',
                  trend: '+5%',
                ),
                const SizedBox(width: 10),
                _buildStatMiniCard(
                  icon: Icons.assignment_rounded,
                  value: _stats['total_simulacros']?.toString() ?? '0',
                  label: 'Simulacros',
                  trend: '+12%',
                ),
                const SizedBox(width: 10),
                _buildStatMiniCard(
                  icon: Icons.trending_up_rounded,
                  value: _stats['promedio_global']?.toStringAsFixed(1) ?? '0.0',
                  label: 'Promedio',
                  trend: _stats['tendencias']?['global']?.toString() ?? '+0%',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatMiniCard({
    required IconData icon,
    required String value,
    required String label,
    required String trend,
  }) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: 100,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surface.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.textOnPrimary, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textOnPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.surface.withOpacity(0.9),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  trend,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textOnPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final auth = Provider.of<AuthService>(context);
    
    final gradosDynamic = auth.user?['grados_disponibles'] as List<dynamic>? ?? [];
    final List<String> grados = gradosDynamic.map((e) => e.toString()).toList();
    
    final aniosDynamic = auth.user?['anios_disponibles'] as List<dynamic>? ?? [];
    final List<String> anios = aniosDynamic.map((e) => e.toString()).toList();

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filtros de análisis',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFilterDropdown(
                  label: 'Grado',
                  value: _selectedGrado,
                  items: grados,
                  onChanged: (value) {
                    setState(() => _selectedGrado = value);
                    _loadStats();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFilterDropdown(
                  label: 'Año',
                  value: _selectedAnio,
                  items: anios,
                  onChanged: (value) {
                    setState(() => _selectedAnio = value);
                    _loadStats();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildChartTypeSelector(),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceClean,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: Icon(Icons.arrow_drop_down_rounded, color: AppColors.textTertiary),
              hint: Text(
                'Seleccionar $label',
                style: TextStyle(color: AppColors.textDisabled),
              ),
              items: items.map((item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChartTypeSelector() {
    final options = {
      'radar': 'Gráfico de Radar',
      'areas': 'Barras por Área',
      'evolution': 'Evolución Mensual',
      'distribution': 'Distribución',
      'stacked': 'Barras Apiladas',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tipo de visualización',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.entries.map((entry) {
            final isSelected = _chartType == entry.key;
            return GestureDetector(
              onTap: () => setState(() => _chartType = entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.surfaceClean,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.textOnPrimary : AppColors.textTertiary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

Widget _buildRadarChart() {
  final promedios = _stats['promedios_por_area'] as Map<String, dynamic>? ?? {};
  
  if (promedios.isEmpty) {
    return _buildEmptyChart('No hay datos por áreas');
  }

  final areaNames = {
    'lectura': 'Lectura',
    'matematicas': 'Matem.', // Abreviado para ganar espacio si es necesario
    'sociales': 'Sociales',
    'naturales': 'Naturales',
    'ingles': 'Inglés',
  };

  final areaColors = {
    'lectura': AppColors.primary,
    'matematicas': AppColors.successDark,
    'sociales': AppColors.purple,
    'naturales': AppColors.warning,
    'ingles': AppColors.error,
  };

  final areas = areaNames.keys.where(promedios.containsKey).toList();
  final values = areas.map((area) => (promedios[area] as num).toDouble()).toList();

  return Container(
    // Aumentamos ligeramente el alto a 480 o lo dejamos flexible
    constraints: const BoxConstraints(minHeight: 450, maxHeight: 480),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), // Menos padding abajo
    decoration: BoxDecoration(
      color: AppColors.surface,
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
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, // Importante: ajustarse al contenido
      children: [
        const Text(
          'Rendimiento por Áreas',
          style: TextStyle(
            fontSize: 16, // Reducido de 18 a 16
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4), // Reducido de 8 a 4
        const Text(
          'Comparativa de promedios',
          style: TextStyle(
            fontSize: 11, // Reducido de 12 a 11
            color: AppColors.textTertiary,
          ),
        ),
        
        // El gráfico ahora está en un Flexible para que no "empuje" a la fuerza
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    dataEntries: values.map((value) => RadarEntry(value: value)).toList(),
                    fillColor: AppColors.primary.withOpacity(0.15),
                    borderColor: AppColors.primary,
                    borderWidth: 2,
                    entryRadius: 2, // Añadido para que los puntos no sean tan grandes
                  ),
                ],
                radarBackgroundColor: AppColors.surfaceVariant,
                radarBorderData: BorderSide(color: AppColors.border, width: 1),
                tickCount: 4, // Reducido de 5 a 4 ticks para limpiar la vista
                ticksTextStyle: TextStyle(color: AppColors.textDisabled, fontSize: 8),
                tickBorderData: BorderSide(color: AppColors.border, width: 0.5),
                radarShape: RadarShape.polygon,
                titleTextStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 9, // Reducido de 11 a 9 para evitar que los textos se salgan
                  fontWeight: FontWeight.w600,
                ),
                getTitle: (index, angle) {
                  if (index >= 0 && index < areas.length) {
                    return RadarChartTitle(
                      text: areaNames[areas[index]]!,
                      angle: angle,
                    );
                  }
                  return const RadarChartTitle(text: '');
                },
              ),
              swapAnimationDuration: const Duration(milliseconds: 400),
            ),
          ),
        ),
        
        // Separación controlada
        Divider(height: 20, thickness: 0.5),
        
        // Ajuste en la leyenda para que use Wrap en lugar de Row/Column rígido
        _buildCompactAreaLegend(areas, areaNames, areaColors, promedios),
      ],
    ),
  );
}

// Nueva función de leyenda más compacta y segura contra overflows
Widget _buildCompactAreaLegend(List<String> areas, Map<String, String> names, Map<String, Color> colors, Map promedios) {
  return Wrap(
    spacing: 12, // Espacio horizontal entre items
    runSpacing: 8, // Espacio vertical si salta de línea
    children: areas.map((area) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colors[area],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            "${names[area]}: ",
            style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
          ),
          Text(
            "${(promedios[area] as num).toStringAsFixed(1)}",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
          ),
        ],
      );
    }).toList(),
  );
}

  Widget _buildHorizontalAreaLegend(
    List<String> areas, 
    Map<String, String> areaNames, 
    Map<String, Color> areaColors, 
    Map<String, dynamic> promedios
  ) {
    return Container(
      height: 60,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Leyenda de áreas',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: areas.map((area) {
                  final promedio = (promedios[area] as num).toDouble();
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(
                      minWidth: 70,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: areaColors[area]!.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: areaColors[area]!.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: areaColors[area],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              areaNames[area]!,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.borderDark,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          promedio.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 12,
                            color: areaColors[area],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEvolutionChart() {
    final evolucionRaw = _stats['evolucion_mensual'] as List<dynamic>? ?? [];
    final List<Map<String, dynamic>> evolucion = evolucionRaw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (evolucion.isEmpty) {
      return _buildEmptyChart('No hay datos de evolución');
    }

    return Container(
      height: 350,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
          const Text(
            'Evolución Mensual por Área',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: sf.SfCartesianChart(
              primaryXAxis: sf.CategoryAxis(
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
              primaryYAxis: sf.NumericAxis(
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
                numberFormat: NumberFormat.decimalPattern(),
              ),
              series: <sf.LineSeries<Map<String, dynamic>, String>>[
                sf.LineSeries<Map<String, dynamic>, String>(
                  dataSource: evolucion,
                  xValueMapper: (data, _) => data['mes'] as String,
                  yValueMapper: (data, _) => (data['lectura'] as num?)?.toDouble(),
                  name: 'Lectura',
                  color: AppColors.primary,
                  width: 3,
                  markerSettings: const sf.MarkerSettings(isVisible: true),
                ),
                sf.LineSeries<Map<String, dynamic>, String>(
                  dataSource: evolucion,
                  xValueMapper: (data, _) => data['mes'] as String,
                  yValueMapper: (data, _) => (data['matematicas'] as num?)?.toDouble(),
                  name: 'Matemáticas',
                  color: AppColors.successDark,
                  width: 3,
                  markerSettings: const sf.MarkerSettings(isVisible: true),
                ),
                sf.LineSeries<Map<String, dynamic>, String>(
                  dataSource: evolucion,
                  xValueMapper: (data, _) => data['mes'] as String,
                  yValueMapper: (data, _) => (data['sociales'] as num?)?.toDouble(),
                  name: 'Sociales',
                  color: AppColors.purple,
                  width: 3,
                  markerSettings: const sf.MarkerSettings(isVisible: true),
                ),
                sf.LineSeries<Map<String, dynamic>, String>(
                  dataSource: evolucion,
                  xValueMapper: (data, _) => data['mes'] as String,
                  yValueMapper: (data, _) => (data['naturales'] as num?)?.toDouble(),
                  name: 'Naturales',
                  color: AppColors.warning,
                  width: 3,
                  markerSettings: const sf.MarkerSettings(isVisible: true),
                ),
                sf.LineSeries<Map<String, dynamic>, String>(
                  dataSource: evolucion,
                  xValueMapper: (data, _) => data['mes'] as String,
                  yValueMapper: (data, _) => (data['ingles'] as num?)?.toDouble(),
                  name: 'Inglés',
                  color: AppColors.error,
                  width: 3,
                  markerSettings: const sf.MarkerSettings(isVisible: true),
                ),
              ],
              tooltipBehavior: sf.TooltipBehavior(enable: true),
              legend: sf.Legend(
                isVisible: true,
                position: sf.LegendPosition.bottom,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAreasChart() {
    final promedios = _stats['promedios_por_area'] as Map<String, dynamic>? ?? {};
    
    if (promedios.isEmpty) {
      return _buildEmptyChart('No hay datos por áreas');
    }

    final areaNames = {
      'lectura': 'Lectura',
      'matematicas': 'Matemáticas',
      'sociales': 'Sociales',
      'naturales': 'Naturales',
      'ingles': 'Inglés',
    };

    final areaColors = {
      'lectura': AppColors.primary,
      'matematicas': AppColors.successDark,
      'sociales': AppColors.purple,
      'naturales': AppColors.warning,
      'ingles': AppColors.error,
    };

    final areas = areaNames.keys.where(promedios.containsKey).toList();
    final values = areas.map((area) => (promedios[area] as num).toDouble()).toList();

    return Container(
      height: 350,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
          const Text(
            'Rendimiento por Área',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: sf.SfCartesianChart(
              primaryXAxis: sf.CategoryAxis(
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
              primaryYAxis: sf.NumericAxis(
                minimum: 0,
                maximum: 100,
                interval: 20,
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
              series: <sf.BarSeries<Map<String, dynamic>, String>>[
                sf.BarSeries<Map<String, dynamic>, String>(
                  dataSource: List.generate(areas.length, (index) => {
                    'area': areaNames[areas[index]],
                    'valor': values[index],
                    'color': areaColors[areas[index]],
                  }),
                  xValueMapper: (data, _) => data['area'],
                  yValueMapper: (data, _) => data['valor'],
                  pointColorMapper: (data, _) => data['color'],
                  dataLabelSettings: const sf.DataLabelSettings(
                    isVisible: true,
                    labelAlignment: sf.ChartDataLabelAlignment.top,
                    textStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              tooltipBehavior: sf.TooltipBehavior(enable: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionChart() {
    final distribucionRaw = _stats['distribucion_puntajes'] as List<dynamic>? ?? [];
    final List<Map<String, dynamic>> distribucion = distribucionRaw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (distribucion.isEmpty) {
      return _buildEmptyChart('No hay datos de distribución');
    }

    return Container(
      height: 350,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
          const Text(
            'Distribución de Puntajes',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: sf.SfCircularChart(
              series: <sf.CircularSeries>[
                sf.PieSeries<Map<String, dynamic>, String>(
                  dataSource: distribucion,
                  xValueMapper: (data, _) => data['rango'] as String,
                  yValueMapper: (data, _) => (data['cantidad'] as num?)?.toDouble(),
                  pointColorMapper: (data, _) =>
                      _parseColor((data['color'] ?? '#64748B') as String),
                  dataLabelSettings: const sf.DataLabelSettings(
                    isVisible: true,
                    labelPosition: sf.ChartDataLabelPosition.outside,
                    textStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  explode: true,
                  explodeIndex: 0,
                ),
              ],
              legend: sf.Legend(
                isVisible: true,
                position: sf.LegendPosition.bottom,
              ),
              tooltipBehavior: sf.TooltipBehavior(enable: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStackedChart() {
    final evolucionRaw = _stats['evolucion_mensual'] as List<dynamic>? ?? [];
    final List<Map<String, dynamic>> evolucion = evolucionRaw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (evolucion.isEmpty) {
      return _buildEmptyChart('No hay datos para gráfico apilado');
    }

    return Container(
      height: 350,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
          const Text(
            'Composición por Área (Apilado)',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: sf.SfCartesianChart(
              primaryXAxis: sf.CategoryAxis(
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
              primaryYAxis: sf.NumericAxis(
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
                numberFormat: NumberFormat.decimalPattern(),
              ),
              series: <sf.StackedBarSeries<Map<String, dynamic>, String>>[
                sf.StackedBarSeries<Map<String, dynamic>, String>(
                  dataSource: evolucion,
                  xValueMapper: (data, _) => data['mes'] as String,
                  yValueMapper: (data, _) => (data['lectura'] as num?)?.toDouble(),
                  name: 'Lectura',
                  color: AppColors.primary,
                ),
                sf.StackedBarSeries<Map<String, dynamic>, String>(
                  dataSource: evolucion,
                  xValueMapper: (data, _) => data['mes'] as String,
                  yValueMapper: (data, _) => (data['matematicas'] as num?)?.toDouble(),
                  name: 'Matemáticas',
                  color: AppColors.successDark,
                ),
                sf.StackedBarSeries<Map<String, dynamic>, String>(
                  dataSource: evolucion,
                  xValueMapper: (data, _) => data['mes'] as String,
                  yValueMapper: (data, _) => (data['sociales'] as num?)?.toDouble(),
                  name: 'Sociales',
                  color: AppColors.purple,
                ),
                sf.StackedBarSeries<Map<String, dynamic>, String>(
                  dataSource: evolucion,
                  xValueMapper: (data, _) => data['mes'] as String,
                  yValueMapper: (data, _) => (data['naturales'] as num?)?.toDouble(),
                  name: 'Naturales',
                  color: AppColors.warning,
                ),
                sf.StackedBarSeries<Map<String, dynamic>, String>(
                  dataSource: evolucion,
                  xValueMapper: (data, _) => data['mes'] as String,
                  yValueMapper: (data, _) => (data['ingles'] as num?)?.toDouble(),
                  name: 'Inglés',
                  color: AppColors.error,
                ),
              ],
              tooltipBehavior: sf.TooltipBehavior(enable: true),
              legend: sf.Legend(
                isVisible: true,
                position: sf.LegendPosition.bottom,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChart(String message) {
    return Container(
      height: 350,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_rounded,
              color: AppColors.textDisabled,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String colorString) {
    try {
      final hexCode = colorString.replaceAll('#', '');
      return Color(int.parse('FF$hexCode', radix: 16));
    } catch (e) {
      return AppColors.textTertiary;
    }
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Text(
            'Cargando estadísticas...',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlobalScaffold(
      currentIndex: 2,
      body: _loading
          ? _buildLoadingState()
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildFilters(),
                  const SizedBox(height: 24),
                  
                  const Text(
                    'Visualización de Datos',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  if (_chartType == 'radar')
                    _buildRadarChart()
                  else if (_chartType == 'areas')
                    _buildAreasChart()
                  else if (_chartType == 'evolution')
                    _buildEvolutionChart()
                  else if (_chartType == 'distribution')
                    _buildDistributionChart()
                  else if (_chartType == 'stacked')
                    _buildStackedChart(),
                  
                  const SizedBox(height: 24),
                  _buildTopStudents(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildTopStudents() {
    final mejores = _stats['mejores_estudiantes'] as List<dynamic>? ?? [];
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top Estudiantes',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ...mejores.asMap().entries.map((entry) {
            final index = entry.key;
            final estudiante = entry.value as Map<String, dynamic>;
            return _buildTopStudentRow(estudiante, index + 1);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildTopStudentRow(Map<String, dynamic> estudiante, int position) {
    final colors = [
      AppColors.warning, // Oro
      AppColors.textDisabled, // Plata
      AppColors.warningDark, // Bronce
    ];
    
    final color = position <= 3 ? colors[position - 1] : AppColors.textTertiary;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceClean,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color),
            ),
            child: Center(
              child: Text(
                '$position',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  estudiante['nombre'] ?? 'Estudiante',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Puntaje: ${estudiante['puntaje'] ?? 0}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Top $position',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}