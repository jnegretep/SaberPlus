// models/challenge.dart
class Challenge {
  final int id;
  final String title;
  final String area;
  final String level;
  final int quizId;
  final String scheduledDatetime;
  final int durationMinutes;
  final String status; // pendiente, en_curso, finalizado
  final int creatorId;
  final String creatorName;
  final String? startedAt;
  final String? endedAt;
  final int participantsCount; // 👈 nuevo campo

  Challenge({
    required this.id,
    required this.title,
    required this.area,
    required this.level,
    required this.quizId,
    required this.scheduledDatetime,
    required this.durationMinutes,
    required this.status,
    required this.creatorId,
    required this.creatorName,
    this.startedAt,
    this.endedAt,
    this.participantsCount = 0, // 👈 valor por defecto
  });

  factory Challenge.fromJson(Map<String, dynamic> json) {
    return Challenge(
      id: int.tryParse(json['challenge_id']?.toString() ?? '') ?? json['id'] ?? 0,
      title: json['title'] ?? '',
      area: json['area'] ?? '',
      level: json['level'] ?? '',
      quizId: int.tryParse(json['quiz_id']?.toString() ?? '') ?? 0,
      scheduledDatetime: json['scheduled_datetime'] ?? '',
      durationMinutes: int.tryParse(json['duration_minutes']?.toString() ?? '') ?? 0,
      status: json['status'] ?? json['challenge_status'] ?? '',
      creatorId: int.tryParse(json['creator_id']?.toString() ?? '') ?? 0,
      creatorName: json['creator_name'] ?? '',
      startedAt: json['started_at'],
      endedAt: json['ended_at'],
      participantsCount: int.tryParse(json['participantsCount']?.toString() ?? '') ?? 0, // 👈 parseo seguro
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'challenge_id': id,
      'title': title,
      'area': area,
      'level': level,
      'quiz_id': quizId,
      'scheduled_datetime': scheduledDatetime,
      'duration_minutes': durationMinutes,
      'status': status,
      'creator_id': creatorId,
      'creator_name': creatorName,
      'started_at': startedAt,
      'ended_at': endedAt,
      'participantsCount': participantsCount, // 👈 exportar también
    };
  }
}
