import '../config/env.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../controllers/quiz_controller.dart';
import '../models/answer_option.dart';
import 'review_screen.dart';
import 'dart:async';
import '../core/theme/app_colors.dart';


class QuestionScreen extends StatefulWidget {
  final QuizController controller;
  final int courseId;

  const QuestionScreen({
    Key? key,
    required this.controller,
    required this.courseId,
  }) : super(key: key);

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  final Map<int, String?> _localSelection = {};
  bool _isSubmitting = false;
  bool _navigatedToReview = false;
  TabController? _tabController;
  Timer? _statusCheckTimer;

  @override
void initState() {
  super.initState();
  
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Primero verificar si el intento sigue activo
    await _checkAttemptStatus();
    
       // Iniciar verificación periódica cada 30 segundos
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkAttemptStatus();
    });

    // Si no fue redirigido, continuar con la inicialización normal
    if (!mounted) return;
    
    _initTabs();
    if (_pageController.hasClients) {
      _pageController.jumpToPage(widget.controller.currentPage);
    }
    for (final entry in widget.controller.answers.entries) {
      _localSelection[entry.key] = entry.value;
    }
    setState(() {});
  });
}

  void _initTabs() {
    final c = widget.controller;
    if (!c.hasMultipleSections) {
      debugPrint('>>> Solo un bloque, sin pestañas');
      return;
    }

    final sections = c.areaNames;
    debugPrint('>>> Construyendo pestañas: $sections');
    _tabController =
        TabController(length: sections.length, vsync: this, initialIndex: 0);

    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) {
        final targetArea = sections[_tabController!.index];
        final index = c.getFirstQuestionIndexOfArea(targetArea);
        if (index != null) _navigateTo(index);
      }
    });
  }

// ==========================================
// VERIFICACIÓN DE ESTADO DEL INTENTO
// ==========================================

Future<void> _checkAttemptStatus() async {
  final c = widget.controller;
  
  // Si no hay attempt, algo está mal
  if (c.attempt == null) return;
  
  try {
    // Obtener datos actualizados del intento
    final attemptData = await c.api.fetchAttemptData(c.attempt!.id);
    final timefinish = attemptData['timefinish'] ?? 0;
    final reviewMode = attemptData['reviewMode'] ?? false;
    final timelimit = attemptData['timelimit'] ?? 0;
    final timestart = attemptData['timestart'] ?? 0;
    
    // Calcular si el tiempo ha expirado
    bool timeExpired = false;
    if (timelimit > 0 && timestart > 0) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final elapsed = now - timestart;
      final remaining = timelimit - elapsed;
      timeExpired = remaining <= 0;
      
      debugPrint("[CHECK_STATUS] now: $now, elapsed: $elapsed, remaining: $remaining, timeExpired: $timeExpired");
    }
    
    // Si timefinish > 0, está en modo revisión, o el tiempo expiró, redirigir a review
      if (timefinish > 0 || reviewMode || timeExpired) {
      debugPrint("[CHECK_STATUS] Redirigiendo a review. timefinish: $timefinish, reviewMode: $reviewMode, timeExpired: $timeExpired");
      
      // Obtener datos de revisión
      final reviewData = c.reviewData ?? await c.api.reviewAttempt(c.attempt!.id);
      
      if (!mounted) return;
      
      // Redirigir directamente a review screen
      Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (_) => ReviewScreen(
      reviewData: reviewData,
      courseId: widget.courseId,
      quizId: widget.controller.quizId, // ¡NUEVO!
    ),
  ),
);
    }
  } catch (e) {
    debugPrint("Error verificando estado del intento: $e");
  }
}


  void _syncTabWithPage() {
    final c = widget.controller;
    if (_tabController == null || !c.hasMultipleSections) return;

    final currentIndex = c.getAreaForQuestion(c.currentPage) != null
        ? c.areaNames.indexOf(c.getAreaForQuestion(c.currentPage)!)
        : 0;
    if (_tabController!.index != currentIndex && currentIndex >= 0) {
      _tabController!.animateTo(currentIndex);
    }
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    _pageController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  String _fmt(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _proxyUrl(String src) {
    final encoded = Uri.encodeFull(src);
    return '${Env.apiBaseUrl}/get_file.php?url=$encoded';
  }

  List<String> _extractImageUrls(String htmlText) {
    final exp = RegExp(r'''<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*>''',
        caseSensitive: false);
    return exp.allMatches(htmlText).map((m) => m.group(1)!).toList();
  }

  String _removeImageTags(String htmlText) {
    final exp = RegExp(r'''<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*>''',
        caseSensitive: false);
    return htmlText.replaceAll(exp, '');
  }

Widget _renderHtmlWithMath(String htmlText, {bool isOption = false}) {
  final widgets = <Widget>[];
  final regex = RegExp(r'(\\\(.+?\\\)|\\\[.+?\\\])', dotAll: true);
  final matches = regex.allMatches(htmlText);

  if (matches.isEmpty) {
    return Html(
      data: htmlText,
      style: {
        "body": Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontSize: FontSize(isOption ? 14.0 : 16.0),
          lineHeight: LineHeight(isOption ? 1.3 : 1.5),
          color: AppColors.borderDark,
        ),
        "p": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
      },
    );
  }

  int last = 0;
  for (final match in matches) {
    // Texto antes de la ecuación
    if (match.start > last) {
      final text = htmlText.substring(last, match.start);
      if (text.trim().isNotEmpty) {
        widgets.add(Html(
          data: text,
          style: {
            "body": Style(
              margin: Margins.zero,
              padding: HtmlPaddings.zero,
              fontSize: FontSize(isOption ? 14.0 : 16.0),
              lineHeight: LineHeight(isOption ? 1.3 : 1.5),
              color: AppColors.borderDark,
            ),
          },
        ));
      }
    }

    // La ecuación en sí (SIN CONTENEDOR)
    final latex = match.group(0)!
        .replaceAll(r'\(', '')
        .replaceAll(r'\)', '')
        .replaceAll(r'\[', '')
        .replaceAll(r'\]', '');

    widgets.add(
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: isOption ? 2 : 4),
        child: Math.tex(
          latex,
          textStyle: TextStyle(
            fontSize: isOption ? 14 : 16,
          ),
        ),
      ),
    );

    last = match.end;
  }

  // Texto después de la última ecuación
  if (last < htmlText.length) {
    final text = htmlText.substring(last);
    if (text.trim().isNotEmpty) {
      widgets.add(Html(
        data: text,
        style: {
          "body": Style(
            margin: Margins.zero,
            padding: HtmlPaddings.zero,
            fontSize: FontSize(isOption ? 14.0 : 16.0),
            lineHeight: LineHeight(isOption ? 1.3 : 1.5),
            color: AppColors.borderDark,
          ),
        },
      ));
    }
  }

  return Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 2,
    runSpacing: 2,
    children: widgets,
  );
}

  void _openImageGallery(BuildContext context, List<String> urls, int index) {
    if (urls.isEmpty) return;
    final proxyUrls = urls.map(_proxyUrl).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.textSecondary,
            elevation: 0,
            iconTheme: const IconThemeData(color: AppColors.textOnPrimary),
          ),
          backgroundColor: Colors.black,
          body: PhotoViewGallery.builder(
            itemCount: proxyUrls.length,
            pageController: PageController(initialPage: index),
            builder: (_, i) => PhotoViewGalleryPageOptions(
              imageProvider: NetworkImage(proxyUrls[i]),
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

/// ✅ FIX #8: Navegación instantánea entre preguntas.
///
/// Antes: cada navegación hacía `fetchAttemptData` + `flushPendingForSlot`
/// esperando respuesta del backend → 1-3 segundos de retraso.
///
/// Ahora:
/// - No verifica el estado del intento en cada navegación (ya hay un timer
///   cada 30s que lo hace en `_checkAttemptStatus`).
/// - El envío de la respuesta pendiente se dispara en background
///   (fire-and-forget) dentro de `c.navigateToPage()`.
/// - La animación del PageView es más rápida (200ms en lugar de 300ms).
/// - Si hay algo enviándose en background, se muestra un indicador sutil
///   en la barra superior pero NO bloquea la navegación.
Future<void> _navigateTo(int index) async {
  final c = widget.controller;
  if (_isSubmitting) return; // solo bloquear si está finalizando

  // Verificación barata: si ya sabemos que el intento está cerrado, ir a review
  // (sin hacer petición al backend — el timer de 30s ya lo detectó)
  if (c.isFinished) {
    if (!mounted) return;
    final reviewData = c.reviewData;
    if (reviewData != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            reviewData: reviewData,
            courseId: widget.courseId,
            quizId: widget.controller.quizId,
          ),
        ),
      );
    }
    return;
  }

  // Navegación instantánea: el controller dispara el flush en background
  await c.navigateToPage(index);

  // Animación suave y rápida del PageView
  if (!mounted) return;
  if (_pageController.hasClients) {
    await _pageController.animateToPage(
      c.currentPage,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }
  _syncTabWithPage();
}

/// ✅ FIX #8: Finalización optimizada del intento.
///
/// Antes: hacía `fetchAttemptData` para verificar si ya estaba cerrado
/// (redundante porque el timer de 30s ya lo hace) → 1-2s extra.
///
/// Ahora:
/// - Si el controller ya sabe que está finalizado, va directo a review.
/// - Si no, hace flush + finish en background mostrando un diálogo de progreso.
Future<void> _finishFlow() async {
  final c = widget.controller;
  if (_isSubmitting) return;

  setState(() => _isSubmitting = true);

  // Caso A: el intento ya está cerrado (detectado por el timer de 30s)
  if (c.isFinished && c.reviewData != null) {
    if (!mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          reviewData: c.reviewData!,
          courseId: widget.courseId,
          quizId: c.quizId,
        ),
      ),
    );
    if (mounted) Navigator.pop(context, true);
    if (mounted) setState(() => _isSubmitting = false);
    return;
  }

  // Caso B: finalizar el intento ahora
  // Mostrar diálogo de progreso no cancelable
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Finalizando simulacro...',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Calculando tu puntaje',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  try {
    await c.flushAllPending();
    await c.finish();

    if (!mounted) return;
    Navigator.pop(context); // cerrar diálogo de progreso

    if (!_navigatedToReview) {
      _navigatedToReview = true;
      final reviewData = c.reviewData ?? await c.api.reviewAttempt(c.attempt!.id);
      if (!mounted) return;

      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => ReviewScreen(
            reviewData: reviewData,
            courseId: widget.courseId,
            quizId: c.quizId,
          ),
        ),
      );

      if (mounted) Navigator.pop(context, true);
    }
  } catch (e) {
    if (!mounted) return;
    Navigator.pop(context); // cerrar diálogo de progreso
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Error: $e'),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
    ));
  } finally {
    if (mounted) setState(() => _isSubmitting = false);
  }
}

  bool _isAnsweredForSlot(int slot) {
    final c = widget.controller;
    final value = c.answers[slot];
    return value != null && value != '-1' && value.toString().trim().isNotEmpty;
  }

Future<void> _openAttemptMap() async {
  debugPrint('>>> Intentando abrir mapa de intento...');
  final c = widget.controller;
  if (c.questions.isEmpty) return;
  if (!mounted) return;

  await showDialog(
    context: context,
    builder: (_) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowLg,
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Mapa del cuestionario',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: AppColors.textTertiary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Divider(height: 0),
              // Ajuste: envolver el grid en Flexible + SingleChildScrollView
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: c.totalPages,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      childAspectRatio: 1.0,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemBuilder: (_, index) {
                      final slot = c.questions[index].slot;
                      final value = c.answers[slot];
                      final answered = value != null &&
                          value != '-1' &&
                          value.toString().trim().isNotEmpty;
                      final isCurrent = index == c.currentPage;

                      Color bgColor;
                      Color textColor;
                      if (isCurrent) {
                        bgColor = AppColors.primary;
                        textColor = AppColors.textOnPrimary;
                      } else if (answered) {
                        bgColor = AppColors.successDark;
                        textColor = AppColors.textOnPrimary;
                      } else {
                        bgColor = AppColors.surfaceVariant;
                        textColor = AppColors.textTertiary;
                      }

                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          _navigateTo(index);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(10),
                            border: isCurrent
                                ? Border.all(color: AppColors.textOnPrimary, width: 2)
                                : null,
                            boxShadow: isCurrent
                                ? [
                                    BoxShadow(
                                      color: AppColors.primary
                                          .withOpacity(0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Actual',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textTertiary)),
                    const SizedBox(width: 16),
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.successDark,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Respondida',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textTertiary)),
                    const SizedBox(width: 16),
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Pendiente',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _confirmFinish() async {
  if (!mounted) return;
  if (_isSubmitting) return;

  final c = widget.controller;
  final total = c.questions.length;
  int answeredCount = 0;

  // Lista de índices de preguntas no respondidas
  final List<int> unansweredIndices = [];
  for (int i = 0; i < c.questions.length; i++) {
    final q = c.questions[i];
    if (_isAnsweredForSlot(q.slot)) {
      answeredCount++;
    } else {
      unansweredIndices.add(i);
    }
  }

  await showDialog(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowLg,
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      answeredCount == total
                          ? Icons.check_circle_outline_rounded
                          : Icons.warning_amber_rounded,
                      size: 48,
                      color: answeredCount == total
                          ? AppColors.successDark
                          : AppColors.warning,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      answeredCount == total
                          ? '¡Cuestionario completo!'
                          : '¿Finalizar cuestionario?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Has respondido $answeredCount de $total preguntas.',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (unansweredIndices.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${unansweredIndices.length} pregunta(s) sin responder',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.errorDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 0),
              if (unansweredIndices.isNotEmpty)
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.3,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: unansweredIndices.length,
                    itemBuilder: (_, index) {
                      final questionIndex = unansweredIndices[index];
                      return ListTile(
                        dense: true,
                        minLeadingWidth: 0,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        leading: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppColors.errorFaint,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: AppColors.errorDark,
                          ),
                        ),
                        title: Text(
                          'Pregunta ${questionIndex + 1}',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        subtitle: const Text(
                          'Sin responder',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Ir a pregunta',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _navigateTo(questionIndex);
                        },
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textTertiary,
                          side: BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Continuar respondiendo'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _finishFlow();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textOnPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: const Text('Finalizar ahora'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _buildTimer() {
  return ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final hasTime = c.hasTimeLimit && c.remainingSeconds != null;
      final remaining = c.remainingSeconds ?? 0;
      final total = c.timeLimitSeconds ?? 1;
      final percent = (total > 0) ? (remaining / total) : 0.0;

if (!hasTime) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'Sin límite',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textTertiary,
      ),
    ),
  );
}

// Si el tiempo restante es 0 o negativo, el intento podría estar vencido
if (remaining <= 0) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.errorLight,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      'Tiempo agotado',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.errorDark,
      ),
    ),
  );
}

      Color timerColor;
      if (remaining <= 60) {
        timerColor = AppColors.errorDark;
      } else if (remaining <= 300) {
        timerColor = AppColors.warning;
      } else {
        timerColor = AppColors.successDark;
      }

      // Formatear tiempo para mostrar
      final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
      final seconds = (remaining % 60).toString().padLeft(2, '0');
      final displayTime = '$minutes:$seconds';

      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowSm,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: percent.clamp(0.0, 1.0),
                    strokeWidth: 4,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                  ),
                  Text(
                    displayTime.split(':')[1], // Segundos
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: timerColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayTime,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: timerColor,
                  ),
                ),
                Text(
                  '${(remaining ~/ 60)} min',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textDisabled,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        if (c.isLoading || c.questions.isEmpty) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Cargando preguntas...',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final progress = (c.currentPage + 1) / c.totalPages;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients &&
              _pageController.page?.round() != c.currentPage) {
            _pageController.jumpToPage(c.currentPage);
          }
          _syncTabWithPage();
        });

        final showTabs = c.hasMultipleSections && _tabController != null;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 1,
            centerTitle: false,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.quizName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${c.currentPage + 1} de ${c.totalPages} preguntas',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            actions: [
  Padding(
    padding: const EdgeInsets.only(right: 12),
    child: _buildTimer(),
  ),
],
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(showTabs ? 88 : 48),
              child: Column(
                children: [
                  if (showTabs)
                    Container(
                      color: AppColors.surface,
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        labelColor: AppColors.primary,
                        unselectedLabelColor: AppColors.textTertiary,
                        indicatorColor: AppColors.primary,
                        indicatorWeight: 2.5,
                        indicatorSize: TabBarIndicatorSize.label,
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        unselectedLabelStyle: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                        tabs: c.areaNames
                            .map((a) => Tab(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    child: Text(
                                      a,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: progress,
                          backgroundColor: AppColors.border,
                          color: AppColors.primary,
                          minHeight: 5,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Progreso',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                              ),
                            ),
                            Text(
                              '${(progress * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: c.totalPages,
                  itemBuilder: (_, index) => _buildQuestionPage(index),
                ),
              ),
              // 🔹 BOTONES INFERIORES MEJORADOS
              SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 8),
                child: Container(
                  color: AppColors.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: c.currentPage > 0 && !_isSubmitting
                              ? () => _navigateTo(c.currentPage - 1)
                              : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textTertiary,
                            side: BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            minimumSize: const Size(0, 44),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chevron_left_rounded, size: 18),
                              SizedBox(width: 4),
                              Text('Anterior', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: !_isSubmitting ? _openAttemptMap : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textTertiary,
                            side: BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            minimumSize: const Size(0, 44),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.grid_view_rounded, size: 18),
                              SizedBox(width: 4),
                              Text('Mapa', style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSubmitting
                              ? null
                              : () async {
                                  final isLast = c.currentPage == c.totalPages - 1;
                                  if (isLast) {
                                    await _confirmFinish();
                                  } else {
                                    await _navigateTo(c.currentPage + 1);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.textOnPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            minimumSize: const Size(0, 44),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                c.currentPage == c.totalPages - 1
                                    ? 'Finalizar'
                                    : 'Siguiente',
                                style: TextStyle(fontSize: 13),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                c.currentPage == c.totalPages - 1
                                    ? Icons.flag_rounded
                                    : Icons.chevron_right_rounded,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuestionPage(int index) {
    final c = widget.controller;
    final q = c.questions[index];
    final questionImages = _extractImageUrls(q.questionText);
    final questionHtmlNoImgs = _removeImageTags(q.questionText);
    final slot = q.slot;
    _localSelection.putIfAbsent(slot, () => c.answers[slot]);
    final hasOptions = q.options.isNotEmpty;

    String _cleanOptionText(String html) {
      final regex = RegExp(r'^[a-zA-Z]\.\s*');
      final text = _removeImageTags(html);
      return text.replaceAll(regex, '');
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado de la pregunta
          Container(
            padding: const EdgeInsets.all(16),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Pregunta ${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isAnsweredForSlot(slot)
                            ? AppColors.successLight
                            : AppColors.errorFaint,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _isAnsweredForSlot(slot) ? 'Respondida' : 'Sin responder',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _isAnsweredForSlot(slot)
                              ? AppColors.successDeep
                              : AppColors.errorDeep,
                        ),
                      ),
                    ),
                  ],
                ),
// 🔥 TAGS DE LA PREGUNTA
if (q.tags != null && q.tags.isNotEmpty) ...[
  Wrap(
    spacing: 6,
    runSpacing: 6,
    children: q.tags.map<Widget>((tag) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.explanationBg, // azul suave
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          tag,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppColors.explanationText,
          ),
        ),
      );
    }).toList(),
  ),
  const SizedBox(height: 12),
],

                const SizedBox(height: 16),
                
                // Imágenes de la pregunta
                if (questionImages.isNotEmpty)
                  Column(
                    children: [
                      SizedBox(
                        height: 130,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: questionImages.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (_, i) => GestureDetector(
                            onTap: () =>
                                _openImageGallery(context, questionImages, i),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Stack(
                                children: [
                                  Image.network(
                                    _proxyUrl(questionImages[i]),
                                    fit: BoxFit.cover,
                                    height: 130,
                                    width: 160,
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        width: 160,
                                        height: 130,
                                        color: AppColors.surfaceVariant,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            value: loadingProgress.expectedTotalBytes !=
                                                    null
                                                ? loadingProgress
                                                        .cumulativeBytesLoaded /
                                                    loadingProgress.expectedTotalBytes!
                                                : null,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: AppColors.overlay,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Icon(
                                        Icons.zoom_in_rounded,
                                        size: 14,
                                        color: AppColors.textOnPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                
                // Texto de la pregunta con matemáticas
                _renderHtmlWithMath(questionHtmlNoImgs),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Opciones de respuesta
          if (hasOptions)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'Selecciona la respuesta correcta:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                ...q.options.asMap().entries.map((entry) {
                  final i = entry.key;
                  final opt = entry.value;
                  final optHtmlNoImgs = _cleanOptionText(opt.labelHtml);
                  final letter = String.fromCharCode(65 + i);
                  final isSelected = _localSelection[slot] == opt.value;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: isSelected
                          ? AppColors.explanationBg
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 1,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _localSelection[slot] = opt.value;
                          });
                          widget.controller.markPending(slot, opt.value);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.border,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                margin: const EdgeInsets.only(top: 2),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.border,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    letter,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: isSelected
                                          ? AppColors.textOnPrimary
                                          : AppColors.textTertiary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Opción con matemáticas (versión compacta)
                                    _renderHtmlWithMath(optHtmlNoImgs, isOption: true),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textSubtle,
                                    width: 1.5,
                                  ),
                                ),
                                child: isSelected
                                    ? Container(
                                        margin: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.primary,
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}