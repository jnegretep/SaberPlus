// models/participant.dart
class Participant {
  final int userId;
  final String name;
  final String username;
  final String invitationStatus; // pendiente, aceptado, rechazado
  final String readyStatus;      // esperando, listo, jugando, terminado
  final double? score;
  final String? startTime;
  final String? endTime;
  final int? moodleAttemptId;    // 👈 nuevo campo
  final String? answersJson;     // 👈 nuevo campo opcional

  Participant({
    required this.userId,
    required this.name,
    required this.username,
    required this.invitationStatus,
    required this.readyStatus,
    this.score,
    this.startTime,
    this.endTime,
    this.moodleAttemptId,
    this.answersJson,
  });

  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      userId: int.tryParse(json['id_usuario']?.toString() ?? json['user_id']?.toString() ?? '') ?? 0,
      name: json['nombre'] ?? '',
      username: json['username'] ?? '',
      invitationStatus: json['invitation_status'] ?? '',
      readyStatus: json['ready_status'] ?? '',
      score: json['score'] != null ? double.tryParse(json['score'].toString()) : null,
      startTime: json['start_time'],
      endTime: json['end_time'],
      moodleAttemptId: json['moodle_attempt_id'] != null
          ? int.tryParse(json['moodle_attempt_id'].toString())
          : null,
      answersJson: json['answers_json'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'nombre': name,
      'username': username,
      'invitation_status': invitationStatus,
      'ready_status': readyStatus,
      'score': score,
      'start_time': startTime,
      'end_time': endTime,
      'moodle_attempt_id': moodleAttemptId,
      'answers_json': answersJson,
    };
  }
}
