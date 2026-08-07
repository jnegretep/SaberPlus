import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/global_scaffold.dart';
import '../../core/theme/app_colors.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({Key? key}) : super(key: key);

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  String? _selectedGrado;
  String? _selectedAnio;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    
    final auth = Provider.of<AuthService>(context, listen: false);
    
    // Establecer año actual por defecto
    _selectedAnio = DateTime.now().year.toString();
    
    // Convertir List<dynamic> a List<String> y obtener el primer elemento
    if (auth.user?['grados_disponibles'] != null) {
      final gradosDynamic = auth.user!['grados_disponibles'] as List<dynamic>;
      if (gradosDynamic.isNotEmpty) {
        _selectedGrado = gradosDynamic[0].toString();
      }
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildHeader(AuthService auth) {
    final userName = (auth.nombre ?? 'Profesor').split(' ').first;
    final colegio = auth.colegio ?? 'Sin colegio asignado';
    

// AHORA (usar esto directo):
String avatarUrl = auth.avatarUrl;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface.withOpacity(0.5), width: 1),
                ),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.surface,
                    backgroundImage: avatarUrl != null
                        ? NetworkImage(avatarUrl)
                        : const AssetImage('assets/avatars/default.png')
                            as ImageProvider,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Prof. $userName',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textOnPrimary,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      colegio,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.surface.withOpacity(0.9),
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surface.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.dashboard_rounded, color: AppColors.surface.withOpacity(0.9), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Panel de Control Académico',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.surface.withOpacity(0.95),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(AuthService auth) {
    final gradosDynamic = auth.user?['grados_disponibles'] as List<dynamic>? ?? [];
    final List<String> grados = gradosDynamic.map((e) => e.toString()).toList();
    
    final currentYear = DateTime.now().year;
    final List<String> anios = [
      (currentYear - 2).toString(),
      (currentYear - 1).toString(),
      currentYear.toString(),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMd,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Text(
                'Filtros de análisis',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildFilterDropdown(
                  label: 'Grado',
                  value: _selectedGrado,
                  items: grados,
                  hint: 'Grado',
                  onChanged: (value) {
                    setState(() => _selectedGrado = value);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildFilterDropdown(
                  label: 'Año',
                  value: _selectedAnio,
                  items: anios,
                  hint: 'Año',
                  onChanged: (value) {
                    setState(() => _selectedAnio = value);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required String hint,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceClean,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textTertiary),
              hint: Text(
                hint,
                style: TextStyle(color: AppColors.textDisabled, fontSize: 14),
              ),
              items: items.map((item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    item,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500
                    ),
                    overflow: TextOverflow.ellipsis,
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

  // ✅ CORREGIDO: Optimizada para no desbordar en espacios pequeños
  Widget _buildStatsCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      // Padding reducido para ganar espacio interno
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.textTertiary.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: AppColors.textOnPrimary, width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8), // Icono más compacto
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 6), // Espacio reducido
          
          // FittedBox ayuda a que el número no desborde si es muy grande
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 22, // Fuente ligeramente ajustada
                fontWeight: FontWeight.w800,
                color: color,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 4), // Espacio reducido
          
          Text(
            title,
            style: TextStyle(
              fontSize: 11, // Fuente ajustada para evitar corte
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textDisabled,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
    bool comingSoon = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.textTertiary.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: AppColors.textOnPrimary, width: 2),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    if (comingSoon)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.warningBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Pronto',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warningDark,
                          ),
                        ),
                      ),
                  ],
                ),
                
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15, // Ligero ajuste
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12, // Ligero ajuste
                        color: AppColors.textTertiary,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                
                Row(
                  children: [
                    Text(
                      'Acceder',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: color,
                      size: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final colegioStats = auth.user?['colegio_stats'] ?? {};

    String formatPromedio(dynamic promedio) {
      if (promedio == null) return 'N/A';
      try {
        if (promedio is String) {
          final doubleValue = double.tryParse(promedio);
          return doubleValue?.toStringAsFixed(1) ?? 'N/A';
        }
        if (promedio is num) {
          return promedio.toStringAsFixed(1);
        }
        return 'N/A';
      } catch (e) {
        return 'N/A';
      }
    }

    return GlobalScaffold(
      currentIndex: 0,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(auth),

            const SizedBox(height: 32),

            _buildFilterBar(auth),

            const SizedBox(height: 32),

            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                'Resumen del colegio',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // ✅ CORREGIDO: Ratio modificado para hacer las tarjetas más altas
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              // Ratio reducido de 0.75 a 0.65 -> Esto hace la tarjeta más alta
              childAspectRatio: 0.65, 
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _buildStatsCard(
                  icon: Icons.people_alt_rounded,
                  title: 'Estudiantes',
                  value: colegioStats['total_estudiantes']?.toString() ?? '0',
                  color: AppColors.primary,
                  subtitle: 'Inscritos',
                ),
                _buildStatsCard(
                  icon: Icons.assignment_rounded,
                  title: 'Simulacros',
                  value: colegioStats['total_simulacros']?.toString() ?? '0',
                  color: AppColors.successDark,
                  subtitle: 'Realizados',
                ),
                _buildStatsCard(
                  icon: Icons.bar_chart_rounded,
                  title: 'Promedio',
                  value: formatPromedio(colegioStats['promedio_colegio']),
                  color: AppColors.purple,
                  subtitle: 'Global',
                ),
              ],
            ),

            const SizedBox(height: 32),

            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                'Herramientas Docentes',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                'Gestione el seguimiento académico de sus grupos',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // GRID 2: Acciones
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              // Ratio 0.72 para botones grandes funciona bien
              childAspectRatio: 0.72,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                _buildActionCard(
                  icon: Icons.school_rounded,
                  title: 'Mis Estudiantes',
                  description: 'Lista detallada y perfiles de alumnos.',
                  color: AppColors.primary,
                  onTap: () {
                    // Navegación
                  },
                ),
                _buildActionCard(
                  icon: Icons.analytics_rounded,
                  title: 'Estadísticas',
                  description: 'Análisis de rendimiento por competencias.',
                  color: AppColors.successDark,
                  onTap: () {
                    // Navegación
                  },
                ),
                _buildActionCard(
                  icon: Icons.leaderboard_rounded,
                  title: 'Ranking',
                  description: 'Posiciones y comparativas grupales.',
                  color: AppColors.warning,
                  onTap: () {
                    // Navegación
                  },
                ),
                _buildActionCard(
                  icon: Icons.picture_as_pdf_rounded,
                  title: 'Informes',
                  description: 'Descargar reportes en formato PDF.',
                  color: AppColors.error,
                  onTap: () {
                    // Navegación
                  },
                  comingSoon: true,
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Footer informativo
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppColors.textTertiary, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Panel Docente',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.borderDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Utilice estas herramientas para monitorear el progreso, identificar áreas de refuerzo y generar reportes para reuniones académicas.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textTertiary,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded,
              color: AppColors.successDark, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.borderMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}