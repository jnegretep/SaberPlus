// test/models/models_test.dart
// Unit tests for key data models — fromJson safe parsing

import 'package:flutter_test/flutter_test.dart';
import 'package:saberplus_app/models/course.dart';
import 'package:saberplus_app/models/quiz.dart';
import 'package:saberplus_app/models/attempt.dart';
import 'package:saberplus_app/models/challenge.dart';
import 'package:saberplus_app/models/summary_stats.dart';
import 'package:saberplus_app/models/plan.dart';

void main() {
  group('Course', () {
    test('fromJson creates valid Course from complete JSON', () {
      final json = {
        'id': 1,
        'name': 'Simulacro 1',
        'fullname': 'Simulacro ICFES 1',
        'category': 'simulacro',
        'progress': 75.0,
        'attempted': true,
      };

      final course = Course.fromJson(json);
      expect(course.id, equals(1));
      expect(course.name, equals('Simulacro 1'));
      expect(course.fullname, equals('Simulacro ICFES 1'));
      expect(course.progress, equals(75.0));
      expect(course.attempted, isTrue);
    });

    test('fromJson handles missing optional fields gracefully', () {
      final json = {
        'id': 2,
        'name': 'Curso Test',
      };

      final course = Course.fromJson(json);
      expect(course.id, equals(2));
      expect(course.name, equals('Curso Test'));
      expect(course.attempted, isFalse);
    });
  });

  group('Quiz', () {
    test('fromJson creates valid Quiz', () {
      final json = {
        'id': 10,
        'name': 'Quiz Matemáticas',
        'courseid': 1,
        'questions': [],
      };

      final quiz = Quiz.fromJson(json);
      expect(quiz.id, equals(10));
      expect(quiz.name, equals('Quiz Matemáticas'));
    });
  });

  group('Attempt', () {
    test('fromJson creates valid Attempt', () {
      final json = {
        'id': 100,
        'quizid': 10,
        'userid': 5,
        'state': 'finished',
        'timestart': 1700000000,
        'timefinish': 1700003600,
      };

      final attempt = Attempt.fromJson(json);
      expect(attempt.id, equals(100));
      expect(attempt.quizid, equals(10));
    });
  });

  group('Challenge', () {
    test('fromJson creates valid Challenge', () {
      final json = {
        'id': 1,
        'nombre': 'Reto Matemáticas',
        'descripcion': 'Reto de práctica',
        'quiz_id': 10,
        'duracion_minutos': 30,
        'activo': true,
        'created_by': 5,
      };

      final challenge = Challenge.fromJson(json);
      expect(challenge.id, equals(1));
      expect(challenge.nombre, equals('Reto Matemáticas'));
      expect(challenge.activo, isTrue);
    });
  });

  group('SummaryStats', () {
    test('fromJson handles nested areas map', () {
      final json = {
        'promedio_global': 320.5,
        'areas': {
          'Matemáticas': 65.0,
          'Lectura': 70.0,
          'Sociales': 55.0,
          'Ciencias': 60.0,
          'Inglés': 50.0,
        },
        'ultima_fecha': '2024-01-15',
        'tiempo_promedio_seg': 1800,
      };

      final stats = SummaryStats.fromJson(json);
      expect(stats.promedioGlobal, equals(320.5));
      expect(stats.areas, isNotNull);
      expect(stats.areas.length, equals(5));
    });
  });

  group('Plan', () {
    test('fromJson creates valid Plan with features', () {
      final json = {
        'id': 1,
        'nombre': 'Premium',
        'precio': 29900.0,
        'duracion_dias': 30,
        'features': [
          {'nombre': 'Simulacros ilimitados', 'incluido': true},
          {'nombre': 'Retos grupales', 'incluido': true},
          {'nombre': 'IA avanzada', 'incluido': false},
        ],
      };

      final plan = Plan.fromJson(json);
      expect(plan.id, equals(1));
      expect(plan.nombre, equals('Premium'));
      expect(plan.precio, equals(29900.0));
    });
  });
}
