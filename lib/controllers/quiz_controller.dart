import 'dart:async';
import 'package:flutter/material.dart';
import '../models/quiz_question.dart';
import '../models/attempt.dart';
import '../services/api_service.dart';
import '../parsers/quiz_question_parser.dart';

class QuizController extends ChangeNotifier {
  final ApiService api;
  final int quizId;
  final String quizName;
  final int? courseId;

  Attempt? attempt;
  final List<QuizQuestion> questions = []; // Final pero mutable
  final Map<int, String> answers = {};
  int currentPage = 0;
  bool isLoading = false;
  bool isFinished = false;
  double? finalGrade;
  Map<String, dynamic>? reviewData;

  // Cronómetro
  int? remainingSeconds;
  bool hasTimeLimit = false;
  Timer? _timer;

  // --- Envíos pendientes y control de respuestas ---
  final Map<int, String> _pending = {};
  final Map<int, Timer> _debounceTimers = {};
  final Set<int> _inFlightSlots = {};
  Duration debounceDuration = const Duration(milliseconds: 700);

  // === Manejo de secciones / áreas ===
  final List<String> _defaultSections = const [
    'Lectura crítica',
    'Matemáticas',
    'Ciencias sociales',
    'Ciencias naturales',
    'Inglés',
  ];

  /// sección → índices de preguntas
  Map<String, List<int>> sectionMap = {};

  QuizController({
    required this.api,
    required this.quizId,
    required this.quizName,
    this.courseId,
  });

  int get totalPages => questions.length;

  bool get hasMultipleSections => sectionMap.length > 1;

  List<String> get areaNames => sectionMap.keys.toList();

  String? getAreaForQuestion(int index) {
    for (final entry in sectionMap.entries) {
      if (entry.value.contains(index)) return entry.key;
    }
    return null;
  }

  int? getFirstQuestionIndexOfArea(String area) {
    final list = sectionMap[area];
    if (list == null || list.isEmpty) return null;
    return list.first;
  }

  // === Construcción de secciones ===
  void _buildSections() {
    if (questions.isEmpty) return;

    final uniquePages = questions.map((q) => q.page).toSet().toList()..sort();
    sectionMap.clear();

    if (uniquePages.length == 1) {
      sectionMap[_defaultSections.first] =
          List.generate(questions.length, (i) => i);
      debugPrint('>>> Solo un bloque, sin secciones múltiples');
      return;
    }

    for (int i = 0; i < uniquePages.length; i++) {
      final page = uniquePages[i];
      final name = i < _defaultSections.length
          ? _defaultSections[i]
          : 'Sección ${i + 1}';
      final questionIndexes = questions
          .asMap()
          .entries
          .where((e) => e.value.page == page)
          .map((e) => e.key)
          .toList();
      sectionMap[name] = questionIndexes;
    }

    debugPrint('>>> Secciones detectadas: $sectionMap');
  }

  // === NUEVO: Método para cargar intento existente ===
  Future<void> loadExistingAttempt(int attemptId) async {
    // Establecer el estado de carga
    isLoading = true;
    notifyListeners();
    
    try {
      // 1. Cargar datos del intento existente
      final data = await api.fetchAttemptData(attemptId);
      
      
      // 2. Crear el objeto Attempt con los datos recibidos
attempt = Attempt(
  id: attemptId,
  uniqueId: attemptId,
  timelimit: data['timelimit'] ?? 1500, // Valor por defecto para simulacros
  timestart: data['timestart'] ?? 0,
  timefinish: data['timefinish'] ?? 0,
  timeleft: data['timeleft'],
);

debugPrint("[QuizController] Intento cargado - timelimit: ${attempt?.timelimit}");
      
      debugPrint("[QuizController] Intentando cargar attemptId: $attemptId");
      
      // 3. Verificar si el intento ya está cerrado
final timefinish = data['timefinish'] ?? 0;
final reviewMode = data['reviewMode'] ?? false;

if (timefinish > 0 || reviewMode) {
  debugPrint("[QuizController] Intento ya cerrado (timefinish: $timefinish, reviewMode: $reviewMode)");
  // Persistir datos de revisión para que la UI pueda navegar sin volver a pedirlos
  reviewData = data;
  isFinished = true;
  notifyListeners();
  throw Exception('Este intento ya ha sido finalizado');
}

      
      // 4. Cargar preguntas - CORRECCIÓN: No reasignar, limpiar y agregar
      final loadedQuestions = await api.fetchAllQuestions(attemptId);
      questions.clear(); // Limpiar lista existente
      questions.addAll(loadedQuestions); // Agregar nuevas preguntas
      debugPrint("[QuizController] Preguntas cargadas: ${questions.length}");
      
      // 5. Cargar respuestas guardadas - CORRECCIÓN: Usar el mismo método que en start()
      final savedResponses = data['savedResponses'] ?? {};
      answers.clear(); // Limpiar respuestas existentes
      if (savedResponses is Map) {
        savedResponses.forEach((slotStr, val) {
          final slot = int.tryParse(slotStr.toString());
          if (slot != null) {
            answers[slot] = val.toString();
          }
        });
      }
      debugPrint("[QuizController] Respuestas guardadas cargadas: ${answers.length}");
      
      // 6. Configurar secciones
      _buildSections();
      
      // 7. Configurar temporizador si es necesario
      _setupTimerFromData(data);
      
      // 8. Configurar estado inicial
      currentPage = 0;
      isLoading = false;
      notifyListeners();
      
      debugPrint("[QuizController] Intento $attemptId cargado exitosamente");
    } catch (e) {
      isLoading = false;
      notifyListeners();
      debugPrint("[QuizController] Error cargando intento $attemptId: $e");
      rethrow;
    }
  }

void _setupTimerFromData(Map<String, dynamic> data) {
  int timelimit = (data['timelimit'] ?? 0) as int;

  if (timelimit <= 0 && attempt?.timelimit != null && attempt!.timelimit > 0) {
    timelimit = attempt!.timelimit;
    debugPrint("[TIMER] Usando timelimit del attempt: $timelimit");
  }

  if (timelimit <= 0) {
    if (courseId != null &&
        [2, 3, 18, 24, 25, 26, 27, 28, 29, 30, 31].contains(courseId)) {
      timelimit = 1500; // último recurso
      debugPrint("[TIMER] Usando valor por defecto para simulacro: $timelimit segundos");
    }
  }

  final timestart = (data['timestart'] ?? attempt?.timestart ?? 0) as int;
  final backendTimeleft = data['timeleft'] ?? attempt?.timeleft;

  debugPrint("[TIMER] timelimit final: $timelimit, timestart: $timestart, backendTimeleft: $backendTimeleft");

  _timer?.cancel();
  _timer = null;

  if (timelimit > 0 && timestart > 0) {
    hasTimeLimit = true;

    if (backendTimeleft is int && backendTimeleft > 0) {
      remainingSeconds = backendTimeleft;
      debugPrint("[TIMER] Usando backendTimeleft: $remainingSeconds segundos");
    } else {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final elapsed = now - timestart;
      final remaining = timelimit - elapsed;

      debugPrint("[TIMER] now: $now, elapsed: $elapsed, remaining: $remaining");

      remainingSeconds = remaining.clamp(0, timelimit).toInt();
    }

    if (remainingSeconds! > 0) {
      debugPrint("[TIMER] Iniciando timer con $remainingSeconds segundos");
      _startTimer();
    } else {
      debugPrint("[TIMER] Tiempo agotado - finalizando intento automáticamente");
      remainingSeconds = 0;
      hasTimeLimit = false;
      _handleTimeExpired();
    }
  } else {
    hasTimeLimit = false;
    remainingSeconds = null;
    debugPrint("[TIMER] No hay límite de tiempo configurado");
  }
}



// Nuevo método para manejar tiempo expirado
void _handleTimeExpired() async {
  if (attempt == null || isFinished) return;
  
  debugPrint("[TIMER] Tiempo expirado - intentando finalizar intento");
  try {
    await flushAllPending();
    
    // Intentar finalizar el intento en Moodle
    final result = await api.finishAttempt(attempt!.id);
    
    if (result.containsKey('review')) {
      reviewData = result['review'];
      isFinished = true;
      debugPrint("[TIMER] Intento finalizado exitosamente por tiempo");
      notifyListeners();
    }
  } catch (e) {
    debugPrint("[TIMER] Error al finalizar intento por tiempo: $e");
  }
}

  // === Método auxiliar para encontrar primera pregunta sin responder ===
  int _findFirstUnansweredQuestion() {
    for (int i = 0; i < questions.length; i++) {
      final question = questions[i];
      // Buscar si hay respuesta guardada para esta pregunta
      if (!answers.containsKey(question.slot) || 
          answers[question.slot] == null || 
          answers[question.slot]!.isEmpty) {
        return i;
      }
    }
    return 0; // Si todas están respondidas, volver a la primera
  }

  // === Carga inicial del intento (método existente) ===
  Future<void> start() async {
    _timer?.cancel();
    _clearPending();
    isLoading = true;
    isFinished = false;
    finalGrade = null;
    reviewData = null;
    currentPage = 0;
    questions.clear();
    answers.clear();
    remainingSeconds = null;
    hasTimeLimit = false;
    notifyListeners();

    try {
      attempt = await api.startAttempt(quizId);
      debugPrint("[QuizController] timelimit del intento recién iniciado: ${attempt?.timelimit}");
      final attemptData = await api.fetchAttemptData(attempt!.id);

      final allQuestions = attemptData['questions'] as List<dynamic>? ?? [];
      for (var q in allQuestions) {
        try {
          final parsed = parseQuizQuestion(q as Map<String, dynamic>);
          questions.add(parsed);
        } catch (e, st) {
          debugPrint('>>> Error parseando pregunta: $e\n$st');
        }
      }

      if (questions.isNotEmpty) currentPage = 0;

      _buildSections(); // Detectar secciones

      final rawSaved = attemptData['savedResponses'];
      if (rawSaved is Map) {
        rawSaved.forEach((slotStr, val) {
          final slot = int.tryParse(slotStr.toString());
          if (slot != null) {
            answers[slot] = val.toString();
          }
        });
      }

      // Usar el nuevo método auxiliar para configurar timer
      _setupTimerFromData(attemptData);
    } catch (e) {
      debugPrint("[QuizController] Error en start(): $e");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (remainingSeconds == null) return;
      remainingSeconds = remainingSeconds! - 1;
      if (remainingSeconds! <= 0) {
        timer.cancel();
        remainingSeconds = 0;
        notifyListeners();
        hasTimeLimit = false;
      } else {
        notifyListeners();
      }
    });
  }

  // === Manejo de respuestas ===
  void markPending(int slot, String value) {
    answers[slot] = value;
    _pending[slot] = value;

    _debounceTimers[slot]?.cancel();
    _debounceTimers[slot] = Timer(debounceDuration, () {
      _debounceTimers.remove(slot);
      _flushPendingForSlot(slot);
    });

    notifyListeners();
  }

  Future<void> _flushPendingForSlot(int slot) async {
    if (!_pending.containsKey(slot)) return;
    if (_inFlightSlots.contains(slot)) return;

    final val = _pending[slot]!;
    _inFlightSlots.add(slot);
    try {
      await api.submitAnswer(attempt!.id, {slot.toString(): val});
      _pending.remove(slot);
    } catch (e) {
      debugPrint('[QuizController] Error enviando slot $slot: $e');
    } finally {
      _inFlightSlots.remove(slot);
    }
  }

  Future<void> flushPendingForSlot(int slot) async {
    _debounceTimers[slot]?.cancel();
    _debounceTimers.remove(slot);
    await _flushPendingForSlot(slot);
  }

  Future<void> flushAllPending() async {
    for (var t in _debounceTimers.values) t.cancel();
    _debounceTimers.clear();

    final slots = _pending.keys.toList();
    for (var s in slots) {
      await _flushPendingForSlot(s);
    }
  }

  void _clearPending() {
    for (var t in _debounceTimers.values) t.cancel();
    _debounceTimers.clear();
    _pending.clear();
    _inFlightSlots.clear();
  }

  Future<void> navigateToPage(int index) async {
    if (index < 0 || index >= totalPages) return;
    final currentSlot = currentQuestion?.slot;
    if (currentSlot != null) await flushPendingForSlot(currentSlot);

    currentPage = index;
    notifyListeners();
  }

  /// Calcula la nota final si ya fue finalizado el intento o si existe reviewData
  double? calculateScoreIfAvailable() {
    if (finalGrade != null) {
      return finalGrade;
    }

    if (reviewData != null &&
        reviewData!.containsKey('grade') &&
        reviewData!['grade'] is num) {
      return (reviewData!['grade'] as num).toDouble();
    }

    return null;
  }

  Future<void> finish() async {
    _timer?.cancel();
    if (attempt == null) return;

    try {
      await flushAllPending();
      final result = await api.finishAttempt(attempt!.id);

      if (result.containsKey('finish') && result.containsKey('review')) {
        reviewData = result['review'];
        if (reviewData != null && reviewData!.containsKey('grade')) {
          finalGrade = (reviewData!['grade'] as num).toDouble();
        }
        isFinished = true;
      } else {
        throw Exception("No se pudo finalizar el intento correctamente");
      }
    } catch (e) {
      debugPrint("[QuizController] Error en finish(): $e");
    }

    notifyListeners();
  }

  // === NUEVO ===
  Future<void> openAttemptMap() async {
    final currentSlot = currentQuestion?.slot;
    if (currentSlot != null) await flushPendingForSlot(currentSlot);
    await flushAllPending();

    // Aquí puedes abrir un modal o pantalla de mapa si ya lo tienes implementado
    debugPrint('>>> Intentando abrir mapa de intento...');
    notifyListeners();
  }

  QuizQuestion? get currentQuestion {
    if (currentPage >= 0 && currentPage < questions.length) {
      return questions[currentPage];
    }
    return null;
  }

  int? get timeLimitSeconds => remainingSeconds;

  @override
  void dispose() {
    _timer?.cancel();
    _clearPending();
    super.dispose();
  }
}