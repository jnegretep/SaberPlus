// lib/services/analytics_service.dart
// Saber+ — Analítica y reporte de fallos v1.6.0
//
// Doble capa:
//  1. Firebase Analytics (fuente principal de funnel/retención).
//  2. Espejo propio en el backend (registrar_evento.php → tabla
//     app_events) para que el administrador vea métricas en el
//     panel /admin sin depender de Firebase.
//
// Crashlytics:
//  - Solo móvil (android/ios). En web no está soportado y se omite.
//  - Captura errores de Flutter + errores no capturados del dispatcher.
//  - Los errores no fatales también se envían al backend como
//    evento 'app_error' (visibles en Admin → Errores).
//
// Uso:
//   await AnalyticsService.initialize();          // en main()
//   AnalyticsService.logLogin(method: 'password');
//   AnalyticsService.logSimulacroCompleted(score: 342);
//   AnalyticsService.recordError(e, stack, reason: 'cargar dashboard');

import 'dart:async';
// 🔧 FIX #1: PlatformDispatcher vive en dart:ui. Sin este import, el
// compilador marca "Undefined name 'PlatformDispatcher'".
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:dio/dio.dart';

import '../config/env.dart';
import '../core/utils/app_logger.dart';

class AnalyticsService {
  AnalyticsService._();

  static FirebaseAnalytics? _analytics;
  static bool _initialized = false;

  /// Versión de la app reportada al backend (actualizar con cada release).
  static const String appVersion = '1.6.0';

  // ─────────────────────────────────────────────
  // Inicialización
  // ─────────────────────────────────────────────

  /// Debe llamarse en main() DESPUÉS de Firebase.initializeApp().
  /// Configura Crashlytics (solo móvil) y registra el observer de
  /// pantallas para el enrutador.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _analytics = FirebaseAnalytics.instance;

      // Deshabilitar reporting en debug para no contaminar métricas
      if (kDebugMode) {
        await _analytics?.setAnalyticsCollectionEnabled(false);
      }

      if (!kIsWeb) {
        // ── Crashlytics: errores de Flutter ──
        FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

        // ── Crashlytics: errores async no capturados ──
        // 🔧 FIX #1 (cont.): PlatformDispatcher solo existe en mobile/desktop.
        // En web hay otros mecanismos (window.onerror), pero por ahora lo
        // omitimos para no complicar. Está protegido por `!kIsWeb`.
        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          _reportErrorToBackend(error.toString(), stack?.toString(), fatal: true);
          return true;
        };
      }

      AppLogger.i('AnalyticsService inicializado '
          '(crashlytics=${kIsWeb ? "web-off" : "on"})');
    } catch (e) {
      AppLogger.e('AnalyticsService.initialize error (no bloqueante)', e);
    }
  }

  /// Observer para GoRouter: registra screen_view automático.
  /// Uso en buildAppRouter: observers: [AnalyticsService.observer]
  static NavigatorObserver get observer => _AnalyticsObserver();

  static FirebaseAnalytics? get analytics => _analytics;

  // ─────────────────────────────────────────────
  // Identidad
  // ─────────────────────────────────────────────

  /// Vincula el usuario (id propio) para funnel por usuario.
  /// No se envía email ni PII.
   /// Vincula el usuario (id propio) para funnel por usuario.
  /// No se envía email ni PII.
  static Future<void> setUserId(int? userId) async {
    if (userId == null) return;
    try {
      // 🔧 FIX: `setUserId` cambió de firma entre versiones de
      // firebase_analytics. `setUserProperty` es estable y siempre usa
      // argumentos nombrados (name:, value:), así que funciona en todas.
      await _analytics?.setUserProperty(
        name: 'user_id',
        value: userId.toString(),
      );
    } catch (_) {}
  }

  // ─────────────────────────────────────────────
  // Eventos de negocio (Firebase + espejo backend)
  // ─────────────────────────────────────────────

  static Future<void> logLogin({String method = 'password'}) async {
    await _log('login', {'method': method});
  }

  static Future<void> logSignUp({String method = 'email'}) async {
    await _log('sign_up', {'method': method});
  }

  static Future<void> logSimulacroStarted({String? simulacroName}) async {
    await _log('simulacro_started', {'name': simulacroName});
  }

  static Future<void> logSimulacroCompleted({
    required double score,
    int? correctas,
    int? total,
  }) async {
    await _log('simulacro_completed', {
      'score': score,
      if (correctas != null) 'correctas': correctas,
      if (total != null) 'total': total,
    });
  }

  static Future<void> logQuizCompleted({required int score, int? total}) async {
    await _log('quiz_completed', {'score': score, if (total != null) 'total': total});
  }

  static Future<void> logChallengeCompleted({required int position, required int xp}) async {
    await _log('challenge_completed', {'position': position, 'xp': xp});
  }

  static Future<void> logBadgeUnlocked({required String badge}) async {
    await _log('badge_unlocked', {'badge': badge});
  }

  static Future<void> logPaywallViewed({String? plan}) async {
    await _log('paywall_viewed', {if (plan != null) 'plan': plan});
  }

  static Future<void> logPurchaseStarted({String? plan, int? priceCop}) async {
    await _log('purchase_started', {if (plan != null) 'plan': plan, if (priceCop != null) 'price_cop': priceCop});
  }

  static Future<void> logPurchaseCompleted({String? plan}) async {
    await _log('purchase_completed', {if (plan != null) 'plan': plan});
  }

  static Future<void> logShareClicked({required String contentType}) async {
    await _log('share_clicked', {'content_type': contentType});
  }

  static Future<void> logAiChatOpened() async {
    await _log('ai_chat_opened', {});
  }

  static Future<void> logRankingViewed({required String tipo}) async {
    await _log('ranking_viewed', {'tipo': tipo});
  }

  static Future<void> logAccountDeleteStarted() async {
    await _log('account_delete_started', {});
  }

  static Future<void> logScreenView(String screenName) async {
    await _log('screen_view', {'screen_name': screenName});
  }

  // ─────────────────────────────────────────────
  // Núcleo: envío dual (Firebase + backend)
  // ─────────────────────────────────────────────

  static Future<void> _log(String name, Map<String, Object?> params) async {
    // 1. Firebase Analytics
    try {
      await _analytics?.logEvent(
        name: name,
        parameters: params.map((k, v) => MapEntry(k, v ?? '')),
      );
    } catch (e) {
      AppLogger.d('Analytics firebase "$name" falló (no bloqueante): $e');
    }

    // 2. Espejo en el backend (fire-and-forget)
    _sendToBackend(name, params);
  }

  static Future<void> _sendToBackend(String name, Map<String, Object?> params) async {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      // JWT lo inyecta quien corresponda; si no hay sesión, el backend
      // responde 401 y se ignora (eventos pre-login solo van a Firebase).
      dio.options.headers['Content-Type'] = 'application/json';

      // Token estático accesible (lo setea AuthService al hacer login)
      final token = authToken;
      if (token != null && token.isNotEmpty) {
        dio.options.headers['Authorization'] = 'Bearer $token';

        unawaited(dio.post(
          '/registrar_evento.php',
          data: {
            'event_name': name,
            'params': params,
            'app_version': appVersion,
            'platform': kIsWeb ? 'web' : 'android',
          },
        ).catchError((_) {})); // fire-and-forget total
      }
    } catch (_) {
      // Nunca bloquear la app por analítica
    }
  }

  /// JWT actual para el espejo de eventos. AuthService lo actualiza.
  /// (Estático y simple: mismo patrón que DioClient.authToken.)
  static String? authToken;

  // ─────────────────────────────────────────────
  // Errores
  // ─────────────────────────────────────────────

  /// Registra un error no fatal: Crashlytics (móvil) + backend (app_error).
  static Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String reason = 'unspecified',
    bool fatal = false,
  }) async {
    try {
      if (!kIsWeb) {
        await FirebaseCrashlytics.instance.recordError(
          error,
          stackTrace,
          reason: reason,
          fatal: fatal,
        );
      }
    } catch (_) {}

    _reportErrorToBackend(error.toString(), stackTrace?.toString(),
        fatal: fatal, code: error.runtimeType.toString());
  }

  static void _reportErrorToBackend(
    String message,
    String? stack, {
    bool fatal = false,
    String? code,
  }) {
    try {
      final dio = Dio(BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      dio.options.headers['Content-Type'] = 'application/json';
      final token = authToken;
      if (token != null && token.isNotEmpty) {
        dio.options.headers['Authorization'] = 'Bearer $token';
        dio
            .post('/registrar_evento.php', data: {
              'event_name': 'app_error',
              'params': {
                'code': code ?? 'Error',
                'message': message.length > 500 ? message.substring(0, 500) : message,
                if (stack != null) 'stack': stack.length > 1500 ? stack.substring(0, 1500) : stack,
              },
              'app_version': appVersion,
              'platform': kIsWeb ? 'web' : 'android',
            })
            .catchError((_) {});
      }
    } catch (_) {}
  }
}

/// Observer que registra screen_view (Firebase + espejo backend)
/// para navegación con GoRouter.
class _AnalyticsObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _track(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _track(newRoute);
  }

  void _track(Route<dynamic> route) {
    final name = route.settings.name;
    if (name == null || name.isEmpty) return;
    // Fire-and-forget: nunca bloquear navegación
    AnalyticsService.logScreenView(name);
  }
}