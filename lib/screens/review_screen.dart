import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../core/theme/app_colors.dart';
import '../widgets/rich/moodle_rich_text.dart';
import '../widgets/rich/q_image.dart';
import 'package:go_router/go_router.dart';
import '../providers/gamification_provider.dart';
import '../widgets/gamification/celebration_overlay.dart';
import '../parsers/review_question_parser.dart';
import '../widgets/question_option_tile.dart';

class ReviewScreen extends StatefulWidget {
  final Map<String, dynamic> reviewData;
  final int courseId;
  final int quizId; // ¡NUEVO!

  const ReviewScreen({
    Key? key,
    required this.reviewData,
    required this.courseId,
    required this.quizId, // ¡NUEVO!
  }) : super(key: key);

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _statsSent = false;
  final List<int> _simuIds = const [
    2, 3, 18, 24, 25, 26, 27, 28, 29, 30, 31
  ];

  /// Preguntas ya parseadas con [parseReviewQuestion]. El HTML de revisión
  /// no cambia tras entrar a la pantalla, así que cada pregunta se parsea
  /// UNA sola vez y el resultado alimenta conteos y tarjetas.
  final Map<int, ReviewQuestionData> _parsedCache = {};

  /// Parsea (o devuelve cacheada) la pregunta [q].
  ReviewQuestionData _parsedFor(Map<String, dynamic> q) {
    final rawSlot = q['slot'];
    final int? slot = rawSlot is num ? rawSlot.toInt() : null;
    // Sin slot no se cachea (evita colisiones entre preguntas malformadas).
    if (slot != null && slot > 0) {
      return _parsedCache.putIfAbsent(slot, () => parseReviewQuestion(q));
    }
    return parseReviewQuestion(q);
  }

  // ==========================
  //   MÉTODOS PARA DETECCIÓN DE ÁREAS
  // ==========================

  String _getAreaName(int page, int totalPages) {
    // Si solo hay una página, es un cuestionario normal, no un simulacro
    if (totalPages == 1) {
      return 'Cuestionario';
    }

    // Si hay 5 páginas, asumimos que es un simulacro ICFES con áreas específicas
    if (totalPages == 5) {
      const areas = [
        'Lectura crítica',
        'Matemáticas',
        'Ciencias sociales',
        'Ciencias naturales',
        'Inglés'
      ];
      if (page >= 0 && page < areas.length) return areas[page];
    }

    // Para cualquier otro caso (por si acaso)
    return 'Área ${page + 1}';
  }

  Color _getAreaColor(int page, int totalPages) {
    // Si es cuestionario de una sola página, usar color primario
    if (totalPages == 1) {
      return AppColors.primary;
    }

    // Si es simulacro ICFES (5 páginas), usar colores por área
    if (totalPages == 5) {
      switch (page) {
        case 0:
          return AppColors.primaryLight; // Lectura crítica
        case 1:
          return AppColors.successDark; // Matemáticas
        case 2:
          return AppColors.purple; // Ciencias sociales
        case 3:
          return AppColors.warning; // Ciencias naturales
        case 4:
          return AppColors.error; // Inglés
      }
    }

    // Color por defecto
    return AppColors.textMuted;
  }

  double _pageScore(List<Map<String, dynamic>> qs) {
    if (qs.isEmpty) return 0;
    final correct = _pageCorrectCount(qs);
    return (correct / qs.length) * 100.0;
  }

  int _pageCorrectCount(List<Map<String, dynamic>> qs) {
    // Estado robusto del parser (tolerante a qtypes) — solo 'correct' suma.
    return qs
        .where((q) => _parsedFor(q).state == ReviewQuestionState.correct)
        .length;
  }

  double _globalScore(Map<int, List<Map<String, dynamic>>> grouped) {
    if (grouped.length < 5) return 0;

    final lc = _pageScore(grouped[0] ?? []);
    final mat = _pageScore(grouped[1] ?? []);
    final soc = _pageScore(grouped[2] ?? []);
    final cn = _pageScore(grouped[3] ?? []);
    final ing = _pageScore(grouped[4] ?? []);

    final global = ((lc * 3 + mat * 3 + soc * 3 + cn * 3 + ing * 1) / 13) * 5;
    return global;
  }

  @override
  void initState() {
    super.initState();
    debugPrint("[REVIEW_SCREEN] Iniciando para courseId: ${widget.courseId}");
  }

  // ==========================
  //   MÉTODOS PARA GUARDAR ESTADÍSTICAS - MEJORADOS
  // ==========================

  Future<void> _sendStatsIfNeeded(
    Map<int, List<Map<String, dynamic>>> grouped,
    List<int> sortedPages,
  ) async {
    if (_statsSent) return;

    final review = widget.reviewData;

    // Convertir attempt a Map<String, dynamic> de forma segura
    final Map<String, dynamic> attempt;
    if (review['attempt'] != null) {
      if (review['attempt'] is Map<String, dynamic>) {
        attempt = review['attempt'] as Map<String, dynamic>;
      } else {
        attempt = Map<String, dynamic>.from(review['attempt']);
      }
    } else {
      attempt = <String, dynamic>{};
    }

    // Verificar si es simulacro por courseId
    final courseId = widget.courseId;
    if (!_simuIds.contains(courseId)) {
      debugPrint(
          "[STATS] No es simulacro (courseId $courseId no está en _simuIds)");
      return;
    }

    // Verificar si el intento está terminado (por cualquier motivo)
    final timefinish = attempt['timefinish'] ?? 0;
    final state = (attempt['state'] ?? "").toString().toLowerCase();

    debugPrint("[STATS] timefinish: $timefinish, state: $state");

    // Si no está terminado, no guardar estadísticas aún
    if (timefinish == 0 && state == 'inprogress') {
      debugPrint("[STATS] Intento inprogress, no guardando estadísticas");
      return;
    }

    // Verificar que tenemos datos para calcular estadísticas
    if (sortedPages.isEmpty || grouped.isEmpty) {
      debugPrint("[STATS] No hay datos para calcular estadísticas");
      return;
    }

    // Guardar estadísticas para intentos terminados (finished, overdue, abandoned)
    await _saveSimulacroStats(grouped, sortedPages, attempt);
  }

  Future<void> _saveSimulacroStats(
    Map<int, List<Map<String, dynamic>>> grouped,
    List<int> sortedPages,
    Map<String, dynamic> attempt,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    int quizId = attempt['quiz'] ?? widget.quizId;
    final key = 'simulacro_${quizId}_saved';

    // Evitar guardar múltiples veces
    if (prefs.getBool(key) == true) {
      _statsSent = true;
      debugPrint("[STATS] Estadísticas ya guardadas previamente");
      return;
    }

    final api = context.read<ApiService>();

    try {
      // Calcular estadísticas por área
      final Map<String, double> areaScores = {};
      final Map<String, int> areaCorrect = {};

      for (final page in sortedPages) {
        final questions = grouped[page] ?? [];
        final areaName = _getAreaName(page, sortedPages.length);
        final correct = questions
            .where((q) => _parsedFor(q).state == ReviewQuestionState.correct)
            .length;
        final total = questions.length;

        areaCorrect[areaName] = correct;
        areaScores[areaName] = total > 0 ? (correct / total * 100.0) : 0.0;
      }

      // Calcular puntaje global (según ponderación ICFES)
      final lectura = areaScores['Lectura crítica'] ?? 0;
      final matematicas = areaScores['Matemáticas'] ?? 0;
      final sociales = areaScores['Ciencias sociales'] ?? 0;
      final naturales = areaScores['Ciencias naturales'] ?? 0;
      final ingles = areaScores['Inglés'] ?? 0;

      final globalScore =
          ((lectura * 3 + matematicas * 3 + sociales * 3 + naturales * 3 + ingles * 1) /
                  13) *
              5;

      // Calcular tiempo empleado en minutos
      int tiempoEmpleado = 0;
      if (attempt['timefinish'] != null && attempt['timestart'] != null) {
        final tiempoSegundos = attempt['timefinish'] - attempt['timestart'];
        tiempoEmpleado = (tiempoSegundos / 60).round();
      } else {
        // Intentar obtener tiempo de otra fuente
        final tiempo =
            attempt['timeused'] ?? attempt['time'] ?? attempt['tiempo'] ?? 0;
        tiempoEmpleado = (int.tryParse(tiempo.toString()) ?? 0) ~/ 60;
      }

      // Preparar payload
      final payload = <String, dynamic>{
        'simulacro_id': quizId,
        'course_id': widget.courseId,
        'puntaje_global': globalScore,
        'lectura_correctas': areaCorrect['Lectura crítica'] ?? 0,
        'matematicas_correctas': areaCorrect['Matemáticas'] ?? 0,
        'sociales_correctas': areaCorrect['Ciencias sociales'] ?? 0,
        'naturales_correctas': areaCorrect['Ciencias naturales'] ?? 0,
        'ingles_correctas': areaCorrect['Inglés'] ?? 0,
        'lectura_puntaje': lectura,
        'matematicas_puntaje': matematicas,
        'sociales_puntaje': sociales,
        'naturales_puntaje': naturales,
        'ingles_puntaje': ingles,
        'tiempo_empleado': tiempoEmpleado,
      };

      debugPrint("[STATS] Guardando estadísticas: $payload");
      await api.saveSimulacroResult(payload);
      await prefs.setBool(key, true);
      _statsSent = true;

      debugPrint("[STATS] Estadísticas guardadas exitosamente para quiz $quizId");

      // ✅ PT5: conectar la gamificación al flujo principal — terminar un
      // simulacro otorga 100 XP + actualiza racha (antes la XP solo vivía
      // en los retos diarios y el estudiante no percibía progreso).
      // referenceId = id del intento → el backend deduplica por evento.
      await _awardSimulacroXp(attempt);
    } catch (e) {
      debugPrint("[STATS] Error guardando estadísticas: $e");
    }
  }

  /// ✅ PT5: otorga XP por simulacro completado y celebra logros.
  Future<void> _awardSimulacroXp(Map<String, dynamic> attempt) async {
    try {
      final gamif = context.read<GamificationProvider>();
      final attemptId = int.tryParse('${attempt['id'] ?? ''}') ?? widget.quizId;
      final result = await gamif.awardXp(
        reason: 'simulacro',
        referenceId: attemptId,
        description: 'Simulacro ICFES completado',
      );
      if (result == null || !mounted) return;
      if (result.xpAwarded <= 0) return; // deduplicado o sin XP

      if (result.leveledUp) {
        await CelebrationOverlay.show(
          context,
          type: CelebrationType.levelUp,
          level: result.newLevel,
          newBadges: result.newBadges,
          xpEarned: result.xpAwarded,
        );
      } else if (result.newBadges.isNotEmpty) {
        await CelebrationOverlay.show(
          context,
          type: CelebrationType.badgeUnlocked,
          newBadges: result.newBadges,
          xpEarned: result.xpAwarded,
        );
      } else {
        await CelebrationOverlay.show(
          context,
          type: CelebrationType.simulacroComplete,
          xpEarned: result.xpAwarded,
        );
      }
    } catch (e) {
      debugPrint("[STATS] Error otorgando XP del simulacro: $e");
    }
  }

  // ==========================
  //   MÉTODOS DE CONSTRUCCIÓN
  // ==========================

  Widget _buildQuestionList(
      List<Map<String, dynamic>> qs, int page, bool isMulti, int totalPages) {
    final correct = _pageCorrectCount(qs);
    final total = qs.length;
    final score = total > 0 ? (correct / total) * 100 : 0.0;
    final areaColor = _getAreaColor(page, totalPages);
    final areaName = _getAreaName(page, totalPages);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER DEL ÁREA/CUESTIONARIO
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadowMd,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: areaColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: areaColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            areaName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: areaColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          totalPages == 1
                              ? 'Resultados del cuestionario'
                              : 'Desempeño del área',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: areaColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${score.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: areaColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$correct de $total correctas',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: score / 100,
                  backgroundColor: AppColors.surfaceVariant,
                  color: areaColor,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Progreso',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    Text(
                      '${score.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: areaColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // LISTA DE PREGUNTAS
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 12),
                child: Text(
                  totalPages == 1
                      ? 'Revisión detallada de respuestas'
                      : 'Revisión pregunta por pregunta',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),

              // Cada pregunta se parsea UNA vez (caché) y la tarjeta recibe
              // el ReviewQuestionData ya procesado.
              ...qs.asMap().entries.map((entry) {
                final index = entry.key;
                final q = entry.value;
                final parsed = _parsedFor(q);

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: _QuestionCard(
                    questionNumber: parsed.slot > 0 ? parsed.slot : index + 1,
                    data: parsed,
                  ),
                );
              }),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSingleAreaView(
    Map<int, List<Map<String, dynamic>>> grouped,
    int page,
    List<Map<String, dynamic>> questions,
  ) {
    final totalPages = grouped.length;
    final attempt = widget.reviewData['attempt'] ?? {};
    final state = (attempt['state'] ?? "").toString().toLowerCase();
    final isOverdue = state == 'overdue';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 1,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textSecondary,
            size: 24,
          ),
          onPressed: () {
            // ✅ PT1: pop con resultado vía router
            context.pop(true);
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isOverdue
                  ? 'Revisión - Cuestionario Vencido'
                  : 'Revisión del cuestionario',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isOverdue
                    ? AppColors.errorDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${questions.length} preguntas',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isOverdue
                    ? AppColors.errorLight
                    : AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_pageScore(questions).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isOverdue ? AppColors.errorDark : AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _buildQuestionList(questions, page, false, totalPages),
    );
  }

  // ✅ FIX: `body: TabBarView(...)` movido al Scaffold (antes estaba dentro
  // del AppBar, que no tiene parámetro `body` → error de compilación).
  Widget _buildMultiAreaView(
    Map<int, List<Map<String, dynamic>>> grouped,
    List<int> sortedPages,
    double globalScore,
  ) {
    final totalPages = sortedPages.length;
    final isSimulacro = totalPages == 5;
    final attempt = widget.reviewData['attempt'] ?? {};
    final state = (attempt['state'] ?? "").toString().toLowerCase();
    final isOverdue = state == 'overdue';

    return DefaultTabController(
      length: totalPages,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 1,
          centerTitle: false,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textSecondary,
              size: 24,
            ),
            onPressed: () {
              // ✅ PT1: pop con resultado vía router
              context.pop(true);
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isOverdue
                    ? 'Revisión - Simulacro Vencido'
                    : isSimulacro
                        ? 'Revisión - Simulacro ICFES'
                        : 'Revisión - Múltiples secciones',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isOverdue
                      ? AppColors.errorDark
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (isSimulacro) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOverdue
                            ? AppColors.errorLight
                            : AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Global: ${globalScore.toStringAsFixed(1)}/500',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isOverdue
                              ? AppColors.errorDark
                              : AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    '$totalPages ${totalPages == 1 ? 'sección' : 'secciones'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          bottom: totalPages > 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: Container(
                    color: AppColors.surface,
                    child: TabBar(
                      isScrollable: true,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.textTertiary,
                      indicatorColor: AppColors.primary,
                      indicatorWeight: 3,
                      indicatorSize: TabBarIndicatorSize.label,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      unselectedLabelStyle: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                      tabs: sortedPages
                          .map((p) => Tab(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  child: Text(_getAreaName(p, totalPages)),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                )
              : null,
        ),
        // ✅ FIX: body del Scaffold (antes estaba por error dentro del AppBar)
        body: TabBarView(
          children: sortedPages
              .map((p) =>
                  _buildQuestionList(grouped[p] ?? [], p, true, totalPages))
              .toList(),
        ),
      ),
    );
  }

  /// ✅ Fix P10: reviewData sin preguntas → estado vacío amable en vez de
  /// crashear en `sortedPages.first`.
  Widget _buildEmptyView() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 1,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textSecondary,
            size: 24,
          ),
          onPressed: () => context.pop(true),
        ),
        title: Text(
          'Revisión del cuestionario',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.quiz_outlined,
                size: 64,
                color: AppColors.textSubtle,
              ),
              const SizedBox(height: 16),
              const Text(
                'No hay preguntas para revisar',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Este intento no tiene preguntas disponibles para mostrar.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.reviewData;
    final questions = review['questions'] is List
        ? List<Map<String, dynamic>>.from(review['questions'])
        : <Map<String, dynamic>>[];

    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final q in questions) {
      final p = q['page'] ?? 0;
      grouped.putIfAbsent(p, () => []).add(q);
    }

    final sortedPages = grouped.keys.toList()..sort();

    // ✅ Fix P10: guard de reviewData vacío.
    if (sortedPages.isEmpty) {
      return _buildEmptyView();
    }

    final totalPages = sortedPages.length;
    final isMulti = totalPages > 1;
    final globalScore = isMulti && totalPages == 5 ? _globalScore(grouped) : 0.0;

    // Guardar estadísticas si es un simulacro y aún no se han guardado
    if (!_statsSent && _simuIds.contains(widget.courseId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendStatsIfNeeded(grouped, sortedPages);
      });
    }

    // ✅ FASE 4: Al cerrar el review, navegar a estadísticas en lugar de
    // volver al cuestionario o quiz_list.
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          // ✅ FASE 4: Navegar a estadísticas con los resultados actualizados
          context.go('/estadisticas');
        }
      },
      child: isMulti
        ? _buildMultiAreaView(grouped, sortedPages, globalScore)
        : _buildSingleAreaView(
            grouped,
            sortedPages.first,
            grouped[sortedPages.first] ?? [],
          ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Helpers de estado (compartidos por la pantalla y las tarjetas)
// ═══════════════════════════════════════════════════════════════════

/// Color del estado — correct: verde, incorrect: rojo, parcial: ámbar,
/// sin responder: gris.
Color _stateColor(String state) {
  switch (state) {
    case ReviewQuestionState.correct:
      return AppColors.successDark;
    case ReviewQuestionState.incorrect:
      return AppColors.error;
    case ReviewQuestionState.partially:
      return AppColors.warning;
    default:
      return AppColors.textMuted;
  }
}

String _stateLabel(String state) {
  switch (state) {
    case ReviewQuestionState.correct:
      return 'Correcta';
    case ReviewQuestionState.incorrect:
      return 'Incorrecta';
    case ReviewQuestionState.partially:
      return 'Parcialmente correcta';
    default:
      return 'Sin responder';
  }
}

IconData _stateIcon(String state) {
  switch (state) {
    case ReviewQuestionState.correct:
      return Icons.check_circle_rounded;
    case ReviewQuestionState.incorrect:
      return Icons.cancel_rounded;
    case ReviewQuestionState.partially:
      return Icons.error_outline_rounded;
    default:
      return Icons.help_outline_rounded;
  }
}

// ═══════════════════════════════════════════════════════════════════
// Tarjeta de pregunta
// ═══════════════════════════════════════════════════════════════════

class _QuestionCard extends StatefulWidget {
  final int questionNumber;
  final ReviewQuestionData data;

  const _QuestionCard({
    required this.questionNumber,
    required this.data,
  });

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  /// La retroalimentación se muestra EXPANDIDA por defecto (antes llegaba
  /// colapsada y el estudiante creía que no había feedback).
  bool _feedbackExpanded = true;

  ReviewQuestionData get _data => widget.data;

  void _openGallery(List<String> urls, int index) {
    QImageGallery.open(context, urls, index);
  }

  /// La sección "respuesta correcta" solo aparece cuando NO se pudo marcar
  /// la corrección directamente sobre las opciones (p.ej. match, o feedback
  /// sin rightanswer revelado por fila).
  bool get _showRightAnswer =>
      _data.rightAnswerHtml.trim().isNotEmpty &&
      !_data.options.any((o) => o.isCorrect);

  @override
  Widget build(BuildContext context) {
    final stateColor = _stateColor(_data.state);

    return Container(
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Borde izquierdo del color del estado (marcador visual rápido).
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: stateColor),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(stateColor),
                  const SizedBox(height: 16),
                  // ✅ v1.7.1: Contenido enriquecido — imágenes inline,
                  // tablas nativas y matemáticas, en el orden del documento.
                  // El enunciado llega limpio desde el parser (sin regex).
                  MoodleRichText(
                    html: _data.questionHtml,
                    onImageTap: _openGallery,
                  ),
                  if (_data.hasOptions) ...[
                    const SizedBox(height: 12),
                    _buildOptions(),
                  ],
                  if (_showRightAnswer) ...[
                    const SizedBox(height: 12),
                    _buildRightAnswer(),
                  ],
                  _buildFeedbackSection(stateColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color stateColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Chip con el número de la pregunta.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Pregunta ${widget.questionNumber}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        // Badge de estado con icono.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: stateColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_stateIcon(_data.state), size: 16, color: stateColor),
              const SizedBox(width: 6),
              Text(
                _stateLabel(_data.state),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: stateColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOptions() {
    final options = _data.options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < options.length; i++)
          QuestionOptionTile(
            letter: String.fromCharCode(65 + i),
            labelHtml: options[i].labelHtml,
            isUserSelected: options[i].isUserSelected,
            isCorrect: options[i].isCorrect,
          ),
      ],
    );
  }

  Widget _buildRightAnswer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.successLight.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.successDark.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 16,
                color: AppColors.successDeep,
              ),
              SizedBox(width: 6),
              Text(
                'La respuesta correcta es:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.successDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          MoodleRichText(
            html: _data.rightAnswerHtml,
            maxImageHeight: 180,
            onImageTap: _openGallery,
          ),
        ],
      ),
    );
  }

  /// Sección "Retroalimentación": combina specificfeedback + feedback +
  /// generalfeedback (cada uno solo si no está vacío) y grade como chip
  /// final. Expandible/colapsable, expandida por defecto.
  Widget _buildFeedbackSection(Color stateColor) {
    final blocks = <String>[
      if (_data.specificFeedbackHtml.trim().isNotEmpty)
        _data.specificFeedbackHtml,
      if (_data.feedbackHtml.trim().isNotEmpty) _data.feedbackHtml,
      if (_data.generalFeedbackHtml.trim().isNotEmpty)
        _data.generalFeedbackHtml,
    ];
    final gradeHtml = _data.gradeHtml.trim();

    if (blocks.isEmpty && gradeHtml.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(height: 1, thickness: 1, color: AppColors.border),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _feedbackExpanded = !_feedbackExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 20,
                      color: stateColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Retroalimentación',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: stateColor,
                      ),
                    ),
                  ],
                ),
                Icon(
                  _feedbackExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: stateColor,
                ),
              ],
            ),
          ),
        ),
        if (_feedbackExpanded)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: _buildFeedbackBody(blocks, gradeHtml),
          ),
      ],
    );
  }

  Widget _buildFeedbackBody(List<String> blocks, String gradeHtml) {
    final feedbackColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: AppColors.border.withOpacity(0.6)),
            const SizedBox(height: 10),
          ],
          MoodleRichText(
            html: blocks[i],
            maxImageHeight: 180,
            onImageTap: _openGallery,
          ),
        ],
        // Calificación tipo "Se puntúa 1,00/1,00" como chip sutil al final.
        if (gradeHtml.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceClean,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: MoodleRichText(html: gradeHtml),
          ),
        ],
      ],
    );

    // Altura completamente adaptable por defecto; solo para contenido
    // extremadamente largo se limita la altura con scroll interno.
    const scrollThreshold = 1500;
    final totalLength = blocks.fold<int>(
          0,
          (acc, block) => acc + block.length,
        ) +
        gradeHtml.length;
    if (totalLength > scrollThreshold) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 4),
          child: feedbackColumn,
        ),
      );
    }
    return feedbackColumn;
  }
}