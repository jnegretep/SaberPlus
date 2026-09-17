// lib/screens/teacher/teacher_dashboard_screen.dart
// Saber+ - Panel de Docentes (Redisenio Profesional)
//
// Mejoras:
// - Cards de estadisticas con numeros en tiempo real
// - Accesos rapidos a todas las herramientas
// - Lista de estudiantes destacados (top 5 por XP)
// - Lista de estudiantes que necesitan atencion (bajo rendimiento)
// - Selector de grado y ano
// - Acceso a prediccion ICFES, analisis de errores y retos diarios

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/auth_service.dart';
import '../../services/teacher_service.dart';
import '../../widgets/global_scaffold.dart';
import '../../core/theme/app_colors.dart';
import '../../core/animations/app_animations.dart';
import '../../config/navigation.dart';
import '../../core/utils/app_logger.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({Key? key}) : super(key: key);

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  String? _selectedGrado;
  String? _selectedAnio;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _topStudents = [];
  List<Map<String, dynamic>> _studentsNeedingHelp = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;

    final auth = Provider.of<AuthService>(context, listen: false);
    _selectedAnio = DateTime.now().year.toString();

    if (auth.user?['grados_disponibles'] != null) {
      final gradosDynamic = auth.user!['grados_disponibles'] as List<dynamic>;
      if (gradosDynamic.isNotEmpty) {
        _selectedGrado = gradosDynamic[0].toString();
      }
    }

    await _loadStats();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final teacherService = Provider.of<TeacherService>(context, listen: false);

      // Cargar stats del profesor
      final statsData = await teacherService.fetchGroupStats(
        auth.colegio ?? '',
        _selectedGrado,
        _selectedAnio,
      );

      if (mounted) {
        // Obtener estudiantes para extraer top y los que necesitan ayuda
        final students = await teacherService.fetchStudents(_selectedGrado, _selectedAnio);

        // Ordenar por promedio para top students
        final sorted = List<Map<String, dynamic>>.from(students);
        sorted.sort((a, b) {
          final avgA = (a['promedio'] ?? a['puntaje_global'] ?? 0) as num;
          final avgB = (b['promedio'] ?? b['puntaje_global'] ?? 0) as num;
          return avgB.compareTo(avgA);
        });

        setState(() {
          _stats = statsData;
          _topStudents = sorted.take(5).map((s) => {
            'nombre': s['nombre'] ?? 'Estudiante',
            'xp': s['xp'] ?? s['total_xp'] ?? 0,
            'level': s['level'] ?? s['current_level'] ?? 1,
          }).toList();
          _studentsNeedingHelp = sorted.reversed.take(5).where((s) {
            final avg = (s['promedio'] ?? s['puntaje_global'] ?? 0) as num;
            return avg < 250; // Promedio bajo
          }).map((s) => {
            'nombre': s['nombre'] ?? 'Estudiante',
            'promedio': s['promedio'] ?? s['puntaje_global'] ?? 0,
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.e('TeacherDashboard: error cargando stats', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final userName = (auth.nombre ?? 'Profesor').split(' ').first;
    final colegio = auth.colegio ?? 'Sin colegio asignado';
    final avatarUrl = auth.avatarUrl;

    return GlobalScaffold(
      currentIndex: 0,
      body: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : RefreshIndicator(
                  onRefresh: _loadStats,
                  color: AppColors.primary,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        _buildHeader(userName, colegio, avatarUrl, isDark),
                        const SizedBox(height: 20),

                        // Selectores de grado y ano
                        _buildSelectors(isDark),
                        const SizedBox(height: 20),

                        // Cards de estadisticas
                        _buildStatsGrid(isDark),
                        const SizedBox(height: 24),

                        // Accesos rapidos
                        _buildQuickAccess(isDark),
                        const SizedBox(height: 24),

                        // Top estudiantes
                        if (_topStudents.isNotEmpty) ...[
                          _buildSectionTitle(isDark, 'Estudiantes Destacados', Icons.emoji_events_rounded, AppColors.warning),
                          const SizedBox(height: 12),
                          _buildTopStudents(isDark),
                          const SizedBox(height: 24),
                        ],

                        // Estudiantes que necesitan atencion
                        if (_studentsNeedingHelp.isNotEmpty) ...[
                          _buildSectionTitle(isDark, 'Necesitan Atencion', Icons.warning_amber_rounded, AppColors.error),
                          const SizedBox(height: 12),
                          _buildStudentsNeedingHelp(isDark),
                          const SizedBox(height: 24),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader(String name, String colegio, String? avatarUrl, bool isDark) {
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
            blurRadius: 12,
            offset: const Offset(0, 6),
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
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.surface,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? CachedNetworkImageProvider(avatarUrl)
                  : const AssetImage('assets/avatars/default.png') as ImageProvider,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prof. $name',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  colegio,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectors(bool isDark) {
    final auth = context.read<AuthService>();
    final grados = (auth.user?['grados_disponibles'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList() ?? [];

    final anios = [
      DateTime.now().year.toString(),
      (DateTime.now().year - 1).toString(),
    ];

    return Row(
      children: [
        Expanded(
          child: _buildDropdown(
            label: 'Grado',
            value: _selectedGrado,
            items: grados,
            onChanged: (v) {
              setState(() => _selectedGrado = v);
              _loadStats();
            },
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDropdown(
            label: 'Año',
            value: _selectedAnio,
            items: anios,
            onChanged: (v) {
              setState(() => _selectedAnio = v);
              _loadStats();
            },
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          labelStyle: TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14)))).toList(),
        onChanged: onChanged,
        isExpanded: true,
      ),
    );
  }

  Widget _buildStatsGrid(bool isDark) {
    final totalStudents = _stats?['total_estudiantes'] ?? 0;
    final totalSimulacros = _stats?['total_simulacros'] ?? 0;
    final avgScore = _stats?['promedio_colegio'] ?? 0;
    final avgScoreFormatted = avgScore is num ? avgScore.toStringAsFixed(0) : '0';

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard('Estudiantes', '$totalStudents', Icons.school_rounded, AppColors.primary, isDark),
        _buildStatCard('Simulacros', '$totalSimulacros', Icons.assignment_rounded, AppColors.accent, isDark),
        _buildStatCard('Promedio', avgScoreFormatted, Icons.trending_up_rounded, AppColors.success, isDark),
        _buildStatCard('Grado', _selectedGrado ?? '-', Icons.grade_rounded, AppColors.purple, isDark),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.shadowSm, blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
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
              const Spacer(),
              Text(
                value,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildQuickAccess(bool isDark) {
    final items = [
      {'icon': Icons.people_rounded, 'label': 'Estudiantes', 'color': AppColors.primary, 'onTap': () => Nav.goTeacherStudents(context)},
      {'icon': Icons.bar_chart_rounded, 'label': 'Estadisticas', 'color': AppColors.success, 'onTap': () => Nav.goTeacherStats(context)},
      {'icon': Icons.picture_as_pdf_rounded, 'label': 'Informes', 'color': AppColors.error, 'onTap': () => Nav.goTeacherReports(context)},
      {'icon': Icons.insights_rounded, 'label': 'Prediccion ICFES', 'color': AppColors.purple, 'onTap': () => Nav.goPrediction(context)},
      {'icon': Icons.analytics_rounded, 'label': 'Analisis Errores', 'color': AppColors.warning, 'onTap': () => Nav.goErrorAnalysis(context)},
      {'icon': Icons.flash_on_rounded, 'label': 'Retos Diarios', 'color': const Color(0xFF6366F1), 'onTap': () => Nav.goDailyChallenges(context)},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Herramientas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.0,
          children: items.map((item) {
            final color = item['color'] as Color;
            return PressScale(
              onTap: item['onTap'] as VoidCallback,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(item['icon'] as IconData, color: color, size: 22),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item['label'] as String,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTopStudents(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: AppColors.shadowSm, blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: _topStudents.take(5).toList().asMap().entries.map((entry) {
          final index = entry.key;
          final student = entry.value;
          final name = student['nombre'] ?? 'Estudiante';
          final xp = student['xp'] ?? 0;
          final level = student['level'] ?? 1;
          final medals = [AppColors.gold, AppColors.silver, AppColors.bronze];

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: index < 3 ? medals[index] : AppColors.surfaceVariant,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: index < 3 ? Colors.white : AppColors.textTertiary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text('Nv $level', style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('$xp XP', style: TextStyle(fontSize: 12, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStudentsNeedingHelp(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: AppColors.shadowSm, blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: _studentsNeedingHelp.take(5).toList().map((student) {
          final name = student['nombre'] ?? 'Estudiante';
          final avg = student['promedio'] ?? 0;
          final avgFormatted = avg is num ? avg.toStringAsFixed(0) : '0';

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                Text('Prom: $avgFormatted', style: TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w700)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionTitle(bool isDark, String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary)),
      ],
    );
  }
}
