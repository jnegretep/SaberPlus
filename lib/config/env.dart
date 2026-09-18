// lib/config/env.dart
// Centraliza toda la configuración de entorno.
// ⚠️ NUNCA hardcodear URLs ni keys — siempre usar esta clase.
//
// Orden de prioridad (desde 2026-09):
//   1. --dart-define (compile-time, NO se empaqueta .env en el APK):
//      flutter build apk --dart-define=API_BASE_URL=https://...
//   2. .env empaquetado (legacy — seguirá funcionando durante la migración).
//
// ⚠️ Si ninguna fuente está configurada, la app falla explícitamente
//    en lugar de conectar a un servidor desconocido.

import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  Env._();

  /// Lee una variable desde .env (fuente legacy).
  /// Las variables inyectables en compilación usan constantes explícitas
  /// abajo, porque `String.fromEnvironment` no admite claves dinámicas.
  static String? _read(String key) {
    final fromDotenv = dotenv.env[key];
    if (fromDotenv != null && fromDotenv.isNotEmpty) return fromDotenv;
    return null;
  }

  /// Verifica que las variables de entorno críticas estén presentes.
  /// Lanza [EnvNotConfiguredException] si falta alguna.
  static void ensureConfigured() {
    if (apiBaseUrl.isEmpty) {
      throw EnvNotConfiguredException(
        'API_BASE_URL no está configurada. '
        'Compila con --dart-define=API_BASE_URL=https://... '
        'o asegúrate de que el archivo .env exista y la contenga.',
      );
    }
  }

  // ── Variables inyectables en compilación (--dart-define) ──
  // Prioridad: dart-define > .env
  static const _ddApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const _ddAvatarBaseUrl = String.fromEnvironment('AVATAR_BASE_URL');
  static const _ddDefaultAvatarUrl = String.fromEnvironment('DEFAULT_AVATAR_URL');
  static const _ddAiApiUrl = String.fromEnvironment('AI_API_URL');

  /// API Backend
  static String get apiBaseUrl =>
      _ddApiBaseUrl.isNotEmpty ? _ddApiBaseUrl : (_read('API_BASE_URL') ?? (throw _missing('API_BASE_URL')));

  static String get avatarBaseUrl =>
      _ddAvatarBaseUrl.isNotEmpty ? _ddAvatarBaseUrl : (_read('AVATAR_BASE_URL') ?? (throw _missing('AVATAR_BASE_URL')));

  static String get defaultAvatarUrl =>
      _ddDefaultAvatarUrl.isNotEmpty ? _ddDefaultAvatarUrl : (_read('DEFAULT_AVATAR_URL') ?? (throw _missing('DEFAULT_AVATAR_URL')));

  static String get aiApiUrl =>
      _ddAiApiUrl.isNotEmpty ? _ddAiApiUrl : (_read('AI_API_URL') ?? (throw _missing('AI_API_URL')));

  /// Firebase Web
  static String get firebaseApiKey =>
      dotenv.env['FIREBASE_API_KEY'] ?? '';

  static String get firebaseAuthDomain =>
      dotenv.env['FIREBASE_AUTH_DOMAIN'] ?? '';

  static String get firebaseProjectId =>
      dotenv.env['FIREBASE_PROJECT_ID'] ?? '';

  static String get firebaseStorageBucket =>
      dotenv.env['FIREBASE_STORAGE_BUCKET'] ?? '';

  static String get firebaseMessagingSenderId =>
      dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? '';

  static String get firebaseAppId =>
      dotenv.env['FIREBASE_APP_ID'] ?? '';

  static String get firebaseMeasurementId =>
      dotenv.env['FIREBASE_MEASUREMENT_ID'] ?? '';

  /// Helpers
  static bool get isConfigured =>
      dotenv.env['API_BASE_URL'] != null &&
      dotenv.env['API_BASE_URL']!.isNotEmpty;

  /// Extrae el host de la API URL (para Uri.http())
  static String get apiHost {
    final uri = Uri.parse(apiBaseUrl);
    return uri.host;
  }

  /// Extrae el path base de la API URL
  static String get apiBasePath {
    final uri = Uri.parse(apiBaseUrl);
    return uri.path;
  }

  /// Para debug: imprimir config sin exponer secrets
  static void debugPrintConfig() {
    assert(() {
      // ignore: avoid_print
      print('[Env] API: $apiBaseUrl');
      // ignore: avoid_print
      print('[Env] AI: $aiApiUrl');
      // ignore: avoid_print
      print('[Env] Firebase: ${firebaseProjectId.isNotEmpty ? "configured" : "missing"}');
      return true;
    }());
  }

  /// Helper para generar error descriptivo cuando falta una variable
  static EnvNotConfiguredException _missing(String key) {
    return EnvNotConfiguredException(
      '$key no está configurada. '
      'Verifica que el archivo .env exista y contenga $key.',
    );
  }
}

/// Excepción lanzada cuando una variable de entorno requerida no está configurada.
class EnvNotConfiguredException implements Exception {
  final String message;
  EnvNotConfiguredException(this.message);

  @override
  String toString() => 'EnvNotConfiguredException: $message';
}
