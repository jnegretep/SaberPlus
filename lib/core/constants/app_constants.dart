// lib/core/constants/app_constants.dart
// Constantes globales de la aplicación Saber+

class AppConstants {
  AppConstants._();

  // ── App ──
  static const String appName = 'Saber+';
  static const String appTagline = 'Preparación ICFES Saber 11';
  static const String appVersion = '1.5.0';

  // ── Storage Keys ──
  static const String keyJwt = 'jwt';
  static const String keyRefreshToken = 'refresh';
  static const String keyUser = 'user';
  static const String keyFirstTime = 'first_time';
  static const String keyRememberMe = 'remember';
  static const String keySavedEmail = 'email';
  // NOTA: NUNCA guardar la contraseña en SharedPreferences (security risk)
  // La contraseña se elimina del storage en esta versión.

  // ── API Timeouts ──
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration sendTimeout = Duration(seconds: 15);

  // ── Caché ──
  static const Duration cacheValidDuration = Duration(minutes: 5);
  static const int maxCacheEntries = 100;

  // ── UI ──
  static const double borderRadiusSmall = 8.0;
  static const double borderRadiusMedium = 14.0;
  static const double borderRadiusLarge = 20.0;
  static const double borderRadiusXLarge = 28.0;

  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  // ── Categorías de cursos ──
  static const String categorySimulacros = 'simulacros';
  static const String categoryCourses = 'courses';
  static const String categoryRetos = 'retos';

  // ── Roles ──
  static const String roleEstudiante = 'estudiante';
  static const String roleProfesor = 'profesor';
  static const String roleAdmin = 'admin';

  // ── Assets ──
  static const String assetLogo = 'assets/images/saberplus.png';
  static const String assetPrepLogo = 'assets/images/prepsaber_logo.png';
  static const String assetDefaultAvatar = 'assets/avatars/avatar_1.png';

  static const List<String> courseCardImages = [
    'assets/images/cards/book_blue.png',
    'assets/images/cards/book_green.png',
    'assets/images/cards/book_orange.png',
  ];

  static const List<String> simulacroCardImages = [
    'assets/images/cards/cube_purple.png',
    'assets/images/cards/stats.png',
    'assets/images/cards/questionnaire.png',
  ];

  static const List<String> retoCardImages = [
    'assets/images/cards/book_blue.png',
    'assets/images/cards/book_green.png',
    'assets/images/cards/book_orange.png',
  ];
}
