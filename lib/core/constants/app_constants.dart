// lib/core/constants/app_constants.dart
// Constantes globales de la aplicación Saber+

class AppConstants {
  AppConstants._();

  // ── App ──
  static const String appName = 'Saber+';
  static const String appTagline = 'Preparación ICFES Saber 11';
  static const String appVersion = '2.0.0';

  // ── Redes y contacto ──
  // ✅ v2.0: cuentas oficiales actualizadas por el propietario (nov-2026).
  static const String webUrl = 'https://saberplus.app';
  static const String supportEmail = 'Saberplus2026@gmail.com';
  static const String supportPhone = '+57 350 2114292';
  static const String whatsappUrl = 'https://wa.me/573502114292';
  static const String instagramUrl = 'https://www.instagram.com/saberplus15/';
  static const String instagramHandle = '@saberplus15';
  static const String tiktokUrl = 'https://www.tiktok.com/@saberplus5';
  static const String tiktokHandle = '@saberplus5';
  static const String facebookUrl =
      'https://www.facebook.com/profile.php?id=61586244015979';
  static const String facebookHandle = 'Saber+';

  // ── Storage Keys ──
  static const String keyJwt = 'jwt';
  static const String keyRefreshToken = 'refresh';
  static const String keyUser = 'user';
  static const String keyFirstTime = 'first_time';
  static const String keyRememberMe = 'remember';
  static const String keySavedEmail = 'email';
  // ✅ v2.0 (biometría rediseñada): la biometría es un BLOQUEO LOCAL de la
  // app, no un mecanismo de login. Solo se guarda un flag; NUNCA se guardan
  // contraseñas ni tokens dedicados. El desbloqueo valida la huella local y
  // la sesión la siguen gestionando el JWT + refresh normales del servidor.
  static const String keyAppLockEnabled = 'app_lock_enabled';
  // Legado (v1.x, ya no se usa en el flujo activo — se limpia si existe):
  static const String keyBiometricEnabled = 'biometric_enabled';
  static const String keyBiometricEmail = 'biometric_email';
  static const String keyBiometricRefreshToken = 'biometric_refresh_token';
  // Prompt único post-login para ofrecer activar el bloqueo biométrico:
  static const String keyBiometricPromptShown = 'biometric_prompt_shown';

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
