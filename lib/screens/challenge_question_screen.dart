import '../config/env.dart';
// lib/screens/challenge_question_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../services/api_service.dart';
import '../controllers/quiz_controller.dart';
import 'challenge_results_screen.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/app_logger.dart';

class ChallengeQuestionScreen extends StatefulWidget {
  final ApiService api;
  final int challengeId;
  final int attemptId;
  final int quizId;
  final int durationMinutes;
  final int? courseId;
  final DateTime? startedAt;
  final DateTime? endTimeGlobal;

  const ChallengeQuestionScreen({
    Key? key,
    required this.api,
    required this.challengeId,
    required this.attemptId,
    required this.quizId,
    required this.durationMinutes,
    this.courseId,
    this.startedAt,
    this.endTimeGlobal,
  }) : super(key: key);

  @override
  State<ChallengeQuestionScreen> createState() => _ChallengeQuestionScreenState();
}

class _ChallengeQuestionScreenState extends State<ChallengeQuestionScreen> {
  final PageController _pageController = PageController();
  late QuizController controller;
  final Map<int, String?> _localSelection = {};
  Timer? _countdownTimer;
  Timer? _syncTimer;
  int _remainingSeconds = 0;
  late final int _totalSeconds;
  bool _isSubmitting = false;
  bool _navigatedToResults = false;
  bool _loadingQuiz = true;
  bool _timeExpired = false;
  String? _loadError;
  int _timeDrift = 0;

  @override
  void initState() {
    super.initState();

    controller = QuizController(
      api: widget.api,
      quizId: widget.quizId,
      quizName: 'Reto ${widget.challengeId}',
      courseId: widget.courseId,
    );

    _totalSeconds = widget.durationMinutes * 60;

    // Usar el tiempo del servidor si está disponible
    if (widget.endTimeGlobal != null) {
      final serverEndTime = widget.endTimeGlobal!.toUtc();
      final nowUtc = DateTime.now().toUtc();
      _remainingSeconds = serverEndTime.difference(nowUtc).inSeconds;
      
      if (widget.api.lastSyncTime != null && widget.api.lastServerTime != null) {
        final localTimeAtSync = widget.api.lastSyncTime!;
        final serverTimeAtSync = widget.api.lastServerTime!;
        final timeDrift = localTimeAtSync.difference(serverTimeAtSync).inSeconds;
        _remainingSeconds -= timeDrift;
        _timeDrift = timeDrift;
      }
      
      if (_remainingSeconds < 0) _remainingSeconds = 0;
    } else if (widget.startedAt != null) {
      final endUtc = widget.startedAt!.toUtc().add(
        Duration(minutes: widget.durationMinutes),
      );
      final nowUtc = DateTime.now().toUtc();
      _remainingSeconds = endUtc.difference(nowUtc).inSeconds;
      if (_remainingSeconds < 0) _remainingSeconds = 0;
    } else {
      _remainingSeconds = _totalSeconds;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await controller.start();

        if (controller.questions.isEmpty) {
          _loadError = 'Este reto no tiene preguntas';
        }
      } catch (e) {
        _loadError = 'Error cargando el cuestionario';
      } finally {
        _loadingQuiz = false;
        if (mounted) setState(() {});
      }

      if (_loadError != null) return;

      for (final entry in controller.answers.entries) {
        _localSelection[entry.key] = entry.value;
      }

      if (_pageController.hasClients) {
        _pageController.jumpToPage(controller.currentPage);
      }

      controller.addListener(_onControllerChanged);
      _startCountdown();
      _startSyncTimer();
    });
  }

  void _onControllerChanged() {
    if (!mounted) return;

    bool needSetState = false;
    controller.answers.forEach((slot, value) {
      final cur = _localSelection[slot];
      if (cur != value) {
        _localSelection[slot] = value;
        needSetState = true;
      }
    });

    final controllerPage = controller.currentPage;
    if (_pageController.hasClients && (_pageController.page?.round() ?? controllerPage) != controllerPage) {
      _pageController.jumpToPage(controllerPage);
      needSetState = true;
    }

    if (needSetState) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    _countdownTimer?.cancel();
    _syncTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;

      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
        
        if (_remainingSeconds == 30) {
          _showTimeWarning('¡Quedan 30 segundos!');
        }
        if (_remainingSeconds == 10) {
          _showTimeWarning('¡Quedan 10 segundos!');
        }
      } else {
        timer.cancel();
        
        if (!_timeExpired) {
          if (mounted) {
            setState(() {
              _timeExpired = true;
            });
          }
          
          await _handleTimeExpired();
        }
      }
    });
  }

  Future<void> _handleTimeExpired() async {
    if (_isSubmitting || _navigatedToResults) return;
    
    if (mounted) {
      setState(() => _isSubmitting = true);
    }
    
    try {
      await _forceFinishOnTimeExpired();
    } catch (e) {
      AppLogger.e('Error al manejar tiempo expirado', e);
      if (mounted && !_navigatedToResults) {
        _navigateToResults();
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _forceFinishOnTimeExpired() async {
    try {
      await controller.flushAllPending();
      
      try {
        await controller.finish();
      } catch (e) {
        if (!e.toString().contains('attemptalreadyclosed') && 
            !e.toString().contains('ya ha sido finalizado')) {
          rethrow;
        }
      }

      final answersList = controller.answers.entries
          .map((e) => {'slot': e.key, 'answer': e.value})
          .toList();

      final score = controller.calculateScoreIfAvailable() ?? 0.0;

      final resp = await widget.api.finishChallenge(
        challengeId: widget.challengeId,
        score: score,
        answers: answersList,
      );

      try {
        await widget.api.forceFinishChallenge(widget.challengeId);
      } catch (e) {
        AppLogger.e('No se pudo forzar finalización del reto', e);
      }

      final pendingUsers = resp['pending_users'] as List?;
      
      if (pendingUsers == null || pendingUsers.isEmpty) {
        _navigateToResults();
      } else {
        await _showWaitingScreen(resp);
      }
    } catch (e, st) {
      debugPrint('Error en finalización forzosa: $e\n$st');
      _navigateToResults();
    }
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      await _syncWithServer();
    });
  }

  Future<void> _syncWithServer() async {
    try {
      final response = await widget.api.getChallengeTime(widget.challengeId);
      if (response['status'] == 'ok') {
        final serverTime = response['server_time'];
        final challenge = response['challenge'];
        final serverRemaining = challenge['remaining_seconds'] ?? 0;

        final localTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final timeDrift = localTime - serverTime;

        if ((_remainingSeconds - serverRemaining).abs() > 5) {
          if (mounted) {
            setState(() {
              _remainingSeconds = serverRemaining;
            });
          }
          _countdownTimer?.cancel();
          _startCountdown();
        }
      }
    } catch (e) {
      AppLogger.e('Error en sincronización', e);
    }
  }

  void _showTimeWarning(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
    final exp = RegExp(r'''<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*>''', caseSensitive: false);
    return exp.allMatches(htmlText).map((m) => m.group(1)!).toList();
  }

  String _removeImageTags(String htmlText) {
    final exp = RegExp(r'''<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*>''', caseSensitive: false);
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

  Future<void> _navigateTo(int index) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final curSlot = controller.currentQuestion?.slot;
      if (curSlot != null) await controller.flushPendingForSlot(curSlot);

      await controller.navigateToPage(index);
      if (_pageController.hasClients) {
        await _pageController.animateToPage(
          controller.currentPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al navegar: $e'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _finishFlow({bool forceFinish = false}) async {
    if (_isSubmitting || _navigatedToResults) return;
    
    setState(() => _isSubmitting = true);

    try {
      await controller.flushAllPending();
      
      try {
        await controller.finish();
      } catch (e) {
        if (!e.toString().contains('attemptalreadyclosed') && 
            !e.toString().contains('ya ha sido finalizado')) {
          AppLogger.e('Error al finalizar intento Moodle', e);
        }
      }

      final answersList = controller.answers.entries
          .map((e) => {'slot': e.key, 'answer': e.value})
          .toList();

      final score = controller.calculateScoreIfAvailable() ?? 0.0;

      final resp = await widget.api.finishChallenge(
        challengeId: widget.challengeId,
        score: score,
        answers: answersList,
      );

      final pendingUsers = resp['pending_users'] as List?;
      
      if (pendingUsers == null || pendingUsers.isEmpty || forceFinish) {
        _navigateToResults();
      } else {
        await _showWaitingScreen(resp);
      }
    } catch (e, st) {
      debugPrint('Finish error: $e\n$st');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        
        await Future.delayed(const Duration(seconds: 2));
        _navigateToResults();
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _navigateToResults() {
    if (_navigatedToResults) return;
    _navigatedToResults = true;
    
    _countdownTimer?.cancel();
    _syncTimer?.cancel();
    
    if (!mounted) return;
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ChallengeResultsScreen(
          api: widget.api,
          challengeId: widget.challengeId,
        ),
      ),
    );
  }

  Future<void> _checkAndNavigateToResults() async {
    try {
      final response = await widget.api.getChallengeResults(widget.challengeId);
      if (response['status'] == 'ok') {
        _navigateToResults();
      }
    } catch (e) {
      AppLogger.e('Error verificando resultados', e);
    }
  }

  void _showTimeWarningInDialog(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.warning,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showWaitingScreen(Map<String, dynamic> initialResp) async {
    List<Map<String, dynamic>> pendingUsers = List<Map<String, dynamic>>.from(
      initialResp['pending_users'] as List? ?? [],
    );

    int remainingSeconds = _remainingSeconds;
    
    bool? shouldNavigateToResults = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WaitingDialog(
        challengeId: widget.challengeId,
        api: widget.api,
        initialPendingUsers: pendingUsers,
        initialRemainingSeconds: remainingSeconds,
      ),
    );

    if (shouldNavigateToResults ?? true) {
      _navigateToResults();
    }
  }

  Widget _buildTimer() {
    final total = _totalSeconds;
    final percent = (total > 0) ? (_remainingSeconds / total) : 0.0;

    if (_timeExpired || _remainingSeconds <= 0) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.errorDark),
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
                    value: 0,
                    strokeWidth: 4,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.errorDark),
                  ),
                  const Text(
                    '00',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.errorDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  '00:00',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.errorDark,
                  ),
                ),
                Text(
                  'Tiempo agotado',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.errorDark,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Color timerColor;
    if (_remainingSeconds <= 60) {
      timerColor = AppColors.errorDark;
    } else if (_remainingSeconds <= 300) {
      timerColor = AppColors.warning;
    } else {
      timerColor = AppColors.successDark;
    }

    final minutes = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remainingSeconds % 60).toString().padLeft(2, '0');
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
                  displayTime.split(':')[1],
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
                '${(_remainingSeconds ~/ 60)} min',
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
  }

  bool _isAnsweredForSlot(int slot) {
    final value = controller.answers[slot];
    return value != null && value != '-1' && value.toString().trim().isNotEmpty;
  }

  Future<void> _openAttemptMap() async {
    if (controller.questions.isEmpty) return;

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
                        'Mapa del reto',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: AppColors.textTertiary),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Divider(height: 0),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: controller.totalPages,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      childAspectRatio: 1.0,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemBuilder: (_, index) {
                      final slot = controller.questions[index].slot;
                      final value = controller.answers[slot];
                      final answered = _isAnsweredForSlot(slot);
                      final isCurrent = index == controller.currentPage;

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
                                ? Border.all(color: AppColors.surface, width: 2)
                                : null,
                            boxShadow: isCurrent
                                ? [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.3),
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
                          style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
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
                          style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
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
                          style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
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

    final total = controller.questions.length;
    int answeredCount = 0;
    final List<int> unansweredIndices = [];
    
    for (int i = 0; i < controller.questions.length; i++) {
      final q = controller.questions[i];
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
                            ? '¡Reto completo!'
                            : '¿Finalizar reto?',
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

  Widget _buildQuestionPage(int index) {
    final q = controller.questions[index];
    final questionImages = _extractImageUrls(q.questionText);
    final questionHtmlNoImgs = _removeImageTags(q.questionText);
    final slot = q.slot;
    _localSelection.putIfAbsent(slot, () => controller.answers[slot]);
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                const SizedBox(height: 16),
                
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
                            onTap: () => _openImageGallery(context, questionImages, i),
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
                
                _renderHtmlWithMath(questionHtmlNoImgs),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
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
                          controller.markPending(slot, opt.value);
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

  @override
  Widget build(BuildContext context) {
    if (_loadingQuiz) {
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

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 1,
          title: Text(
            controller.quizName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadowSm,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.error,
                ),
                const SizedBox(height: 16),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (controller.questions.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 1,
          title: Text(
            controller.quizName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadowSm,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.assignment_outlined,
                  size: 48,
                  color: AppColors.textDisabled,
                ),
                SizedBox(height: 16),
                Text(
                  'No hay preguntas disponibles en este reto',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final progress = (controller.currentPage + 1) / controller.totalPages;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients &&
          _pageController.page?.round() != controller.currentPage) {
        _pageController.jumpToPage(controller.currentPage);
      }
    });

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
              controller.quizName,
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
              '${controller.currentPage + 1} de ${controller.totalPages} preguntas',
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
          preferredSize: const Size.fromHeight(48),
          child: Container(
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
                    const Text(
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
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: controller.totalPages,
              itemBuilder: (_, index) => _buildQuestionPage(index),
            ),
          ),
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
                      onPressed: controller.currentPage > 0 && !_isSubmitting
                          ? () => _navigateTo(controller.currentPage - 1)
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
                              final isLast = controller.currentPage == controller.totalPages - 1;
                              if (isLast) {
                                await _confirmFinish();
                              } else {
                                await _navigateTo(controller.currentPage + 1);
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
                            controller.currentPage == controller.totalPages - 1
                                ? 'Finalizar'
                                : 'Siguiente',
                            style: TextStyle(fontSize: 13),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            controller.currentPage == controller.totalPages - 1
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
  }
}

// Widget separado para el diálogo de espera
class WaitingDialog extends StatefulWidget {
  final int challengeId;
  final ApiService api;
  final List<Map<String, dynamic>> initialPendingUsers;
  final int initialRemainingSeconds;

  const WaitingDialog({
    Key? key,
    required this.challengeId,
    required this.api,
    required this.initialPendingUsers,
    required this.initialRemainingSeconds,
  }) : super(key: key);

  @override
  _WaitingDialogState createState() => _WaitingDialogState();
}

class _WaitingDialogState extends State<WaitingDialog> {
  late List<Map<String, dynamic>> _pendingUsers;
  late int _remainingSeconds;
  Timer? _pollingTimer;
  Timer? _countdownTimer;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _pendingUsers = widget.initialPendingUsers;
    _remainingSeconds = widget.initialRemainingSeconds;
    
    _startPolling();
    
    if (_remainingSeconds > 0) {
      _startCountdown();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) return;
      await _checkWaitingStatus();
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        _forceCloseDialog();
      }
    });
  }

  Future<void> _checkWaitingStatus() async {
    if (_isChecking) return;
    
    _isChecking = true;
    try {
      final response = await widget.api.getChallengeWaitingStatus(widget.challengeId);
      
      if (response['status'] == 'ok') {
        final pending = List<Map<String, dynamic>>.from(
          response['pending_users'] as List? ?? [],
        );
        
        final serverRemaining = response['remaining_seconds'] ?? 0;
        
        setState(() {
          _pendingUsers = pending;
          if (serverRemaining > 0 && _remainingSeconds != serverRemaining) {
            _remainingSeconds = serverRemaining;
            _countdownTimer?.cancel();
            _startCountdown();
          }
        });
        
        if (pending.isEmpty) {
          _closeDialog(true);
        }
      }
    } catch (e) {
      AppLogger.e('Error en polling de espera', e);
    } finally {
      _isChecking = false;
    }
  }

  void _forceCloseDialog() {
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _closeDialog(bool navigateToResults) {
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    if (mounted) {
      Navigator.of(context).pop(navigateToResults);
    }
  }

  String _fmt(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Icon(
                      Icons.hourglass_top_rounded,
                      color: AppColors.primary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Esperando participantes",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tiempo restante: ${_fmt(_remainingSeconds)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_pendingUsers.isNotEmpty) ...[
                    const Text(
                      'Faltan por terminar:',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.maxFinite,
                      height: 200,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _pendingUsers.length,
                        itemBuilder: (context, index) {
                          final user = _pendingUsers[index];
                          final name = user['nombre'] ?? 'Usuario';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceClean,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.explanationBg,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 20,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.borderDark,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ] else
                    const Text(
                      'Todos han finalizado',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.successDark,
                      ),
                    ),
                ],
              ),
            ),
            Divider(height: 0),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _closeDialog(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textTertiary,
                        side: BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _closeDialog(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textOnPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: const Text('Ver resultados'),
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