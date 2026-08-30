import '../config/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../core/theme/app_colors.dart';
import '../widgets/math/math_text.dart';

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

class _ReviewScreenState extends State<ReviewScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  bool _statsSent = false;
  final List<int> _simuIds = const [
    2, 3, 18, 24, 25, 26, 27, 28, 29, 30, 31
  ];

  // ==========================
  //   MÉTODOS DE UTILIDAD
  // ==========================

  List<String> _extractImageUrls(String htmlText) {
    final exp = RegExp(
      r'''<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*>''',
      caseSensitive: false,
    );
    final urls = exp.allMatches(htmlText).map((m) => m.group(1)!).toList();
    return urls.where((u) => !u.contains('/i/unflagged')).toList();
  }

  String _removeImageTagsAndHeaders(String htmlText) {
    return htmlText
        .replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'<div[^>]*class="grade"[^>]*>.*?<\/div>',
                caseSensitive: false, dotAll: true),
            '')
        .replaceAll(
            RegExp(r'<h3[^>]*>.*?<\/h3>',
                caseSensitive: false, dotAll: true),
            '')
        .trim();
  }

  String _proxyUrl(String src) {
    final encoded = Uri.encodeFull(src);
    return '${Env.apiBaseUrl}/get_file.php?url=$encoded';
  }

  String _extractState(String htmlText) {
    final low = htmlText.toLowerCase();

    if (low.contains('class="que multichoice deferredfeedback correct"') ||
        low.contains('gradedright')) {
      return 'Correcta';
    }
    if (low.contains('class="que multichoice deferredfeedback incorrect"') ||
        low.contains('gradedwrong')) {
      return 'Incorrecta';
    }
    if (low.contains('no contest') ||
        low.contains('sin responder') ||
        low.contains('not answered')) {
      return 'Sin responder';
    }

    return 'Sin responder';
  }

  Color _stateColor(String s) {
    s = s.toLowerCase();
    if (s == 'correcta') return AppColors.successDark;
    if (s == 'incorrecta') return AppColors.error;
    return AppColors.warning;
  }

  String _extractFeedback(String htmlText) {
    final exp =
        RegExp(r'<div[^>]*class="feedback"[^>]*>([\s\S]*?)<\/div>',
            caseSensitive: false);
    final match = exp.firstMatch(htmlText);
    String content = match != null ? match.group(1)!.trim() : '';

    content = content
        .replaceAll(RegExp(r'Se\s*punt(úa|ua).*?[\.]?',
            caseSensitive: false), '')
        .replaceAll(RegExp(r'\bCorrecta\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bIncorrecta\b', caseSensitive: false), '')
        .trim();

    return content;
  }

  /// ✅ FASE 4.2: Renderizado mejorado — delega al widget MathText.
  Widget _renderHtmlWithMath(String htmlText, {bool isFeedback = false}) {
    return MathText(
      html: htmlText,
      isOption: isFeedback, // isFeedback usa tamaño de opción (más pequeño)
    );
  }

  void _openImageGallery(
      BuildContext context, List<String> urls, int index) {
    if (urls.isEmpty) return;
    final proxy = urls.map(_proxyUrl).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: AppColors.textSecondary,
            elevation: 0,
            iconTheme: const IconThemeData(color: AppColors.textOnPrimary),
          ),
          body: PhotoViewGallery.builder(
            itemCount: proxy.length,
            pageController: PageController(initialPage: index),
            builder: (_, i) => PhotoViewGalleryPageOptions(
              imageProvider: NetworkImage(proxy[i]),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
            ),
            backgroundDecoration: BoxDecoration(color: Colors.black),
            loadingBuilder: (context, event) => Center(
              child: CircularProgressIndicator(
                value: event == null
                    ? 0
                    : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
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
        case 0: return AppColors.primaryLight; // Lectura crítica
        case 1: return AppColors.successDark; // Matemáticas
        case 2: return AppColors.purple; // Ciencias sociales
        case 3: return AppColors.warning; // Ciencias naturales
        case 4: return AppColors.error; // Inglés
      }
    }
    
    // Color por defecto
    return AppColors.textMuted;
  }

  double _pageScore(List<Map<String, dynamic>> qs) {
    if (qs.isEmpty) return 0;
    final correct =
        qs.where((q) => _extractState(q['html']) == 'Correcta').length;
    return (correct / qs.length) * 100.0;
  }

  int _pageCorrectCount(List<Map<String, dynamic>> qs) {
    return qs.where((q) => _extractState(q['html']) == 'Correcta').length;
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
    
    final qs = widget.reviewData['questions'] ?? [];
    final pages = <int>{};
    for (final q in qs) pages.add(q['page'] ?? 0);

    if (pages.length > 1) {
      _tabController = TabController(length: pages.length, vsync: this);
    }
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
    debugPrint("[STATS] No es simulacro (courseId $courseId no está en _simuIds)");
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
        final correct = questions.where((q) => _extractState(q['html']) == 'Correcta').length;
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
      
      final globalScore = ((lectura * 3 + matematicas * 3 + sociales * 3 + naturales * 3 + ingles * 1) / 13) * 5;
      
      // Calcular tiempo empleado en minutos
      int tiempoEmpleado = 0;
      if (attempt['timefinish'] != null && attempt['timestart'] != null) {
        final tiempoSegundos = attempt['timefinish'] - attempt['timestart'];
        tiempoEmpleado = (tiempoSegundos / 60).round();
      } else {
        // Intentar obtener tiempo de otra fuente
        final tiempo = attempt['timeused'] ?? attempt['time'] ?? attempt['tiempo'] ?? 0;
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
    } catch (e) {
      debugPrint("[STATS] Error guardando estadísticas: $e");
    }
  }

  // ==========================
  //   MÉTODOS DE CONSTRUCCIÓN
  // ==========================

  Widget _buildQuestionList(
      List<Map<String, dynamic>> qs, int page, bool isMulti, int totalPages) {
    final correct = qs.where((q) => _extractState(q['html']) == 'Correcta').length;
    final total = qs.length;
    final score = (correct / total) * 100;
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
                            border: Border.all(color: areaColor.withOpacity(0.3)),
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
              
              ...qs.asMap().entries.map((entry) {
                final index = entry.key;
                final q = entry.value;
                final html = q['html'] ?? '';
                final clean = _removeImageTagsAndHeaders(html);
                final imgs = _extractImageUrls(html);
                final state = _extractState(html);
                final color = _stateColor(state);
                final feedback = _extractFeedback(html);
                final hasFeedback = feedback.isNotEmpty;
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: _QuestionCard(
                    questionNumber: q['slot'] ?? (index + 1),
                    questionHtml: clean,
                    state: state,
                    stateColor: color,
                    images: imgs,
                    feedback: feedback,
                    hasFeedback: hasFeedback,
                    onImageTap: (imgIndex) => _openImageGallery(context, imgs, imgIndex),
                    renderHtmlWithMath: (html) => _renderHtmlWithMath(html),
                    renderFeedbackWithMath: (html) => _renderHtmlWithMath(html, isFeedback: true),
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
          Navigator.pop(context, true);
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
                color: isOverdue
                    ? AppColors.errorDark
                    : AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    ),
    body: _buildQuestionList(questions, page, false, totalPages),
  );
}


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
            Navigator.pop(context, true);
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
      body: TabBarView(
        children: sortedPages
            .map((p) => _buildQuestionList(grouped[p]!, p, true, totalPages))
            .toList(),
      ),
    ),
  );
}


  @override
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
  final totalPages = sortedPages.length;
  final isMulti = totalPages > 1;
  final globalScore = isMulti && totalPages == 5 ? _globalScore(grouped) : 0.0;

  // Guardar estadísticas si es un simulacro y aún no se han guardado
  if (!_statsSent && _simuIds.contains(widget.courseId)) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendStatsIfNeeded(grouped, sortedPages);
    });
  }

  return WillPopScope(
    onWillPop: () async {
      Navigator.pop(context, true);
      return false;
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

class _QuestionCard extends StatefulWidget {
  final int questionNumber;
  final String questionHtml;
  final String state;
  final Color stateColor;
  final List<String> images;
  final String feedback;
  final bool hasFeedback;
  final Function(int) onImageTap;
  final Widget Function(String) renderHtmlWithMath;
  final Widget Function(String) renderFeedbackWithMath;

  const _QuestionCard({
    required this.questionNumber,
    required this.questionHtml,
    required this.state,
    required this.stateColor,
    required this.images,
    required this.feedback,
    required this.hasFeedback,
    required this.onImageTap,
    required this.renderHtmlWithMath,
    required this.renderFeedbackWithMath,
  });

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
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
        border: Border.all(
          color: widget.stateColor.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER DE LA PREGUNTA
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.stateColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.state == 'Correcta'
                                ? Icons.check_circle_rounded
                                : widget.state == 'Incorrecta'
                                    ? Icons.cancel_rounded
                                    : Icons.error_outline_rounded,
                            size: 16,
                            color: widget.stateColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Pregunta ${widget.questionNumber}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: widget.stateColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.stateColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        widget.state,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: widget.stateColor,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                // IMÁGENES (SI HAY)
                if (widget.images.isNotEmpty)
                  Column(
                    children: [
                      SizedBox(
                        height: 140,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.images.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, index) {
                            final src = widget.images[index];
                            return GestureDetector(
                              onTap: () => widget.onImageTap(index),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    Image.network(
                                      '${Env.apiBaseUrl}/get_file.php?url=${Uri.encodeFull(src)}',
                                      fit: BoxFit.cover,
                                      height: 140,
                                      width: 180,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Container(
                                          width: 180,
                                          height: 140,
                                          color: AppColors.surfaceVariant,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              value: loadingProgress.expectedTotalBytes != null
                                                  ? loadingProgress.cumulativeBytesLoaded /
                                                      loadingProgress.expectedTotalBytes!
                                                  : null,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: AppColors.overlay,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Icon(
                                          Icons.zoom_in_rounded,
                                          size: 16,
                                          color: AppColors.textOnPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                
                // CONTENIDO DE LA PREGUNTA
                widget.renderHtmlWithMath(widget.questionHtml),
              ],
            ),
          ),
          
          // FEEDBACK (COLLAPSIBLE)
          if (widget.hasFeedback)
            Column(
              children: [
                Divider(height: 0),
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceClean,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      border: Border.all(
                        color: AppColors.border,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.lightbulb_outline_rounded,
                              size: 20,
                              color: widget.stateColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Retroalimentación',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: widget.stateColor,
                              ),
                            ),
                          ],
                        ),
                        Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: widget.stateColor,
                        ),
                      ],
                    ),
                  ),
                ),
                
                if (_expanded)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceClean,
                      border: Border.all(
                        color: AppColors.border,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        widget.renderFeedbackWithMath(widget.feedback),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
    }
}