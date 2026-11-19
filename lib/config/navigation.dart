// lib/config/navigation.dart
// Helpers de navegación para migrar de Navigator.pushNamed a GoRouter
// Centraliza todas las rutas para evitar strings mágicos

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/course.dart';
import '../controllers/quiz_controller.dart';

/// Navegación centralizada para Saber+
/// Reemplaza todos los Navigator.pushNamed() con estos métodos type-safe
class Nav {
  Nav._();

  // ── Público ──
  static void goWelcome(BuildContext context) => context.go('/welcome');
  static void goLogin(BuildContext context) => context.go('/login');

  // ── Registro ──
  static void goRegisterStep1(BuildContext context) => context.push('/register/step1');

  static void goRegisterStep2(
    BuildContext context, {
    required String nombre,
    required String email,
    required String telefono,
    required String username,
  }) {
    context.push('/register/step2', extra: {
      'nombre': nombre,
      'email': email,
      'telefono': telefono,
      'username': username,
    });
  }

  static void goVerifyEmail(
    BuildContext context, {
    required String email,
    required String userId,
    dynamic selectedImage,
    String? selectedAvatarAsset,
  }) {
    context.push('/register/verify-email', extra: {
      'email': email,
      'userId': userId,
      'selectedImage': selectedImage,
      'selectedAvatarAsset': selectedAvatarAsset,
    });
  }

  static void goSetPassword(
    BuildContext context, {
    required int userId,
    required String email,
    dynamic selectedImage,
    String? selectedAvatarAsset,
  }) {
    context.push('/register/set-password', extra: {
      'userId': userId,
      'email': email,
      'selectedImage': selectedImage,
      'selectedAvatarAsset': selectedAvatarAsset,
    });
  }

  // ── Recuperar contraseña ──
  static void goForgotPassword(BuildContext context) => context.push('/forgot-password');

  static void goVerifyReset(BuildContext context, {required String email}) {
    context.push('/forgot-password/verify-reset?email=$email');
  }

  static void goResetPassword(
    BuildContext context, {
    required int userId,
    required String email,
    String? resetToken,
  }) {
    context.push('/forgot-password/reset-password', extra: {
      'userId': userId,
      'email': email,
      'resetToken': resetToken,
    });
  }

  // ── Dashboard ──
  static void goDashboard(BuildContext context) => context.go('/dashboard');

  // ── Cursos ──
  static void goCourses(
    BuildContext context, {
    String category = 'courses',
    String title = 'Mis Cursos',
  }) {
    context.push('/courses?category=$category&title=$title');
  }

  static void goCourseContents(
    BuildContext context, {
    required int courseId,
    required String courseName,
  }) {
    context.push('/course-contents/$courseId?name=${Uri.encodeComponent(courseName)}');
  }

  static void goQuizzes(
    BuildContext context, {
    required Course course,
  }) {
    context.push('/quizzes/${course.id}?name=${Uri.encodeComponent(course.name)}');
  }

  static void goQuestion(
    BuildContext context, {
    required QuizController controller,
    required int courseId,
  }) {
    context.push('/question', extra: {
      'controller': controller,
      'courseId': courseId,
    });
  }

  /// ✅ PT1: reemplaza la pantalla actual por el cuestionario (equivale a
  /// Navigator.pushReplacement) manteniendo el historial del navegador
  /// sincronizado: back desde review NO vuelve al cuestionario.
  static void replaceQuestion(
    BuildContext context, {
    required QuizController controller,
    required int courseId,
  }) {
    context.pushReplacement('/question', extra: {
      'controller': controller,
      'courseId': courseId,
    });
  }

  static void goReview(
    BuildContext context, {
    required Map<String, dynamic> reviewData,
    required int courseId,
    required int quizId,
  }) {
    context.push('/review', extra: {
      'reviewData': reviewData,
      'courseId': courseId,
      'quizId': quizId,
    });
  }

  /// ✅ PT1: reemplaza la pantalla actual por la revisión.
  static void replaceReview(
    BuildContext context, {
    required Map<String, dynamic> reviewData,
    required int courseId,
    required int quizId,
  }) {
    context.pushReplacement('/review', extra: {
      'reviewData': reviewData,
      'courseId': courseId,
      'quizId': quizId,
    });
  }

  /// ✅ PT1: retrocede de forma segura. En web, si no hay páginas en la
  /// pila del router (p. ej. entrada directa por URL), lleva al dashboard
  /// en vez de dejar al usuario atrapado.
  static void safePop(BuildContext context, {String fallback = '/dashboard'}) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallback);
    }
  }

  // ✅ PT1: ficha del quiz (antes Navigator.push crudo)
  static void goQuizIntro(
    BuildContext context, {
    required int courseId,
    required int quizId,
    required String quizName,
    required int timeLimit,
    required int questions,
  }) {
    context.push('/quiz-intro/$courseId/$quizId', extra: {
      'quizName': quizName,
      'timeLimit': timeLimit,
      'questions': questions,
    });
  }

  // ✅ PT1: visor de contenido HTML (antes Navigator.push crudo)
  static void goHtmlViewer(
    BuildContext context, {
    required String title,
    required String html,
  }) {
    context.push('/html-viewer', extra: {
      'title': title,
      'html': html,
    });
  }

  // ✅ PT1: estadísticas del simulacro (antes Navigator.push crudo)
  static void goSimulacroStats(
    BuildContext context, {
    required int quizId,
    required int courseId,
  }) {
    context.push('/simulacro-stats/$quizId?courseId=$courseId');
  }

  // ✅ PT1: notificaciones (antes Navigator.push crudo)
  static void goNotifications(BuildContext context) =>
      context.push('/notifications');

  // ✅ PT1: tutor IA (antes Navigator.push crudo)
  static void goChat(BuildContext context) => context.push('/chat');

  // ✅ PT1: sub-pantallas de estadísticas (antes Navigator.push crudo)
  static void goAreaTrend(BuildContext context, {required String area}) {
    context.push('/stats/area-trend?area=${Uri.encodeComponent(area)}');
  }

  static void goComparativas(
    BuildContext context, {
    required String area,
    required String scope,
  }) {
    context.push(
        '/stats/comparativas?area=${Uri.encodeComponent(area)}&scope=$scope');
  }

  static void goRanking(
    BuildContext context, {
    required String area,
    required String scope,
  }) {
    context
        .push('/stats/ranking?area=${Uri.encodeComponent(area)}&scope=$scope');
  }

  // ── Perfil ──
  static void goProfile(BuildContext context) => context.push('/profile');
  static void goPerfilHub(BuildContext context) => context.push('/perfil-hub');
  static void goEditProfile(BuildContext context) => context.push('/edit-profile');
  static void goChangePassword(BuildContext context) => context.push('/change-password');

  // ── Estadísticas ──
  static void goEstadisticas(BuildContext context) => context.push('/estadisticas');

  // ── Logros / Achievements ──
  static void goAchievements(BuildContext context) => context.push('/achievements');

  // ── Ranking de XP ──
  static void goXpRanking(BuildContext context) => context.push('/xp-ranking');

  // ── Retos Diarios ──
  static void goDailyChallenges(BuildContext context) => context.push('/daily-challenges');

  // ── Prediccion ICFES ──
  static void goPrediction(BuildContext context) => context.push('/prediction');

  // ── Analisis de Errores ──
  static void goErrorAnalysis(BuildContext context) => context.push('/error-analysis');

  // ── Retos ──
  static void goChallenges(BuildContext context) => context.push('/challenges');
  static void goCreateChallenge(BuildContext context) => context.push('/challenges/create');

  static void goChallengeDetail(BuildContext context, {required int id}) {
    context.push('/challenges/$id');
  }

  static void goChallengeQuestion(
    BuildContext context, {
    required int challengeId,
    required int attemptId,
    required int quizId,
    required int duration,
  }) {
    context.push('/challenges/$challengeId/question', extra: {
      'attemptId': attemptId,
      'quizId': quizId,
      'duration': duration,
    });
  }

  static void goChallengeResults(BuildContext context, {required int id}) {
    context.push('/challenges/$id/results');
  }

  // ── Teacher ──
  static void goTeacher(BuildContext context) => context.go('/teacher');
  static void goTeacherStudents(BuildContext context) => context.push('/teacher/students');
  static void goTeacherStats(BuildContext context) => context.push('/teacher/stats');
  static void goTeacherReports(BuildContext context) => context.push('/teacher/reports');

  // ── Info ──
  static void goAcerca(BuildContext context) => context.push('/acerca');
  static void goPrivacidad(BuildContext context) => context.push('/privacidad');
  static void goSoporte(BuildContext context) => context.push('/soporte');

  // ── Upgrade ──
  static void goUpgrade(BuildContext context) => context.push('/upgrade');

  // ── Invitaciones ──
  static void goInvitations(BuildContext context) => context.push('/invitations');

  // ── Reemplazo ──
  /// Reemplaza Navigator.pushNamedAndRemoveUntil para login
  static void goToLoginAndClearStack(BuildContext context) {
    context.go('/login');
  }
}
