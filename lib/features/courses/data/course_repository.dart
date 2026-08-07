// lib/features/courses/data/course_repository.dart
// Repository para cursos — separa lógica de datos de UI

import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../config/env.dart';
import '../../../core/types/result.dart';
import '../../../core/utils/app_logger.dart';
import '../../../models/course.dart';
import '../../../models/quiz.dart';
import '../../../models/quiz_question.dart';
import '../../../models/attempt.dart';

/// Repository de cursos y contenido
class CourseRepository {
  final String Function() _getToken;

  CourseRepository({required String Function() getToken}) : _getToken = getToken;

  Map<String, String> _headers([String? token]) => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  // ── Cursos ──
  Future<Result<List<Course>>> getCourses(String category) async {
    final token = _getToken();
    final url = Uri.parse('${Env.apiBaseUrl}/courses.php?category=$category');

    try {
      final resp = await http.get(url, headers: _headers(token));
      AppLogger.api('GET', '/courses.php?category=$category', statusCode: resp.statusCode);

      if (resp.statusCode != 200) return Failure('Error cargando cursos (${resp.statusCode})');

      final data = jsonDecode(resp.body);
      if (data['status'] != 'ok') return Failure(data['msg']?.toString() ?? 'Error');

      final courses = (data['courses'] as List)
          .map((json) => Course.fromJson(json as Map<String, dynamic>))
          .toList();

      return Success(courses);
    } catch (e) {
      AppLogger.e('getCourses ERROR', e);
      return const Failure('Error de conexión al cargar cursos');
    }
  }

  // ── Quizzes de un curso ──
  Future<Result<List<Quiz>>> getQuizzes(int courseId) async {
    final token = _getToken();
    final url = Uri.parse('${Env.apiBaseUrl}/quizzes.php?course_id=$courseId');

    try {
      final resp = await http.get(url, headers: _headers(token));
      AppLogger.api('GET', '/quizzes.php', statusCode: resp.statusCode);

      if (resp.statusCode != 200) return Failure('Error cargando quizzes');

      final data = jsonDecode(resp.body);
      if (data['status'] != 'ok') return Failure(data['msg']?.toString() ?? 'Error');

      final quizzes = (data['quizzes'] as List)
          .map((json) => Quiz.fromJson(json as Map<String, dynamic>))
          .toList();

      return Success(quizzes);
    } catch (e) {
      AppLogger.e('getQuizzes ERROR', e);
      return const Failure('Error de conexión al cargar quizzes');
    }
  }

  // ── Preguntas de un quiz ──
  Future<Result<List<QuizQuestion>>> getQuestions(int quizId) async {
    final token = _getToken();
    final url = Uri.parse('${Env.apiBaseUrl}/questions.php?quiz_id=$quizId');

    try {
      final resp = await http.get(url, headers: _headers(token));
      if (resp.statusCode != 200) return Failure('Error cargando preguntas');

      final data = jsonDecode(resp.body);
      if (data['status'] != 'ok') return Failure(data['msg']?.toString() ?? 'Error');

      final questions = (data['questions'] as List)
          .map((json) => QuizQuestion.fromJson(json as Map<String, dynamic>))
          .toList();

      return Success(questions);
    } catch (e) {
      AppLogger.e('getQuestions ERROR', e);
      return const Failure('Error de conexión al cargar preguntas');
    }
  }

  // ── Iniciar intento ──
  Future<Result<Attempt>> startAttempt(int quizId, int userId) async {
    final token = _getToken();
    final url = Uri.parse('${Env.apiBaseUrl}/start_attempt.php');

    try {
      final resp = await http.post(
        url,
        headers: _headers(token),
        body: jsonEncode({'quiz_id': quizId, 'user_id': userId}),
      );

      if (resp.statusCode != 200) return const Failure('Error al iniciar intento');

      final data = jsonDecode(resp.body);
      if (data['status'] != 'ok') return Failure(data['msg']?.toString() ?? 'Error');

      return Success(Attempt.fromJson(data['attempt'] as Map<String, dynamic>));
    } catch (e) {
      AppLogger.e('startAttempt ERROR', e);
      return const Failure('Error de conexión al iniciar intento');
    }
  }
}
