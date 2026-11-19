// lib/services/fcm_service.dart
// Saber+ — Sincronización del token FCM con el backend
//
// Auto-contenido: crea su propio Dio y toma el JWT de un callback.
// No depende de DioClient ni de ApiService internals.
//
// v1.6.0 WEB: en web getToken() requiere una VAPID key. Si
// Env.firebaseVapidKey está configurada se usa; si no, el push web
// queda deshabilitado (la app funciona sin notificaciones en web).

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../config/env.dart';
import '../core/utils/app_logger.dart';

class FcmService {
  static String? _baseUrl;
  static Future<String?> Function()? _jwtProvider;
  static bool _refreshListenerRegistered = false;

  /// Configura el servicio. Llamar UNA sola vez en main().
  ///
  /// - [baseUrl]: URL base del backend, p.ej. `ApiService.baseUrl`.
  /// - [jwtProvider]: callback que retorna el JWT actual (o null si no hay
  ///   sesión). Normalmente `() async => authService.token`.
  static void configure({
    required String baseUrl,
    required Future<String?> Function() jwtProvider,
  }) {
    _baseUrl = baseUrl;
    _jwtProvider = jwtProvider;
    AppLogger.d('FcmService: configurado (baseUrl=$baseUrl)');
  }

  /// Envía el token FCM actual al backend.
  ///
  /// - Si no hay JWT (usuario no logueado), el endpoint responde 401 y
  ///   se ignora silenciosamente. Se reintentará tras el login.
  /// - Si no hay token FCM todavía, no hace nada.
  static Future<void> syncTokenWithBackend() async {
    final baseUrl = _baseUrl;
    final jwtProvider = _jwtProvider;
    if (baseUrl == null || jwtProvider == null) {
      AppLogger.w('FcmService: no configurado, saltando sync');
      return;
    }

    try {
      // ✅ v1.6.0 WEB: en web, getToken() necesita vapidKey. Sin ella,
      // se omite la sincronización (push deshabilitado en web).
      final String? token;
      if (kIsWeb) {
        final vapid = Env.firebaseVapidKey;
        if (vapid.isEmpty) {
          AppLogger.d('FcmService: push web deshabilitado (sin VAPID key)');
          return;
        }
        token = await FirebaseMessaging.instance.getToken(vapidKey: vapid);
      } else {
        token = await FirebaseMessaging.instance.getToken();
      }
      if (token == null || token.isEmpty) {
        AppLogger.w('FcmService: no hay token FCM disponible aún');
        return;
      }

      final jwt = await jwtProvider();
      if (jwt == null || jwt.isEmpty) {
        AppLogger.d('FcmService: sync omitido (sin JWT aún)');
        return;
      }

      final dio = Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));
      dio.options.headers['Authorization'] = 'Bearer $jwt';
      dio.options.headers['Content-Type'] = 'application/json';

      final res = await dio.post(
        '/save_fcm_token.php',
        data: {'fcm_token': token},
      );

      AppLogger.i(
        'FcmService: token sincronizado (${token.substring(0, 20)}...) '
        '→ ${res.statusCode}',
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401) {
        AppLogger.d('FcmService: sync omitido (JWT inválido/expirado)');
      } else {
        AppLogger.e('FcmService: error sincronizando token', e);
      }
    } catch (e) {
      AppLogger.e('FcmService: error inesperado sincronizando token', e);
    }
  }

  /// Registra un listener para reenviar el token cuando FCM lo rote.
  /// Llamar UNA sola vez al arrancar la app.
  static void registerTokenRefreshListener() {
    if (_refreshListenerRegistered) return;
    _refreshListenerRegistered = true;

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      AppLogger.i('FcmService: token rotado (${newToken.substring(0, 20)}...)');
      final baseUrl = _baseUrl;
      final jwtProvider = _jwtProvider;
      if (baseUrl == null || jwtProvider == null) return;

      try {
        final jwt = await jwtProvider();
        if (jwt == null || jwt.isEmpty) return;

        final dio = Dio(BaseOptions(baseUrl: baseUrl));
        dio.options.headers['Authorization'] = 'Bearer $jwt';
        dio.options.headers['Content-Type'] = 'application/json';

        await dio.post('/save_fcm_token.php', data: {'fcm_token': newToken});
        AppLogger.i('FcmService: token rotado sincronizado');
      } catch (e) {
        AppLogger.e('FcmService: error reenviando token rotado', e);
      }
    });
  }
}