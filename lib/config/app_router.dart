// lib/config/app_router.dart
// GoRouter configuration for Saber+
// Type-safe navigation with auth guards and deep linking

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/app_logger.dart';
import '../models/course.dart';
import '../controllers/quiz_controller.dart';

// Screens
import '../screens/welcome_screen.dart';
import '../screens/login_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/course_list_screen.dart';
import '../screens/course_contents_screen.dart';
import '../screens/quiz_list_screen.dart';
import '../screens/question_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/verify_reset_password_screen.dart';
import '../screens/register_step1.dart';
import '../screens/register_step2.dart';
import '../screens/verify_email_screen.dart';
import '../screens/set_password_screen.dart';
import '../screens/perfil_screen.dart';
import '../screens/acerca_screen.dart';
import '../screens/privacidad_screen.dart';
import '../screens/perfil_hub_screen.dart';
import '../screens/stats_home_screen.dart';
import '../screens/challenge_list_screen.dart';
import '../screens/challenge_detail_screen.dart';
import '../screens/challenge_results_screen.dart';
import '../screens/challenge_question_screen.dart';
import '../screens/create_challenge_screen.dart';
import '../screens/edit_profile_complete_screen.dart';
import '../screens/change_password_screen.dart';
import '../screens/review_screen.dart';
import '../screens/teacher/teacher_dashboard_screen.dart';
import '../screens/teacher/teacher_reports_screen.dart';
import '../screens/teacher/teacher_stats_screen.dart';
import '../screens/teacher/teacher_students_screen.dart';
import '../screens/invitations_screen.dart';
import '../screens/achievements_screen.dart';
import '../screens/xp_ranking_screen.dart';

/// Rutas que NO requieren autenticación
const _publicRoutes = {
  '/welcome',
  '/login',
  '/register',
  '/register/step1',
  '/register/step2',
  '/register/verify-email',
  '/register/set-password',
  '/forgot-password',
  '/forgot-password/verify-reset',
  '/forgot-password/reset-password',
};

/// Construye el GoRouter con auth guard
GoRouter buildAppRouter({
  required AuthService auth,
  required ApiService api,
  required String initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    debugLogDiagnostics: true,
    // ✅ FIX #1: refreshListenable permite que el router reaccione a cambios
    // de auth SIN necesidad de recrear el router. Esto evita que tras login
    // el usuario sea devuelto a la pantalla inicial.
    refreshListenable: auth,
    redirect: (context, state) {
      final isAuthenticated = auth.token != null;
      final isPublicRoute = _publicRoutes.contains(state.matchedLocation);

      // Si no autenticado y ruta protegida → login
      if (!isAuthenticated && !isPublicRoute) {
        AppLogger.d('Redirect: ${state.matchedLocation} → /login (no auth)');
        return '/login';
      }

      // ✅ FIX #1+#3: Si autenticado y en ruta pública (INCLUSIVE /welcome) → dashboard
      // Antes se excluía /welcome, causaba que tras login el usuario quedara atrapado en welcome
      if (isAuthenticated && isPublicRoute) {
        final target = auth.isProfesor ? '/teacher' : '/dashboard';
        AppLogger.d('Redirect: ${state.matchedLocation} → $target (already auth)');
        return target;
      }

      return null; // Sin redirect
    },
    routes: [
      // ── Público ──
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(),
      ),

      // ── Registro ──
      GoRoute(
        path: '/register/step1',
        builder: (context, state) => const RegisterStep1(),
      ),
      GoRoute(
        path: '/register/step2',
        builder: (context, state) {
          final extra = state.extra as Map<String, String>? ?? {};
          return RegisterStep2(
            nombre: extra['nombre'] ?? '',
            email: extra['email'] ?? '',
            telefono: extra['telefono'] ?? '',
            username: extra['username'] ?? '',
          );
        },
      ),
      GoRoute(
        path: '/register/verify-email',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return VerifyEmailScreen(
            email: extra['email'] as String,
            userId: extra['userId'] as String,
            selectedImage: extra['selectedImage'],
            selectedAvatarAsset: extra['selectedAvatarAsset'],
          );
        },
      ),
      GoRoute(
        path: '/register/set-password',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return SetPasswordScreen(
            userId: extra['userId'] as int,
            email: extra['email'] as String,
            selectedImage: extra['selectedImage'],
            selectedAvatarAsset: extra['selectedAvatarAsset'],
          );
        },
      ),

      // ── Recuperar contraseña ──
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/forgot-password/verify-reset',
        builder: (context, state) {
          final email = state.uri.queryParameters['email'] ?? '';
          return VerifyResetPasswordScreen(email: email);
        },
      ),
      GoRoute(
        path: '/forgot-password/reset-password',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return SetPasswordScreen(
            userId: extra['userId'] as int,
            email: extra['email'] as String,
            resetToken: extra['resetToken'] as String?,
          );
        },
      ),

      // ── Dashboard (principal) ──
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),

      // ── Cursos ──
      GoRoute(
        path: '/courses',
        builder: (context, state) {
          final category = state.uri.queryParameters['category'] ?? AppConstants.categoryCourses;
          final title = state.uri.queryParameters['title'] ?? 'Mis Cursos';
          return CourseListScreen(category: category, title: title);
        },
      ),
      GoRoute(
        path: '/course-contents/:courseId',
        builder: (context, state) {
          final courseId = int.parse(state.pathParameters['courseId']!);
          final courseName = state.uri.queryParameters['name'] ?? '';
          return CourseContentsScreen(courseId: courseId, courseName: courseName);
        },
      ),
      GoRoute(
        path: '/quizzes/:courseId',
        builder: (context, state) {
          final courseId = int.parse(state.pathParameters['courseId']!);
          final courseName = state.uri.queryParameters['name'] ?? '';
          final course = Course(
            id: courseId,
            fullname: courseName,
            shortname: courseName,
            startdate: 0,
            enddate: 0,
            visible: true,
          );
          return QuizListScreen(course: course);
        },
      ),
      GoRoute(
        path: '/question',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return QuestionScreen(
            controller: extra['controller'] as QuizController,
            courseId: extra['courseId'] as int,
          );
        },
      ),
      GoRoute(
        path: '/review',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return ReviewScreen(
            reviewData: extra['reviewData'] as Map<String, dynamic>,
            courseId: extra['courseId'] as int,
            quizId: extra['quizId'] as int,
          );
        },
      ),

      // ── Perfil ──
      GoRoute(
        path: '/profile',
        builder: (context, state) => const PerfilScreen(),
      ),
      GoRoute(
        path: '/perfil-hub',
        builder: (context, state) => const PerfilHubScreen(),
      ),
      GoRoute(
        path: '/edit-profile',
        builder: (context, state) => const EditProfileCompleteScreen(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),

      // ── Estadísticas ──
      GoRoute(
        path: '/estadisticas',
        builder: (context, state) => StatsHomeScreen(),
      ),

      // ── Logros / Achievements ──
      GoRoute(
        path: '/achievements',
        builder: (context, state) => const AchievementsScreen(),
      ),

      // ── Ranking de XP ──
      GoRoute(
        path: '/xp-ranking',
        builder: (context, state) => const XpRankingScreen(),
      ),

      // ── Retos (Challenges) ──
      GoRoute(
        path: '/challenges',
        builder: (context, state) => ChallengeListScreen(api: api),
      ),
      GoRoute(
        path: '/challenges/create',
        builder: (context, state) => CreateChallengeScreen(api: api),
      ),
      GoRoute(
        path: '/challenges/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return ChallengeDetailScreen(api: api, challengeId: id);
        },
      ),
      GoRoute(
        path: '/challenges/:id/question',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          final extra = state.extra as Map<String, dynamic>;
          return ChallengeQuestionScreen(
            api: api,
            challengeId: id,
            attemptId: extra['attemptId'] as int,
            quizId: extra['quizId'] as int,
            durationMinutes: extra['duration'] as int,
          );
        },
      ),
      GoRoute(
        path: '/challenges/:id/results',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return ChallengeResultsScreen(api: api, challengeId: id);
        },
      ),

      // ── Teacher ──
      GoRoute(
        path: '/teacher',
        builder: (context, state) => const TeacherDashboardScreen(),
      ),
      GoRoute(
        path: '/teacher/students',
        builder: (context, state) => const TeacherStudentsScreen(),
      ),
      GoRoute(
        path: '/teacher/stats',
        builder: (context, state) => const TeacherStatsScreen(),
      ),
      GoRoute(
        path: '/teacher/reports',
        builder: (context, state) => const TeacherReportsScreen(),
      ),

      // ── Info ──
      GoRoute(
        path: '/acerca',
        builder: (context, state) => const AcercaScreen(),
      ),
      GoRoute(
        path: '/privacidad',
        builder: (context, state) => const PrivacidadScreen(),
      ),

      // ── Invitaciones ──
      GoRoute(
        path: '/invitations',
        builder: (context, state) => const InvitationsScreen(),
      ),
    ],

    // Error page para rutas no encontradas
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Página no encontrada',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(state.matchedLocation),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Volver al inicio'),
            ),
          ],
        ),
      ),
    ),
  );
}
