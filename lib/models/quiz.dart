class Quiz {
  final int id;
  final int courseid;
  final String name;
  final int timelimit;
  final int questions;

  // ✅ Getters compatibles con el resto del código
  int get quizId => id;
  int get courseId => courseid;

  Quiz({
    required this.id,
    required this.courseid,
    required this.name,
    required this.timelimit,
    required this.questions,
  });

  factory Quiz.fromJson(Map<String, dynamic> json) {
    return Quiz(
      id: json['quizid'] is int
          ? json['quizid'] as int
          : int.parse(json['quizid'].toString()),
      courseid: json['courseid'] is int
          ? json['courseid'] as int
          : int.parse(json['courseid'].toString()),
      name: json['name'] as String,
      timelimit: json['timelimit'] is int
          ? json['timelimit'] as int
          : int.parse(json['timelimit'].toString()),
      questions: json['questions'] is int
          ? json['questions'] as int
          : int.parse(json['questions'].toString()),
    );
  }
}
