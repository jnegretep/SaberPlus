import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/course.dart';
import '../services/api_service.dart';
import '../widgets/global_scaffold.dart';
import '../widgets/dashboard/preview_card.dart';
import '../screens/upgrade_screen.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';
import '../core/services/course_cache_service.dart';
import '../core/utils/app_logger.dart';
import '../widgets/dashboard/continue_learning_card.dart';
import '../widgets/search_bar_widget.dart';

class CourseListScreen extends StatefulWidget {
  final String category; // 'courses' | 'simulacros' | 'retos'
  final String title;

  const CourseListScreen({
    Key? key,
    required this.category,
    this.title = 'Mis Cursos',
  }) : super(key: key);

  @override
  State<CourseListScreen> createState() => _CourseListScreenState();
}

class _CourseListScreenState extends State<CourseListScreen> with RouteAware {
  late Future<List<Course>> _futureCourses;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiService>();
    _futureCourses = _loadCoursesWithAttempts(api);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// ✅ FASE 4: Carga cursos con caché offline.
  /// - Primero intenta caché (TTL 30 min)
  /// - Si no hay caché o expiró, carga desde API y guarda en caché
  /// - Si no hay internet, usa caché expirado (mejor que nada)
  Future<List<Course>> _loadCoursesWithAttempts(ApiService api) async {
    // ✅ Usar caché para la lista de cursos
    var courses = await CourseCacheService.fetchCoursesWithCache(
      api: api,
      category: widget.category,
    );

    if (widget.category == 'simulacros') {
      try {
        final attempts = await api.fetchSimulacroAttempts(api.auth.userId!);
        for (var c in courses) {
          if (attempts.contains(c.id)) {
            c.attempted = true;
          }
        }
      } catch (e) {
        AppLogger.w('No se pudieron cargar attempts (¿offline?): $e');
        // Continuamos sin marcar attempts — los cursos igual se muestran
      }
    }
    return courses;
  }

  /// Refresca forzando ignorar caché (pull-to-refresh)
  Future<List<Course>> _loadCoursesWithAttemptsForce(ApiService api) async {
    var courses = await CourseCacheService.fetchCoursesWithCache(
      api: api,
      category: widget.category,
      forceRefresh: true,
    );

    if (widget.category == 'simulacros') {
      try {
        final attempts = await api.fetchSimulacroAttempts(api.auth.userId!);
        for (var c in courses) {
          if (attempts.contains(c.id)) {
            c.attempted = true;
          }
        }
      } catch (e) {
        AppLogger.w('No se pudieron cargar attempts (¿offline?): $e');
      }
    }
    return courses;
  }

  @override
  void didPopNext() {
    final api = context.read<ApiService>();
    setState(() {
      _futureCourses = _loadCoursesWithAttempts(api);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlobalScaffold(
      currentIndex: 0,
      body: SafeArea(
        child: FutureBuilder<List<Course>>(
          future: _futureCourses,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _buildErrorState(snap.error);
            }

            var courses = snap.data ?? [];
            if (courses.isEmpty) {
              return Center(
                child: Text(
                  _emptyTextForCategory(widget.category),
                  style: TextStyle(fontSize: 15),
                ),
              );
            }

            if (widget.category == 'simulacros') {
              courses = _orderedCourses(courses);
            }

            // Filtrar por busqueda si hay query
            if (_searchQuery.isNotEmpty) {
              final query = _searchQuery.toLowerCase();
              courses = courses
                  .where((c) => c.name.toLowerCase().contains(query))
                  .toList();
            }

            // ✅ FASE 4: Pull-to-refresh con caché
            return RefreshIndicator(
              onRefresh: () async {
                final api = context.read<ApiService>();
                setState(() {
                  _futureCourses = _loadCoursesWithAttemptsForce(api);
                });
                await _futureCourses;
              },
              color: AppColors.primary,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ───── Header ─────
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${courses.length} disponibles',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Barra de busqueda
                    SearchBarWidget(
                      controller: _searchCtrl,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      hintText: 'Buscar ${widget.title.toLowerCase()}...',
                    ),
                    const SizedBox(height: 16),

                    // ───── Grid ─────
                    Expanded(
                      child: GridView.builder(
                        itemCount: courses.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.95,
                        ),
                        itemBuilder: (ctx, i) {
                          final c = courses[i];

                          final enabledByProgress = _isEnabled(c, courses);
                          final imagePath = _imageForCategory(widget.category, i);

                          // 🔹 CORRECCIÓN: Maneja cuando locked es null
                          final isPaywallLocked = c.locked ?? false;
                          final isLocked = isPaywallLocked || !enabledByProgress;

                          return PreviewCard(
                            icon: Icons.school,
                            title: c.name,
                            subtitle: widget.category == 'simulacros'
                                ? 'Simulacro'
                                : 'Curso',
                            imagePath: imagePath,
                            color: AppColors.primary,
                            locked: isLocked,
                            completed: c.attempted,
                            onTap: () async {
                              // 1️⃣ Bloqueado por PLAN → PAYWALL
                              if (isPaywallLocked) {
                                final upgradeResult = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const UpgradeScreen(),
                                  ),
                                );

                                // Si el upgrade fue exitoso (true), recargar cursos
                                if (upgradeResult == true) {
                                  final api = context.read<ApiService>();
                                  setState(() {
                                    _futureCourses = _loadCoursesWithAttempts(api);
                                  });
                                }
                                return;
                              }

                              // 2️⃣ Bloqueado por PROGRESIÓN
                              if (!enabledByProgress) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Debes completar el simulacro anterior.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              // 3️⃣ Acceso normal
                              // Guardar como ultimo accedido para "Continua donde quedaste"
                              ContinueLearningCard.saveLastAccessed(
                                courseId: c.id,
                                courseName: c.name,
                                category: widget.category,
                              );
                              Nav.goCourseContents(
                                context,
                                courseId: c.id,
                                courseName: c.name,
                              );

                              final api = context.read<ApiService>();
                              setState(() {
                                _futureCourses = _loadCoursesWithAttempts(api);
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// ✅ FASE 4: Estado de error mejorado (con sugerencia offline).
  Widget _buildErrorState(dynamic error) {
    final errorMsg = error.toString();
    final isOffline = errorMsg.contains('SocketException') ||
        errorMsg.contains('Failed host lookup') ||
        errorMsg.contains('Connection refused');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
              size: 64,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              isOffline
                  ? 'Sin conexión a internet'
                  : 'Error al cargar cursos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isOffline
                  ? 'Verifica tu conexión e inténtalo de nuevo.'
                  : errorMsg,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                final api = context.read<ApiService>();
                setState(() {
                  _futureCourses = _loadCoursesWithAttemptsForce(api);
                });
              },
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

  // ─────────────────────────────
  bool _isEnabled(Course c, List<Course> courses) {
    if (widget.category != 'simulacros') return true;

    // Caso especial: Diagnóstico
    if (c.name.toLowerCase().contains('diagnostico')) {
      return true;
    }

    // Extraer número del simulacro
    final num = int.tryParse(c.name.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

    // Simulacro 1 depende del diagnóstico
    if (num == 1) {
      final diag = courses.firstWhere(
        (x) => x.name.toLowerCase().contains('diagnostico'),
        orElse: () => c,
      );
      return diag.attempted;
    }

    // Simulacros posteriores dependen del anterior
    if (num > 1) {
      final prevName = 'Simulacro ${num - 1}';
      final prev = courses.firstWhere(
        (x) => x.name.contains(prevName),
        orElse: () => c,
      );
      return prev.attempted;
    }

    return true;
  }

  String _imageForCategory(String category, int index) {
    if (category == 'courses') {
      const books = [
        'assets/images/cards/book_blue.png',
        'assets/images/cards/book_green.png',
        'assets/images/cards/book_orange.png',
      ];
      return books[index % books.length];
    }

    const simulacros = [
      'assets/images/cards/cube_purple.png',
      'assets/images/cards/stats.png',
      'assets/images/cards/questionnaire.png',
    ];
    return simulacros[index % simulacros.length];
  }

  String _emptyTextForCategory(String category) {
    switch (category) {
      case 'simulacros':
        return 'No tienes simulacros asignados.';
      case 'retos':
        return 'No tienes retos asignados.';
      default:
        return 'No tienes cursos asignados.';
    }
  }

  List<Course> _orderedCourses(List<Course> courses) {
    final simulacros = courses
        .where((c) => c.name.toLowerCase().contains("simulacro"))
        .toList();
    final otros = courses
        .where((c) => !c.name.toLowerCase().contains("simulacro"))
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

    return [...simulacros, ...otros];
  }
}