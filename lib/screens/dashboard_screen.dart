// lib/screens/dashboard_screen.dart
// Saber+ — Dashboard Premium with shimmer, animations, and premium empty states

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import '../widgets/dashboard/continue_learning_card.dart';
import '../widgets/dashboard/progress_showcase.dart';
import '../widgets/global_scaffold.dart';
import '../widgets/gamification/gamification_header.dart';
import '../config/navigation.dart';
import '../models/course.dart';
import '../models/summary_stats.dart';
import '../providers/gamification_provider.dart';
import 'dart:math';
import '../widgets/ad_overlay.dart';
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

  /// ✅ v2.0: banner de upgrade — descartable por sesión (no persistente,
  /// para que el descubrimiento de Premium sea visible pero no invasivo).
  bool _premiumBannerDismissed = false;

  /// ✅ v2.0: construye el banner de Premium para usuarios free/trial.
  Widget? _buildPremiumBanner() {
    if (_premiumBannerDismissed) return null;

    final auth = context.read<AuthService>();
    final level = auth.user?['access_level'] as String? ?? 'free';
    if (level == 'premium' || level == 'early_bird') return null;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium_rounded,
              color: Colors.white, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Desbloquea todo Saber+',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Simulacros ilimitados y todos los cursos · pago único',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Nav.goUpgrade(context),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1E3A8A),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Ver Premium',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            onPressed: () => setState(() => _premiumBannerDismissed = true),
            icon: Icon(Icons.close_rounded,
                color: Colors.white.withOpacity(0.7), size: 18),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            tooltip: 'Ocultar',
          ),
        ],
      ),
    );
  }

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
      // ✅ PT5: XP de inicio de sesión — 10 XP la primera vez que el
      // estudiante abre la app cada día (alimenta racha y hábito diario).
      _maybeAwardDailyLoginXp();
      // ✅ PT6: tour de bienvenida la primera vez que entra al dashboard
      _maybeShowOnboarding();
    });
  }

  /// ✅ PT6: muestra el tour de bienvenida una sola vez (flag persistente
  /// marcado al completar o saltar — no al arrancar como el carrusel
  /// pre-login, que así nunca vuelve a verse a mitad).
  Future<void> _maybeShowOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('onboarding_completed') == true) return;
      if (!mounted) return;
      context.go('/onboarding');
    } catch (_) {}
  }

  /// ✅ PT5: otorga daily_login (10 XP) una vez por día natural.
  /// Deduplicación local por fecha + deduplicación server-side.
  Future<void> _maybeAwardDailyLoginXp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today =
          DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD
      final key = 'daily_login_xp_$today';
      if (prefs.getBool(key) == true) return;

      final gamif = context.read<GamificationProvider>();
      final result = await gamif.awardXp(
        reason: 'daily_login',
        description: 'Inicio de sesión diario',
      );
      // Se marca como concedido aunque result sea null (fallo de red): así
      // no spameamos el endpoint en cada rebuild del mismo día.
      await prefs.setBool(key, true);
      if (result != null && result.xpAwarded > 0) {
        debugPrint('[DAILY_LOGIN] +${result.xpAwarded} XP por inicio de sesión');
      }
    } catch (_) {
      // silencioso: la XP diaria nunca debe interrumpir el dashboard
    }
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  // ✅ FASE 5: Control de anuncios - no mostrar más de 1 vez por sesión
  static bool _adShownThisSession = false;

  Future<void> _loadAd() async {
    // No mostrar si ya se mostró en esta sesión
    if (_adShownThisSession) return;

    final api = context.read<ApiService>();
    final ad = await api.getActiveAd();

    if (ad == null) return;

    if (!mounted) return;

    // Marcar como mostrado
    _adShownThisSession = true;

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

                                // ✅ v2.0: banner contextual de Premium (free/trial)
                                _buildPremiumBanner() ?? const SizedBox.shrink(),

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

                                // Continua donde quedaste
                                const ContinueLearningCard(),

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

                                // ✅ PT6: checklist de primeros pasos para
                                // usuarios nuevos (desaparece al completar)
                                const FirstStepsChecklist(),

                                // ✅ FASE 5: Retos Diarios — banner destacado
                                _buildDailyChallengeBanner(),

                                const SizedBox(height: 24),

                                // 🔹 SIMULACROS
                                SectionCard(
                                  title: 'Simulacros',
                                  onViewAll: () {
                                    // ✅ PT1: navegación por router (URL + historial)
                                    Nav.goCourses(
                                      context,
                                      category: 'simulacros',
                                      title: 'Simulacros',
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
                                                      // ✅ PT1: por router
                                                      Nav.goCourses(
                                                        context,
                                                        category: 'simulacros',
                                                        title: 'Simulacros',
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
                                    // ✅ PT1: navegación por router
                                    Nav.goCourses(
                                      context,
                                      category: 'courses',
                                      title: 'Cursos',
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
                                                // ✅ PT1: tap muerto corregido
                                                // — abre el contenido del curso
                                                Nav.goCourseContents(
                                                  context,
                                                  courseId: c.id,
                                                  courseName: c.fullname,
                                                );
                                              },
                                            );
                                          },
                                        ),
                                ),

                                const SizedBox(height: 28),

                                // ✅ v1.7.1: VITRINA DE PROGRESO — reemplaza las
                                // tarjetas de retos (cursos que solo se juegan vía
                                // la función "retar a un amigo" y no eran accesibles
                                // directo). Muestra nivel, racha, insignias y XP en
                                // vivo desde la gamificación.
                                const ProgressShowcase(),

                                const SizedBox(height: 28),

                                // 🔹 RETA A UN AMIGO — acceso directo a los retos
                                // (antes oculto tras tarjetas sin acción).
                                _RetoAmigoCard(),

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
                      // ✅ PT1: tutor IA por router (URL propia + historial)
                      Nav.goChat(context);
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


// ✅ v1.7.1: Tarjeta compacta "Reta a un amigo" — lleva a la sección de
// retos donde sí se pueden iniciar desafíos contra otros estudiantes.
class _RetoAmigoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          // ✅ PT1: retos por router (la ruta /challenges ya existía)
          Nav.goChallenges(context);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowSm,
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF22C55E), Color(0xFF10B981)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.sports_kabaddi_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reta a un amigo',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Compite en tiempo real y gana XP extra',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ══════════════════════════════════════════════════════════════════════
// ✅ PT6: CHECKLIST DE PRIMEROS PASOS
// Tarjeta para usuarios nuevos con las 3 acciones que activan a un
// estudiante en Saber+. Se oculta automáticamente al completarse
// (persistido en SharedPreferences) y se puede descartar manualmente.
// ══════════════════════════════════════════════════════════════════════
class FirstStepsChecklist extends StatefulWidget {
  const FirstStepsChecklist({super.key});

  @override
  State<FirstStepsChecklist> createState() => _FirstStepsChecklistState();
}

class _FirstStepsChecklistState extends State<FirstStepsChecklist> {
  bool _visible = true;
  bool _profileDone = false;
  bool _simulacroDone = false;
  bool _xpDone = false;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _profileDone = prefs.getBool('fs_profile_done') ?? false;
      _simulacroDone = prefs.getBool('fs_simulacro_done') ?? false;
      _xpDone = prefs.getBool('fs_xp_done') ?? false;
      _visible = !(_profileDone && _simulacroDone && _xpDone) &&
          !(prefs.getBool('fs_dismissed') ?? false);
    });
  }

  Future<void> _mark(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
    await _loadState();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final textColor =
        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final subColor =
        isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;
    final done = [_profileDone, _simulacroDone, _xpDone].where((b) => b).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: done == 3
              ? AppColors.success.withOpacity(0.5)
              : (isDark ? AppColors.darkBorder : AppColors.border),
        ),
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
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.rocket_launch_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Empieza con buen pie',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    Text(
                      '$done de 3 completados',
                      style: TextStyle(fontSize: 12, color: subColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded,
                    size: 18, color: subColor),
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('fs_dismissed', true);
                  if (mounted) setState(() => _visible = false);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _step(
            isDark: isDark,
            done: _profileDone,
            icon: Icons.person_rounded,
            label: 'Completa tu perfil',
            onTap: () {
              _mark('fs_profile_done');
              Nav.goProfile(context);
            },
          ),
          _step(
            isDark: isDark,
            done: _simulacroDone,
            icon: Icons.assignment_rounded,
            label: 'Haz tu primer simulacro',
            onTap: () {
              _mark('fs_simulacro_done');
              Nav.goCourses(context,
                  category: 'simulacros', title: 'Simulacros');
            },
          ),
          _step(
            isDark: isDark,
            done: _xpDone,
            icon: Icons.bolt_rounded,
            label: 'Gana tu primera XP',
            onTap: () {
              _mark('fs_xp_done');
              Nav.goDailyChallenges(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _step({
    required bool isDark,
    required bool done,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final textColor =
        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: done ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Icon(
                done
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: done ? AppColors.success : AppColors.textTertiary,
              ),
              const SizedBox(width: 12),
              Icon(icon,
                  size: 18,
                  color: done ? AppColors.success : AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (!done)
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 13, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
