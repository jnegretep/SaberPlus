import 'package:flutter/material.dart';
import '../controllers/quiz_controller.dart';
import '../services/api_service.dart';
import 'question_screen.dart';
import 'review_screen.dart';
import '../models/attempt_summary.dart';
import 'simulacro_stats_screen.dart';
import '../core/theme/app_colors.dart';

class QuizIntroScreen extends StatefulWidget {
  final int quizId;
  final String quizName;
  final int courseId;
  final int timeLimit;
  final int questions;
  final ApiService api;

  const QuizIntroScreen({
    Key? key,
    required this.quizId,
    required this.quizName,
    required this.courseId,
    required this.timeLimit,
    required this.questions,
    required this.api,
  }) : super(key: key);

  @override
  State<QuizIntroScreen> createState() => _QuizIntroScreenState();
}

class _QuizIntroScreenState extends State<QuizIntroScreen> {
  bool _loading = true;
  List<dynamic> _attempts = [];
  Map<String, dynamic> _accessInfo = {};
  bool _startingAttempt = false;
  final Map<int, bool> _loadingReview = {};
  Map<String, dynamic>? _latestStats;

  // IDs de cursos simulacro
  final List<int> simuIds = const [2, 3, 18, 24, 25, 26, 27, 28, 29, 30, 31];
  bool get isSimulacro => simuIds.contains(widget.courseId);

  // ==========================================
  // GETTERS PARA EL ESTADO DE INTENTOS
  // ==========================================
  bool get _hasActiveAttempt {
    if (_attempts.isEmpty) return false;
    final latest = _attempts.last as AttemptSummary;
    return _isAttemptActive(latest);
  }

  bool get _hasFinishedAttempt {
    if (_attempts.isEmpty) return false;
    final latest = _attempts.last as AttemptSummary;
    return _isAttemptFinished(latest);
  }

  bool get _showStartButton {
    if (isSimulacro) {
      // Para simulacros: solo mostrar si no hay intento activo NI terminado
      return !_hasActiveAttempt && !_hasFinishedAttempt;
    } else {
      // Para cuestionarios normales: mostrar si no hay intento activo
      return !_hasActiveAttempt;
    }
  }

  bool get alreadyAttempted => _attempts.isNotEmpty;

  // En initState
@override
void initState() {
  super.initState();
  _loadAttempts();
  if (isSimulacro) _loadStats();
  
  // Refrescar intentos cada 10 segundos si hay un intento activo
  _startAutoRefresh();
}

// Nueva función
void _startAutoRefresh() {
  Future.delayed(const Duration(seconds: 10), () {
    if (mounted) {
      _loadAttempts().then((_) {
        // Si hay intentos activos, seguir refrescando
        if (_hasActiveAttempt) {
          _startAutoRefresh();
        }
      });
    }
  });
}

// En dispose
@override
void dispose() {
  // Cancelar cualquier refresh pendiente
  // (aunque no hay timer, las Futures siguen ejecutándose)
  super.dispose();
}

  Future<void> _loadStats() async {
    try {
      final res = await widget.api.fetchSimulacroStats(widget.quizId);
      setState(() {
        _latestStats = res["user"];
      });
    } catch (e) {
      debugPrint("Error cargando stats: $e");
    }
  }

Future<void> _loadAttempts() async {
  setState(() => _loading = true);
  try {
    final data = await widget.api.fetchAttempts(widget.quizId);

    // Verificar si hay intentos que necesiten ser finalizados por tiempo
    final attempts = data['attempts'] ?? [];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (final attempt in attempts) {
      final state = attempt.state?.toString().toLowerCase() ?? '';
      final timestart = attempt.timestart ?? 0;

      // Usar el timelimit real del cuestionario en vez de hardcodear 1500
      final timelimit = widget.timeLimit; // segundos reales

      if (state == 'inprogress' && timestart > 0 && timelimit > 0) {
        final elapsed = now - timestart;
        if (elapsed > timelimit) {
          debugPrint(
            "[LOAD_ATTEMPTS] Intento ${attempt.id} ha expirado "
            "(transcurrido: $elapsed, límite: $timelimit)",
          );
          // Este intento debería estar marcado como overdue (el backend lo hará)
        }
      }
    }

    setState(() {
      _attempts = attempts;
      _accessInfo = data['accessinfo'] ?? {};
      _loading = false;
    });
  } catch (e) {
    setState(() => _loading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar intentos: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}


  String _formatDateTimeEpoch(int? epochSeconds) {
    if (epochSeconds == null || epochSeconds <= 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000).toLocal();
    
    final day = dt.day.toString().padLeft(2, '0');
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
    ];
    final month = months[dt.month - 1];
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    
    return "$day $month · $hour:$min";
  }

  // ==========================================
  // FUNCIONES AUXILIARES PARA DETECTAR ESTADOS
  // ==========================================

  // Determina si un intento está activo (realmente inprogress)
  bool _isAttemptActive(AttemptSummary a) {
    final state = (a.state ?? "").toString().toLowerCase();
    final timefinish = a.timefinish ?? 0;
    
    // Solo está activo si state es 'inprogress' Y timefinish es 0
    return state == 'inprogress' && timefinish == 0;
  }

  // Determina si un intento está terminado (por cualquier motivo)
  bool _isAttemptFinished(AttemptSummary a) {
    final state = (a.state ?? "").toString().toLowerCase();
    final timefinish = a.timefinish ?? 0;
    
    // Terminado si: state es 'finished', 'overdue', o timefinish > 0
    return state == 'finished' || state == 'overdue' || timefinish > 0;
  }

  // Determina si un intento está "overdue" (vencido por tiempo)
  bool _isAttemptOverdue(AttemptSummary a) {
    final state = (a.state ?? "").toString().toLowerCase();
    return state == 'overdue';
  }

  Future<void> _confirmStart() async {
    final minutes = (widget.timeLimit ~/ 60);
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    
    final durationText = hours > 0
        ? "${hours}h ${mins}m"
        : "${mins} minutos";

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
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
                        Icons.assignment_rounded,
                        color: AppColors.primary,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Confirmar inicio",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Este simulacro solo permite un intento.\n\n"
                      "Preguntas: ${widget.questions}\n"
                      "Duración: $durationText\n\n"
                      "¿Deseas comenzar ahora?",
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textTertiary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
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
                        onPressed: () => Navigator.pop(context, false),
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
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textOnPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: const Text('Comenzar'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok == true) {
      _startNewAttempt();
    }
  }

Future<void> _startNewAttempt() async {
  if (_startingAttempt) return;
  
  setState(() => _startingAttempt = true);
  try {
    await widget.api.startAttempt(widget.quizId);
    
    final controller = QuizController(
      api: widget.api,
      quizId: widget.quizId,
      quizName: widget.quizName,
      courseId: widget.courseId,
    );
    
    await controller.start();
    
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionScreen(
          controller: controller,
          courseId: widget.courseId,
        ),
      ),
    );
  } catch (e) {
    // Si es error 500 por intento ya existente, verificar si hay intento para revisar
    if (e.toString().contains('500') || e.toString().contains('attemptalreadyclosed')) {
      try {
        // Intentar obtener el último intento para revisar
        if (_attempts.isNotEmpty) {
          final lastAttempt = _attempts.last;
          _reviewAttempt(lastAttempt.id);
        } else {
          // Si no hay intentos en la lista, intentar cargar estadísticas
          await _loadStats();
          if (_latestStats != null) {
            // Mostrar resultados existentes
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Este simulacro ya fue completado. Mostrando resultados...'),
                backgroundColor: AppColors.warning,
                action: SnackBarAction(
                  label: 'Ver',
                  onPressed: () {
                    // Navegar a pantalla de estadísticas
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SimulacroStatsScreen(
                          simulacroId: widget.quizId,
                          courseId: widget.courseId,
                          api: widget.api,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: $e'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }
      } catch (e2) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al procesar intento: $e2'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al iniciar intento: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } finally {
    if (mounted) setState(() => _startingAttempt = false);
  }
}

Future<void> _reviewAttempt(int attemptId) async {
  if (_loadingReview[attemptId] == true) return;
  
  setState(() => _loadingReview[attemptId] = true);
  try {
    final data = await widget.api.fetchAttemptData(attemptId);
    
    if (!mounted) return;
    
    // Usar push y esperar a que regrese
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          reviewData: data,
          courseId: widget.courseId,
          quizId: widget.quizId,
        ),
      ),
    );
    
    // Si regresó con true o simplemente regresó, actualizar
    if (result == true || mounted) {
      await _loadAttempts();
      if (isSimulacro) {
        await _loadStats();
      }
      setState(() {});
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar revisión: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } finally {
    if (mounted) setState(() => _loadingReview[attemptId] = false);
  }
}

  Widget _buildStatsBlock() {
    if (_latestStats == null) return const SizedBox.shrink();
    
    double _toDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0.0;
    }
    
    final Map<String, IconData> areaIcons = {
      "Lectura": Icons.menu_book_rounded,
      "Matemáticas": Icons.calculate_rounded,
      "Sociales": Icons.public_rounded,
      "Naturales": Icons.eco_rounded,
      "Inglés": Icons.language_rounded,
    };
    
    final Map<String, String> areaKeys = {
      "Lectura": "lectura_puntaje",
      "Matemáticas": "matematicas_puntaje",
      "Sociales": "sociales_puntaje",
      "Naturales": "naturales_puntaje",
      "Inglés": "ingles_puntaje",
    };
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header del bloque
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.bar_chart_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Resultado del simulacro',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      _latestStats?["fecha_realizacion"] ?? "—",
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Puntaje global
          Center(
            child: Column(
              children: [
                Text(
                  _toDouble(_latestStats?["puntaje_global"]).toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Puntaje global',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          Divider(color: AppColors.border),
          const SizedBox(height: 16),
          
          // Puntajes por área
          const Text(
            'Puntajes por área',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          
          ...areaIcons.entries.map((entry) {
            final area = entry.key;
            final icon = entry.value;
            final key = areaKeys[area];
            final score = _toDouble(_latestStats?[key]);
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceClean,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: AppColors.textTertiary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      area,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      score.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          
          const SizedBox(height: 12),
          
          // Tiempo empleado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceClean,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Tiempo empleado:',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textTertiary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_latestStats?["tiempo_empleado"] ?? "—"} min',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Botón ver estadísticas completas
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SimulacroStatsScreen(
                      simulacroId: widget.quizId,
                      courseId: widget.courseId,
                      api: widget.api,
                    ),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.insights_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Ver estadísticas completas'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attemptCard(int index, AttemptSummary a) {
    final id = a.id;
    final isActive = _isAttemptActive(a);
    final isFinished = _isAttemptFinished(a);
    final isOverdue = _isAttemptOverdue(a);
    final start = _formatDateTimeEpoch(a.timestart);
    final finish = a.timefinish != null && a.timefinish! > 0
        ? _formatDateTimeEpoch(a.timefinish)
        : "En curso";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icono de estado
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isOverdue
                        ? AppColors.warningBg // Amarillo para vencido
                        : isFinished
                            ? AppColors.successLight // Verde para completado
                            : AppColors.infoBg, // Azul para en curso
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isOverdue
                        ? Icons.access_time_rounded
                        : isFinished
                            ? Icons.check_circle_rounded
                            : Icons.pending_rounded,
                    color: isOverdue
                        ? AppColors.warning
                        : isFinished
                            ? AppColors.successDark
                            : AppColors.primary,
                    size: 24,
                  ),
                ),
                
                const SizedBox(width: 16),
                
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isOverdue 
                            ? "Vencido por tiempo" 
                            : isFinished 
                                ? "Simulacro completado" 
                                : "Simulacro en curso",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // Timeline
                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 200) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildTimeChip(
                                  icon: Icons.play_arrow_rounded,
                                  text: start,
                                ),
                                const SizedBox(height: 6),
                                _buildTimeChip(
                                  icon: Icons.stop_rounded,
                                  text: finish,
                                ),
                              ],
                            );
                          }
                          
                          return Row(
                            children: [
                              Expanded(
                                child: _buildTimeChip(
                                  icon: Icons.play_arrow_rounded,
                                  text: start,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 14,
                                  color: AppColors.textDisabled,
                                ),
                              ),
                              Expanded(
                                child: _buildTimeChip(
                                  icon: Icons.stop_rounded,
                                  text: finish,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 12),
                
                // Botón de revisar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    onPressed: _loadingReview[id] == true
                        ? null
                        : () => _reviewAttempt(id),
                    icon: _loadingReview[id] == true
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : Icon(
                            Icons.visibility_rounded,
                            color: AppColors.primary,
                            size: 20,
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

  // Widget helper para los chips de tiempo
  Widget _buildTimeChip({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // MÉTODOS PARA LOS BOTONES
  // ==========================================

  Widget _buildBottomButton() {
    if (_hasActiveAttempt) {
      // Mostrar botón para continuar intento activo
      return _buildContinueButton();
    } else if (_showStartButton) {
      // Mostrar botón para comenzar nuevo intento
      return _buildStartButton();
    } else if (_hasFinishedAttempt && isSimulacro) {
      // Para simulacros terminados, mostrar botón de ver resultados
      return _buildResultsButton();
    }
    return const SizedBox.shrink();
  }

  Widget _buildContinueButton() {
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 56,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _startingAttempt ? null : _continueActiveAttempt,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.successDark, // Verde para continuar
              foregroundColor: AppColors.textOnPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _startingAttempt
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textOnPrimary,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_arrow_rounded, size: 20),
                      SizedBox(width: 8),
                      Text(
                        "Continuar intento",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsButton() {
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 56,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _startingAttempt ? null : () {
              final latest = _attempts.last as AttemptSummary;
              _reviewAttempt(latest.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bar_chart_rounded, size: 20),
                SizedBox(width: 8),
                Text(
                  "Ver resultados",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStartButton() {
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 56,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _startingAttempt
                ? null
                : () {
                    if (isSimulacro) {
                      _confirmStart();
                    } else {
                      _startNewAttempt();
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _startingAttempt
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textOnPrimary,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_arrow_rounded, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        isSimulacro
                            ? "Comenzar simulacro"
                            : "Comenzar intento",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // MÉTODO PARA CONTINUAR INTENTO ACTIVO
  // ==========================================

Future<void> _continueActiveAttempt() async {
  if (_attempts.isEmpty) return;

  final latestAttempt = _attempts.last as AttemptSummary;
  if (!_isAttemptActive(latestAttempt)) return;

  setState(() => _startingAttempt = true);
  try {
    final controller = QuizController(
      api: widget.api,
      quizId: widget.quizId,
      quizName: widget.quizName,
      courseId: widget.courseId,
    );

    await controller.loadExistingAttempt(latestAttempt.id);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionScreen(
          controller: controller,
          courseId: widget.courseId,
        ),
      ),
    );
  } catch (e) {
    // Intento ya finalizado o vencido: mostrar alerta y mandar a revisión
    if (e.toString().toLowerCase().contains('finalizado') ||
        e.toString().toLowerCase().contains('overdue') ||
        e.toString().toLowerCase().contains('finished') ||
        e.toString().toLowerCase().contains('already closed')) {
      // Cargar datos de revisión si el controlador no los tiene aún
      Map<String, dynamic>? reviewData;
      try {
        // Intento obtener del controlador si fue persistido
        // (en loadExistingAttempt ya lo guardamos antes de lanzar la excepción)
        // Si no está, pido al backend
        if (mounted) {
          final controllerProbe = QuizController(
            api: widget.api,
            quizId: widget.quizId,
            quizName: widget.quizName,
            courseId: widget.courseId,
          );
          // Si por algún motivo no está en controller.reviewData, lo obtenemos directamente
          reviewData = controllerProbe.reviewData ?? await widget.api.fetchAttemptData(latestAttempt.id);
        }
      } catch (_) {}

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Tiempo agotado"),
          content: const Text(
            "Este intento ya ha sido finalizado. Ahora puedes revisar tus respuestas.",
          ),
          actions: [
            TextButton(
              child: const Text("Ver revisión"),
              onPressed: () {
                Navigator.pop(context); // cerrar el diálogo
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReviewScreen(
                      reviewData: reviewData ?? {},
                      courseId: widget.courseId,
                      quizId: widget.quizId,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar intento: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  } finally {
    if (mounted) setState(() => _startingAttempt = false);
  }
}


  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowSm,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textSecondary,
                      size: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.quizName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.questions} preguntas • ${widget.timeLimit ~/ 60} min',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isSimulacro ? 'Simulacro' : 'Cuestionario',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Contenido
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadAttempts,
                color: AppColors.primary,
                backgroundColor: AppColors.surface,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Bloque de estadísticas (si es simulacro y ya intentado)
                      if (isSimulacro && alreadyAttempted) _buildStatsBlock(),

                      const SizedBox(height: 4),

                      // Lista de intentos o estado vacío
                      if (_attempts.isEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Column(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceVariant,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.assignment_outlined,
                                  color: AppColors.textDisabled,
                                  size: 48,
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Aún no has realizado intentos',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.borderDark,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Comienza tu primer intento para ver resultados',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textTertiary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 12),
                              child: Text(
                                'Intentos realizados (${_attempts.length})',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            ..._attempts.asMap().entries.map(
                                  (entry) => _attemptCard(entry.key, entry.value as AttemptSummary),
                                ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // Botón inferior (decide automáticamente qué mostrar)
            _buildBottomButton(),
          ],
        ),
      ),
    );
  }
}