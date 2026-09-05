// lib/screens/dashboard_screen.dart
// Saber+ — Dashboard Premium with shimmer, animations, and premium empty states

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/dashboard/dashboard_header.dart';
import '../widgets/dashboard/progress_card.dart';
import '../widgets/dashboard/primary_cta.dart';
import '../widgets/dashboard/horizontal_preview_list.dart';
import '../widgets/dashboard/preview_card.dart';
import '../widgets/dashboard/section_header.dart';
import '../widgets/dashboard/section_card.dart';
import 'course_list_screen.dart';
import 'challenge_list_screen.dart';
import '../widgets/global_scaffold.dart';
import '../widgets/gamification/gamification_header.dart';
import '../config/navigation.dart';
import '../models/course.dart';
import '../models/summary_stats.dart';
import '../providers/gamification_provider.dart';
import 'dart:math';
import '../widgets/ad_overlay.dart';
import 'chat_screen.dart';
import '../core/theme/app_colors.dart';
import '../core/animations/shimmer_loading.dart';
import '../core/animations/app_animations.dart';
import '../core/widgets/empty_state.dart';

/// 🔹 Listas de imágenes disponibles
const List<String> kCourseImages = [
  'assets/images/cards/book_blue.png',
  'assets/images/cards/book_green.png',
  'assets/images/cards/book_orange.png',
];

const List<String> kSimulacroImages = [
  'assets/images/cards/cube_purple.png',
  'assets/images/cards/stats.png',
  'assets/images/cards/questionnaire.png',
];

const List<String> kRetoImages = [
  'assets/images/cards/book_blue.png',
  'assets/images/cards/book_green.png',
  'assets/images/cards/book_orange.png',
];

/// 🔹 Funciones de asignación determinista por índice
String courseImageByIndex(int index) {
  return kCourseImages[index % kCourseImages.length];
}

String simulacroImageByIndex(int index) {
  return kSimulacroImages[index % kSimulacroImages.length];
}

String retoImageByIndex(int index) {
  return kRetoImages[index % kRetoImages.length];
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fabController;
  late final Animation<double> _fabScale;

  @override
  void initState() {
    super.initState();

    // FAB entrance animation
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fabScale = CurvedAnimation(
      parent: _fabController,
      curve: Curves.elasticOut,
    );

    // 🔹 Cargar datos del dashboard
    Future.microtask(() {
      context.read<DashboardProvider>().loadDashboardData();
    });

    // 🔹 Cargar anuncio y animate FAB after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAd();
      _fabController.forward();
    });
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  Future<void> _loadAd() async {
    final api = context.read<ApiService>();
    final ad = await api.getActiveAd();

    if (ad == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdOverlay(ad: ad),
    );
  }

  /// 🔹 Ordena simulacros igual que en CourseListScreen
  List<Course> _orderedSimulacros(List<Course> courses) {
    final simulacros = courses
        .where((c) => c.name.toLowerCase().contains("simulacro"))
        .toList();

    simulacros.sort((a, b) {
      if (a.name.toLowerCase().contains("diagnostico")) return -1;
      if (b.name.toLowerCase().contains("diagnostico")) return 1;

      final numA =
          int.tryParse(a.name.replaceAll(RegExp(r'[^0-9]'), "")) ?? 9999;
      final numB =
          int.tryParse(b.name.replaceAll(RegExp(r'[^0-9]'), "")) ?? 9999;
      return numA.compareTo(numB);
    });

    return simulacros;
  }

  /// 🔹 Misma lógica de habilitación que en CourseListScreen
  bool _isSimulacroEnabled(Course current, List<Course> orderedSimulacros) {
    if (current.name.toLowerCase().contains('diagnostico')) {
      return true;
    }

    final num = int.tryParse(current.name.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    if (num == 1) {
      final diag = orderedSimulacros.firstWhere(
        (x) => x.name.toLowerCase().contains('diagnostico'),
        orElse: () => current,
      );
      return diag.attempted;
    }

    if (num > 1) {
      final prevName = 'Simulacro ${num - 1}';
      final prev = orderedSimulacros.firstWhere(
        (x) => x.name.contains(prevName),
        orElse: () => current,
      );
      return prev.attempted;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final api = context.read<ApiService>();
    final dashboard = context.watch<DashboardProvider>();

    final userName = (auth.nombre ?? 'Usuario').split(' ').first;
    final avatarUrl = auth.avatarUrl;

    final simulacros = _orderedSimulacros(dashboard.simulacros);
    final cursos = dashboard.cursos;
    final retos = dashboard.retos;

    return GlobalScaffold(
      currentIndex: 0,
      body: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Stack(
            children: [
              // ── Contenido principal ──
              dashboard.isLoading
                  ? const DashboardShimmer()
                  : dashboard.error != null
                      ? Center(
                          child: PremiumEmptyState(
                            icon: Icons.cloud_off_rounded,
                            title: 'Error de conexión',
                            subtitle: dashboard.error!,
                            ctaLabel: 'Reintentar',
                            onCta: () {
                              context.read<DashboardProvider>().loadDashboardData(forceRefresh: true);
                            },
                          ),
                        )
                      : RefreshIndicator(
                          // ✅ Pull-to-refresh real: ignora el caché
                          onRefresh: () => dashboard.loadDashboardData(forceRefresh: true),
                          color: AppColors.primary,
                          backgroundColor: AppColors.surface,
                          displacement: 40,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 🔹 HEADER
                                DashboardHeader(
                                  userName: userName,
                                  avatarUrl: avatarUrl,
                                  isRefreshing: dashboard.isRefreshing,
                                ),

                                const SizedBox(height: 16),

                                // 🔹 GAMIFICATION HEADER (XP bar + racha)
                                // ✅ FASE 3.2: Barra de progreso de nivel + indicador de racha
                                GamificationHeader(
                                  onXpTap: () => Nav.goAchievements(context),
                                  onStreakTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          dashboard.isRefreshing
                                              ? 'Racha: cargando...'
                                              : '¡Llevas ${context.read<GamificationProvider>().currentStreak} días de racha!',
                                        ),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                ),

                                const SizedBox(height: 24),

                                // 🔹 PROGRESO
                                if (dashboard.summary != null)
                                  ProgressCard(
                                    scoreGlobal: dashboard.summary!.promedioGlobal,
                                    areas: dashboard.summary!.areas
                                        .map((k, v) => MapEntry(k, v ?? 0)),
                                    ultimaFecha: dashboard.summary!.ultimaFecha,
                                    tiempoPromedioSeg:
                                        dashboard.summary!.tiempoPromedioSeg,
                                  )
                                else
                                  const SizedBox(height: 120),

                                const SizedBox(height: 24),

                                // ✅ FASE 5: Retos Diarios — banner destacado
                                _buildDailyChallengeBanner(),

                                const SizedBox(height: 24),

                                // 🔹 SIMULACROS
                                SectionCard(
                                  title: 'Simulacros',
                                  onViewAll: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const CourseListScreen(
                                          category: 'simulacros',
                                          title: 'Simulacros',
                                        ),
                                      ),
                                    );
                                  },
                                  child: simulacros.isEmpty
                                      ? const PremiumEmptyState(
                                          icon: Icons.assignment_outlined,
                                          title: 'Sin simulacros',
                                          subtitle: 'Aún no tienes simulacros asignados. Pronto estarán disponibles.',
                                        )
                                      : HorizontalPreviewList(
                                          itemCount: simulacros.length,
                                          builder: (context, index) {
                                            final s = simulacros[index];
                                            final enabled = _isSimulacroEnabled(s, simulacros);

                                            return PreviewCard(
                                              icon: Icons.assignment_rounded,
                                              title: s.fullname,
                                              subtitle: 'ICFES • Simulacro',
                                              imagePath: simulacroImageByIndex(index),
                                              color: AppColors.primary,
                                              locked: !enabled,
                                              completed: s.attempted,
                                              onTap: !enabled
                                                  ? () {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                            'Debes completar el simulacro anterior.',
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                  : () {
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (_) => const CourseListScreen(
                                                            category: 'simulacros',
                                                            title: 'Simulacros',
                                                          ),
                                                        ),
                                                      );
                                                    },
                                            );
                                          },
                                        ),
                                ),

                                const SizedBox(height: 28),

                                // 🔹 CURSOS
                                SectionCard(
                                  title: 'Cursos',
                                  onViewAll: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const CourseListScreen(
                                          category: 'courses',
                                          title: 'Cursos',
                                        ),
                                      ),
                                    );
                                  },
                                  child: cursos.isEmpty
                                      ? const PremiumEmptyState(
                                          icon: Icons.menu_book_outlined,
                                          title: 'Sin cursos',
                                          subtitle: 'No tienes cursos asignados todavía. Contacta a tu profesor.',
                                        )
                                      : HorizontalPreviewList(
                                          itemCount: cursos.length > 5 ? 5 : cursos.length,
                                          builder: (context, index) {
                                            final c = cursos[index];
                                            return PreviewCard(
                                              icon: Icons.menu_book_rounded,
                                              title: c.fullname,
                                              subtitle: 'Curso',
                                              imagePath: courseImageByIndex(index),
                                              color: AppColors.accent,
                                              completed: (c.progress ?? 0) >= 100,
                                              onTap: () {
                                                // Navegación a detalles del curso
                                              },
                                            );
                                          },
                                        ),
                                ),

                                const SizedBox(height: 28),

                                // 🔹 RETOS
                                SectionCard(
                                  title: 'Retos',
                                  onViewAll: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChallengeListScreen(api: api),
                                      ),
                                    );
                                  },
                                  child: retos.isEmpty
                                      ? const PremiumEmptyState(
                                          icon: Icons.emoji_events_outlined,
                                          title: 'Sin retos activos',
                                          subtitle: 'No hay retos disponibles ahora. ¡Vuelve pronto!',
                                        )
                                      : HorizontalPreviewList(
                                          itemCount: retos.length > 3 ? 3 : retos.length,
                                          builder: (context, index) {
                                            final r = retos[index];
                                            return PreviewCard(
                                              icon: Icons.emoji_events_rounded,
                                              title: r.fullname,
                                              subtitle: 'Reto activo',
                                              imagePath: retoImageByIndex(index),
                                              color: AppColors.success,
                                              onTap: () {
                                                // Navegación a detalles del reto
                                              },
                                            );
                                          },
                                        ),
                                ),

                                const SizedBox(height: 80),
                              ],
                            ),
                          ),
                      ),

              // ── FAB ANIMATED ──
              Positioned(
                bottom: 24,
                right: 24,
                child: ScaleTransition(
                  scale: _fabScale,
                  child: FloatingActionButton.extended(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ChatScreen()),
                      );
                    },
                    backgroundColor: AppColors.textSecondary,
                    icon: Icon(Icons.auto_awesome, color: AppColors.accent, size: 22),
                    label: const Text(
                      'Saber+ IA',
                      style: TextStyle(
                        color: AppColors.textOnPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ✅ FASE 5: Banner de Retos Diarios en el dashboard.
  /// Muestra un CTA prominente para que el usuario vaya a los retos diarios.
  Widget _buildDailyChallengeBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => Nav.goDailyChallenges(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.flash_on_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Retos Diarios',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '¡Completa los retos de hoy y gana XP!',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: const Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Ver retos',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
