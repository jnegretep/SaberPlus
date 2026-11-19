// lib/models/daily_challenge.dart
// Saber+ — Modelo de Retos Diarios

/// Estado de un reto diario.
enum DailyChallengeStatus {
  available,    // disponible pero no completado
  completed,    // ya completado hoy
  pending,      // pendiente (sin iniciar)
}

/// Un reto diario individual.
class DailyChallenge {
  final int id;              // ID del quiz en Moodle
  final String name;         // Nombre del reto
  final int courseId;        // ID del curso (56-60)
  final String area;         // Área/materia (Matemáticas, Sociales, etc.)
  final String areaColor;    // Color del área en hex
  final String areaIcon;     // Icono Material del área
  final int timeopen;        // Timestamp de apertura
  final int timeclose;       // Timestamp de cierre
  final int timelimit;       // Límite de tiempo en segundos
  final int questions;       // Número de preguntas
  final String? completedAt; // Fecha de completado (si aplica)

  DailyChallenge({
    required this.id,
    required this.name,
    required this.courseId,
    required this.area,
    required this.areaColor,
    required this.areaIcon,
    required this.timeopen,
    required this.timeclose,
    required this.timelimit,
    required this.questions,
    this.completedAt,
  });

  factory DailyChallenge.fromJson(Map<String, dynamic> json) {
    return DailyChallenge(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? 'Reto Diario',
      courseId: (json['course_id'] as num).toInt(),
      area: json['area'] as String? ?? 'General',
      areaColor: json['area_color'] as String? ?? '#1E4ED8',
      areaIcon: json['area_icon'] as String? ?? 'extension_rounded',
      timeopen: (json['timeopen'] as num?)?.toInt() ?? 0,
      timeclose: (json['timeclose'] as num?)?.toInt() ?? 0,
      timelimit: (json['timelimit'] as num?)?.toInt() ?? 0,
      questions: (json['questions'] as num?)?.toInt() ?? 0,
      completedAt: json['completed_at'] as String?,
    );
  }

  /// true si el reto ya fue completado
  bool get isCompleted => completedAt != null;

  /// true si el reto está disponible ahora (dentro de la ventana de tiempo)
  bool get isAvailableNow {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (timeopen > 0 && now < timeopen) return false;
    if (timeclose > 0 && now > timeclose) return false;
    return true;
  }

  /// Tiempo restante para que cierre el reto (en segundos, 0 si no hay límite)
  int get remainingTime {
    if (timeclose <= 0) return 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final remaining = timeclose - now;
    return remaining > 0 ? remaining : 0;
  }

  /// Formatea el tiempo restante como "Xh Ym" o "Xm"
  String get remainingTimeFormatted {
    final seconds = remainingTime;
    if (seconds <= 0) return 'Expirado';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

/// Respuesta completa del endpoint de retos diarios.
class DailyChallengesResponse {
  final String date;
  final List<DailyChallenge> available;
  final List<DailyChallenge> completed;
  final List<DailyChallenge> pending;
  final int totalAvailable;
  final int totalCompleted;
  final bool allCompleted;
  final int totalChallenges;

  DailyChallengesResponse({
    required this.date,
    required this.available,
    required this.completed,
    required this.pending,
    required this.totalAvailable,
    required this.totalCompleted,
    required this.allCompleted,
    required this.totalChallenges,
  });

  factory DailyChallengesResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    final availableRaw = (data['available'] as List<dynamic>? ?? []);
    final completedRaw = (data['completed'] as List<dynamic>? ?? []);
    final pendingRaw = (data['pending'] as List<dynamic>? ?? []);

    return DailyChallengesResponse(
      date: data['date'] as String? ?? '',
      available: availableRaw
          .map((e) => DailyChallenge.fromJson(e as Map<String, dynamic>))
          .toList(),
      completed: completedRaw
          .map((e) => DailyChallenge.fromJson(e as Map<String, dynamic>))
          .toList(),
      pending: pendingRaw
          .map((e) => DailyChallenge.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalAvailable: (data['total_available'] as num?)?.toInt() ?? 0,
      totalCompleted: (data['total_completed'] as num?)?.toInt() ?? 0,
      allCompleted: data['all_completed'] as bool? ?? false,
      totalChallenges: (data['total_challenges'] as num?)?.toInt() ?? 0,
    );
  }
}
