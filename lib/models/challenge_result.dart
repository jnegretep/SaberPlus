// models/challenge_result.dart
class ChallengeResult {
  final int userId;
  final String name;
  final String username;
  final double score;
  final int position;
  final int correctas;
  final int incorrectas;
  final int tiempoTotal;
  final String? startTime;
  final String? endTime;
  final List<AnswerDetail> answers; // retroalimentación por pregunta

  ChallengeResult({
    required this.userId,
    required this.name,
    required this.username,
    required this.score,
    required this.position,
    required this.correctas,
    required this.incorrectas,
    required this.tiempoTotal,
    this.startTime,
    this.endTime,
    this.answers = const [],
  });

  factory ChallengeResult.fromJson(Map<String, dynamic> json) {
    return ChallengeResult(
      userId: int.tryParse(json['usuario_id']?.toString() ?? json['user_id']?.toString() ?? '') ?? 0,
      name: json['nombre'] ?? '',
      username: json['username'] ?? '',
      score: double.tryParse(json['puntaje']?.toString() ?? json['score']?.toString() ?? '0') ?? 0,
      position: int.tryParse(json['position']?.toString() ?? '0') ?? 0,
      correctas: int.tryParse(json['correctas']?.toString() ?? '0') ?? 0,
      incorrectas: int.tryParse(json['incorrectas']?.toString() ?? '0') ?? 0,
      tiempoTotal: int.tryParse(json['tiempo']?.toString() ?? json['tiempo_total']?.toString() ?? '0') ?? 0,
      startTime: json['start_time'],
      endTime: json['end_time'],
      answers: (json['answers'] as List<dynamic>? ?? [])
          .map((a) => AnswerDetail.fromJson(a as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'nombre': name,
      'username': username,
      'score': score,
      'position': position,
      'correctas': correctas,
      'incorrectas': incorrectas,
      'tiempo_total': tiempoTotal,
      'start_time': startTime,
      'end_time': endTime,
      'answers': answers.map((a) => a.toJson()).toList(),
    };
  }
}

/// Modelo auxiliar para retroalimentación por pregunta
class AnswerDetail {
  final int questionId;
  final String answer;
  final bool isCorrect;

  AnswerDetail({
    required this.questionId,
    required this.answer,
    required this.isCorrect,
  });

  factory AnswerDetail.fromJson(Map<String, dynamic> json) {
    return AnswerDetail(
      questionId: int.tryParse(json['question_id']?.toString() ?? '0') ?? 0,
      answer: json['answer']?.toString() ?? '',
      isCorrect: json['is_correct']?.toString() == '1' || json['is_correct'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'question_id': questionId,
      'answer': answer,
      'is_correct': isCorrect,
    };
  }
}
