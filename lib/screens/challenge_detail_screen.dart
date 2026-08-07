// lib/screens/challenge_detail_screen.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/challenge.dart';
import '../models/participant.dart';
import 'challenge_question_screen.dart';
import 'challenge_results_screen.dart';
import '../core/theme/app_colors.dart';

class ChallengeDetailScreen extends StatefulWidget {
  final ApiService api;
  final int challengeId;

  const ChallengeDetailScreen({
    Key? key,
    required this.api,
    required this.challengeId,
  }) : super(key: key);

  @override
  State<ChallengeDetailScreen> createState() => _ChallengeDetailScreenState();
}

class _ChallengeDetailScreenState extends State<ChallengeDetailScreen> {
  // estado principal
  bool _loading = true;
  String? _error;
  Challenge? _challenge;
  List<Participant> _participants = [];
  Participant? _me;

  // timers
  Timer? _pollTimer;
  Timer? _secondTimer;

  // control de navegación
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _loadDetail(initial: true);
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _loadDetail());
    _secondTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_challenge != null && _challenge!.status == 'en_curso') {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _secondTimer?.cancel();
    super.dispose();
  }

  // ==========================
  //   PERMISOS Y ELIMINACIÓN
  // ==========================
  bool get _canDeleteChallenge {
    if (_challenge == null) return false;
    return _challenge!.creatorId == widget.api.auth.userId &&
           _challenge!.status == 'pendiente';
  }

  Future<void> _confirmAndDeleteChallenge() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
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
                        color: AppColors.errorFaint,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Icon(
                        Icons.delete_forever_rounded,
                        color: AppColors.errorDark,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "¿Eliminar reto?",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Esta acción es permanente.\n\n'
                      'El reto será eliminado y los participantes '
                      'quedarán libres para usar este cuestionario nuevamente.\n\n'
                      '¿Deseas continuar?',
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
                          backgroundColor: AppColors.errorDark,
                          foregroundColor: AppColors.textOnPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: const Text('Eliminar'),
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

    if (confirm != true) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );

      await widget.api.deleteChallenge(challengeId: _challenge!.id);

      if (!mounted) return;
      Navigator.pop(context); // cerrar loader
      Navigator.pop(context); // salir del detalle

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Reto eliminado correctamente'),
          backgroundColor: AppColors.successDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar el reto: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ==========================
  //   HELPERS
  // ==========================
  int _normalizeDurationMinutes(int raw) {
    if (raw <= 0) return 0;
    if (raw > 240) return (raw ~/ 60);
    return raw;
  }

  String _fmt(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  String _formatScheduled(String raw) {
    try {
      final dt = DateTime.parse(raw);
      final df = DateFormat('dd MMM • h:mm a', 'es');
      return df.format(dt);
    } catch (_) {
      return raw;
    }
  }

  String _formatMmSs(Duration d) {
    if (d.isNegative) return "00:00";
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'finalizado':
        return AppColors.successDark;
      case 'en_curso':
        return AppColors.warning;
      case 'pendiente':
        return AppColors.textTertiary;
      default:
        return AppColors.textDisabled;
    }
  }

  Color _getAreaColor(String area) {
    switch (area.toLowerCase()) {
      case 'lectura':
        return AppColors.primary; // Unificado
      case 'matematicas':
        return AppColors.primaryLight; // Unificado
      case 'sociales':
        return AppColors.successDark;
      case 'naturales':
        return AppColors.purple;
      case 'ingles':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  IconData _getAreaIcon(String area) {
    switch (area.toLowerCase()) {
      case 'lectura':
        return Icons.menu_book_rounded;
      case 'matematicas':
        return Icons.calculate_rounded;
      case 'sociales':
        return Icons.public_rounded;
      case 'naturales':
        return Icons.eco_rounded;
      case 'ingles':
        return Icons.language_rounded;
      default:
        return Icons.emoji_events_rounded;
    }
  }

  Color _getReadyStatusColor(String status) {
    switch (status) {
      case 'listo':
        return AppColors.warning;
      case 'jugando':
        return AppColors.primary;
      case 'terminado':
        return AppColors.successDark;
      default:
        return AppColors.textTertiary;
    }
  }

  // ==========================
  //   NAVEGACIÓN Y FLUJOS
  // ==========================
  void _goToQuestions({
    required int attemptId,
    required int quizId,
    required int challengeId,
    required int durationMinutes,
    String? startedAtStr,
    String? endTimeGlobalStr,
    DateTime? startedAt,
    DateTime? endTimeGlobal,
  }) {
    final start = startedAt ?? (startedAtStr != null ? DateTime.parse(startedAtStr).toUtc() : null);
    final end = endTimeGlobal ?? (endTimeGlobalStr != null ? DateTime.parse(endTimeGlobalStr).toUtc() : null);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChallengeQuestionScreen(
            api: widget.api,
            challengeId: challengeId,
            attemptId: attemptId,
            quizId: quizId,
            durationMinutes: durationMinutes,
            startedAt: start,
            endTimeGlobal: end,
          ),
        ),
      );
    });
  }

  Future<void> _showReadyDialog(Map<String, dynamic> resp) async {
    List<dynamic> participants = resp['participants'] as List<dynamic>? ?? [];
    String? startedAtStr = resp['started_at'] as String?;
    int durationMin = (resp['duration_minutes'] is int)
        ? resp['duration_minutes'] as int
        : (_challenge?.durationMinutes ?? 0);

    int remaining = 0;
    if (startedAtStr != null) {
      final start = DateTime.tryParse(startedAtStr)?.toUtc();
      if (start != null) {
        final end = start.add(Duration(minutes: durationMin));
        remaining = end.difference(DateTime.now().toUtc()).inSeconds;
        if (remaining < 0) remaining = 0;
      }
    }

    Timer? dialogTimer;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setStateDialog) {
          dialogTimer ??= Timer.periodic(const Duration(seconds: 3), (_) async {
            try {
              final detail = await widget.api.getChallengeDetail(widget.challengeId);
              final ch = detail['challenge'] as Map<String, dynamic>? ?? {};
              final status = ch['status'] ?? '';
              if (status == 'en_curso') {
                dialogTimer?.cancel();
                Navigator.pop(ctx2);
                final meResp = (ch['participants'] as List<dynamic>? ?? [])
                    .firstWhere((p) => p['user_id'] == widget.api.currentUserId, orElse: () => null);
                final attemptId = meResp?['moodle_attempt_id'];
                final startedAtStr2 = ch['started_at'] as String?;
                final endTimeGlobalStr2 = ch['end_time_global'] as String?;
                if (attemptId != null) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChallengeQuestionScreen(
                        api: widget.api,
                        challengeId: widget.challengeId,
                        attemptId: attemptId,
                        quizId: _challenge?.quizId ?? 0,
                        durationMinutes: _challenge?.durationMinutes ?? 0,
                        startedAt: startedAtStr2 != null ? DateTime.parse(startedAtStr2).toUtc() : null,
                        endTimeGlobal: endTimeGlobalStr2 != null ? DateTime.parse(endTimeGlobalStr2).toUtc() : null,
                      ),
                    ),
                  );
                }
              }

              participants = detail['participants'] as List<dynamic>? ?? participants;
              final startedAtStr2 = ch['started_at'] as String?;
              if (startedAtStr2 != null) {
                final start = DateTime.tryParse(startedAtStr2)?.toUtc();
                if (start != null) {
                  final end = start.add(Duration(minutes: durationMin));
                  final rem = end.difference(DateTime.now().toUtc()).inSeconds;
                  setStateDialog(() {
                    remaining = rem < 0 ? 0 : rem;
                  });
                }
              }
            } catch (_) {}
          });

          final ready = participants.where((p) => p['ready_status'] == 'listo').toList();
          final waiting = participants.where((p) => p['ready_status'] != 'listo').toList();

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
                          'Tiempo para empezar: ${_fmt(remaining)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (ready.isNotEmpty) ...[
                          const Text(
                            '✅ Listos para empezar:',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.successDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...ready.map((u) {
                            final name = u['nombre'] ?? 'Usuario';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.successLight,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(name),
                            );
                          }).toList(),
                          const SizedBox(height: 12),
                        ],
                        if (waiting.isNotEmpty) ...[
                          const Text(
                            '⏳ Esperando a:',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...waiting.map((u) {
                            final name = u['nombre'] ?? 'Usuario';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.warningBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(name),
                            );
                          }).toList(),
                        ],
                      ],
                    ),
                  ),
                  Divider(height: 0),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceVariant,
                          foregroundColor: AppColors.textTertiary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                        ),
                        child: const Text('Debes esperar a que todos estén listos'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    dialogTimer?.cancel();
  }

  Future<void> _loadDetail({bool initial = false}) async {
    if (!mounted) return;

    if (initial) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await widget.api.getChallengeDetail(widget.challengeId);
      final challengeJson = Map<String, dynamic>.from(data['challenge'] as Map);
      final participantsJson = (data['participants'] as List<dynamic>?) ?? [];

      final challenge = Challenge.fromJson(challengeJson);
      final normalizedDuration = _normalizeDurationMinutes(challenge.durationMinutes);
      final challengeNormalized = Challenge(
        id: challenge.id,
        title: challenge.title,
        area: challenge.area,
        level: challenge.level,
        quizId: challenge.quizId,
        scheduledDatetime: challenge.scheduledDatetime,
        durationMinutes: normalizedDuration,
        status: challenge.status,
        creatorId: challenge.creatorId,
        creatorName: challenge.creatorName,
        startedAt: challenge.startedAt,
        endedAt: challenge.endedAt,
      );

      final participants = participantsJson
          .map((p) => Participant.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList();

      final me = participants.firstWhere(
        (p) => p.userId == widget.api.currentUserId,
        orElse: () => Participant(
          userId: -1,
          name: '',
          username: '',
          invitationStatus: '',
          readyStatus: '',
        ),
      );

      if (!mounted) return;

      setState(() {
        _challenge = challengeNormalized;
        _participants = participants;
        _me = me.userId == -1 ? null : me;
        _loading = false;
        _error = null;
      });

      // navegación automática
      if (!_navigated &&
          _challenge != null &&
          _challenge!.status == 'en_curso' &&
          _me != null &&
          _me!.moodleAttemptId != null) {
        _navigated = true;
        final attemptId = _me!.moodleAttemptId!;
        final startedAtStr = (data['started_at'] as String?) ?? _challenge!.startedAt;
        final endTimeGlobalStr = (data['end_time_global'] as String?);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ChallengeQuestionScreen(
                api: widget.api,
                challengeId: widget.challengeId,
                attemptId: attemptId,
                quizId: _challenge!.quizId,
                durationMinutes: _challenge!.durationMinutes,
                startedAt: startedAtStr != null ? DateTime.tryParse(startedAtStr) : null,
                endTimeGlobal: endTimeGlobalStr != null ? DateTime.tryParse(endTimeGlobalStr) : null,
              ),
            ),
          );
        });
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('Error loading challenge detail: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshDetail() async => _loadDetail(initial: true);

  // ==========================
  //   WIDGETS
  // ==========================
  Widget _buildChallengeHeader() {
    final challenge = _challenge!;
    final statusColor = _getStatusColor(challenge.status);
    final areaColor = _getAreaColor(challenge.area);
    final areaIcon = _getAreaIcon(challenge.area);

    DateTime? startedAt;
    DateTime? endTimeGlobal;
    if (challenge.startedAt != null && challenge.startedAt!.isNotEmpty) {
      startedAt = DateTime.tryParse(challenge.startedAt!);
      if (startedAt != null) {
        endTimeGlobal = startedAt.add(Duration(minutes: challenge.durationMinutes));
      }
    }

    final remaining = endTimeGlobal != null ? endTimeGlobal.difference(DateTime.now()) : Duration.zero;
    final isTimeCritical = remaining.inMinutes < 5 && remaining.inMinutes > 0;

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
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 Header con ícono y título
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: areaColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: areaColor.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  areaIcon,
                  color: areaColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    
                    // 🔹 Estado del reto
                    Container(
                      constraints: const BoxConstraints(maxWidth: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        challenge.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // 🔹 Información del reto en chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Área
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: areaColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: areaColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      challenge.area.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: areaColor,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Nivel
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.trending_up_rounded,
                      size: 12,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Nivel ${challenge.level}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Duración
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 12,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${challenge.durationMinutes} min',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // 🔹 Fecha y creador - CORREGIDO EL OVERFLOW
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceClean,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Fecha
                Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Fecha programada:',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textDisabled,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatScheduled(challenge.scheduledDatetime),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.borderDark,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Creador
                Row(
                  children: [
                    Icon(
                      Icons.person_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Creado por:',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textDisabled,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            challenge.creatorName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.borderDark,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // 🔹 Cronómetro si está en curso
          if (challenge.status == 'en_curso' && endTimeGlobal != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isTimeCritical 
                    ? AppColors.errorFaint
                    : AppColors.surfaceClean,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isTimeCritical 
                      ? AppColors.errorFg
                      : AppColors.border,
                  width: isTimeCritical ? 1.5 : 1,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.timer_rounded,
                        size: 18,
                        color: isTimeCritical 
                            ? AppColors.error
                            : AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Tiempo restante',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isTimeCritical 
                              ? AppColors.error
                              : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _formatMmSs(remaining),
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: isTimeCritical 
                          ? AppColors.error
                          : AppColors.primary,
                    ),
                  ),
                  Text(
                    'El reto finalizará automáticamente',
                    style: TextStyle(
                      fontSize: 12,
                      color: isTimeCritical 
                          ? AppColors.error
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildParticipantCard(Participant p) {
    final statusColor = _getReadyStatusColor(p.readyStatus);
    String timeSpent = '';
    
    if (p.startTime != null && p.endTime != null) {
      final s = DateTime.tryParse(p.startTime!);
      final e = DateTime.tryParse(p.endTime!);
      if (s != null && e != null) {
        final spent = e.difference(s);
        timeSpent = _formatMmSs(spent);
      }
    }

    final isMe = p.userId == widget.api.currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe ? AppColors.infoBg : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? AppColors.infoFg : AppColors.border,
          width: isMe ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMd,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isMe ? AppColors.infoFg : AppColors.surfaceVariant,
              shape: BoxShape.circle,
              border: Border.all(
                color: isMe ? AppColors.infoFg : AppColors.border,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isMe ? AppColors.textOnPrimary : AppColors.textTertiary,
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Información
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isMe 
                              ? AppColors.infoDark 
                              : AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isMe)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.infoFg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'TÚ',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textOnPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        p.readyStatus.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                    if (timeSpent.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 10,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              timeSpent,
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          
          // Puntuación
          if (p.score != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Text(
                '${p.score!.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

Widget _buildActionButtons() {
  final challenge = _challenge!;
  final me = _me;
  final participants = _participants;

  // Calcular si todos están listos
  final allReady = participants.isNotEmpty &&
      participants.every((p) => p.readyStatus == 'listo');
  final isCreator = challenge.creatorId == widget.api.currentUserId;

  final bottomSafePadding = MediaQuery.of(context).viewPadding.bottom;

  return SafeArea(
    top: false,
    left: false,
    right: false,
    minimum: EdgeInsets.only(bottom: 12 + bottomSafePadding),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Aceptar / Rechazar
        if (me == null || me.invitationStatus == 'pendiente') ...[
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      final resp = await widget.api.respondChallenge(
                        challengeId: widget.challengeId,
                        action: 'accept',
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(resp['msg'] ?? 'Has aceptado el reto'),
                          backgroundColor: AppColors.successDark,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      await _refreshDetail();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: AppColors.error,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.successDark,
                    foregroundColor: AppColors.textOnPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Aceptar reto'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    try {
                      final resp = await widget.api.respondChallenge(
                        challengeId: widget.challengeId,
                        action: 'reject',
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(resp['msg'] ?? 'Has rechazado el reto'),
                          backgroundColor: AppColors.successDark,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      Navigator.pop(context, true);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: AppColors.error,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textTertiary,
                    side: BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.close_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Rechazar'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // Estoy listo
        if (me != null &&
            me.invitationStatus == 'aceptado' &&
            challenge.status == 'pendiente') ...[
          ElevatedButton(
            onPressed: () async {
              try {
                final resp = await widget.api.startChallenge(
                  challengeId: widget.challengeId,
                  action: 'ready',
                );

                if (resp['started'] == true) {
                  final participantsResp =
                      resp['participants'] as List<dynamic>? ?? [];
                  final meResp = participantsResp.firstWhere(
                    (p) => p['user_id'] == widget.api.currentUserId,
                    orElse: () => null,
                  );
                  final attemptId = meResp?['moodle_attempt_id'];
                  final startedAtStr = resp['started_at'] as String?;
                  final endTimeGlobalStr =
                      resp['end_time_global'] as String?;

                  if (attemptId != null) {
                    _goToQuestions(
                      attemptId: attemptId,
                      quizId: challenge.quizId,
                      challengeId: widget.challengeId,
                      durationMinutes: challenge.durationMinutes,
                      startedAtStr: startedAtStr,
                      endTimeGlobalStr: endTimeGlobalStr,
                    );
                  } else {
                    await _refreshDetail();
                  }
                } else {
                  await _showReadyDialog(resp);
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                await _refreshDetail();
              }
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
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, size: 18),
                SizedBox(width: 8),
                Text(
                  'Estoy listo',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Empezar ya (creador)
        if (challenge.status == 'pendiente' && isCreator && allReady) ...[
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: AppColors.textOnPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
            ),
            onPressed: () async {
              try {
                final resp = await widget.api.startChallenge(
                  challengeId: widget.challengeId,
                  action: 'force_start',
                );

                if (resp['started'] == true) {
                  final participantsResp =
                      resp['participants'] as List<dynamic>? ?? [];
                  final meResp = participantsResp.firstWhere(
                    (p) => p['user_id'] == widget.api.currentUserId,
                    orElse: () => null,
                  );
                  final attemptId = meResp?['moodle_attempt_id'];

                  DateTime? startedAt;
                  DateTime? endTimeGlobal;

                  if (resp['started_at'] != null) {
                    startedAt =
                        DateTime.parse(resp['started_at']).toUtc();
                  }
                  if (resp['end_time_global'] != null) {
                    endTimeGlobal =
                        DateTime.parse(resp['end_time_global']).toUtc();
                  }

                  if (attemptId != null) {
                    _goToQuestions(
                      attemptId: attemptId,
                      quizId: challenge.quizId,
                      challengeId: widget.challengeId,
                      durationMinutes: challenge.durationMinutes,
                      startedAt: startedAt,
                      endTimeGlobal: endTimeGlobal,
                    );
                  } else {
                    await _refreshDetail();
                  }
                } else {
                  await _refreshDetail();
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                await _refreshDetail();
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.flash_on_rounded, size: 18),
                SizedBox(width: 8),
                Text(
                  'Empezar ya',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Eliminar reto
        if (_canDeleteChallenge) ...[
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.errorDark,
              side: BorderSide(color: AppColors.errorDark),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _confirmAndDeleteChallenge,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_outline_rounded, size: 18),
                SizedBox(width: 8),
                Text(
                  'Eliminar reto',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Ver resultados
        if (challenge.status == 'finalizado') ...[
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.successDark,
              foregroundColor: AppColors.textOnPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChallengeResultsScreen(
                    api: widget.api,
                    challengeId: widget.challengeId,
                  ),
                ),
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.insights_rounded, size: 18),
                SizedBox(width: 8),
                Text(
                  'Ver resultados',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          centerTitle: false,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Detalle del reto',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Cargando información...',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
              SizedBox(height: 16),
              Text(
                'Cargando detalles del reto...',
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

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          centerTitle: false,
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Detalle del reto',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Error al cargar',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
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
                  blurRadius: 16,
                  offset: const Offset(0, 8),
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
                  'Error: $_error',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _refreshDetail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final challenge = _challenge!;
    final participants = _participants;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              challenge.title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              'ID: #${challenge.id} • ${participants.length} participantes',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshDetail,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔹 Header del reto
              _buildChallengeHeader(),
              
              const SizedBox(height: 20),
              
              // 🔹 Lista de participantes
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowSm,
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Participantes',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            '${participants.length}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...participants.map(_buildParticipantCard).toList(),
                  ],
                ),
              ),
              
              const SizedBox(height: 80), // Espacio para los botones inferiores
            ],
          ),
        ),
      ),
      bottomSheet: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowSm,
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: _buildActionButtons(),
        ),
      ),
    );
  }
}