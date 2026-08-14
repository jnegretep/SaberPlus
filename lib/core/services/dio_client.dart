// lib/core/services/dio_client.dart
// Saber+ — Dio HTTP Client con interceptores v1.0
//
// Cliente HTTP centralizado con:
// - Inyección automática del token JWT (AuthInterceptor)
// - Logging estructurado de peticiones (LoggingInterceptor)
// - Reintentos automáticos en errores de red (RetryInterceptor)
// - Refresco automático del token cuando expira (RefreshTokenInterceptor)
// - Timeouts configurados (connect: 15s, receive: 30s)
// - Manejo de errores centralizado
//
// Uso:
// ```dart
// final response = await DioClient.instance.post(
//   '/login.php',
//   data: {'email': email, 'password': password},
// );
// ```

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import '../utils/app_logger.dart';
import '../../config/env.dart';

/// Cliente Dio singleton para toda la app.
///
/// Configurado con:
/// - Base URL desde Env
/// - Timeouts razonables
/// - Interceptores de auth, logging, retry y refresh
class DioClient {
  static Dio? _instance;

  /// Token JWT actual — seteado por AuthService cuando el usuario inicia sesión.
  /// El AuthInterceptor lo inyecta automáticamente en cada petición.
  static String? authToken;

  /// Refresh token — usado por el RefreshTokenInterceptor para renovar el JWT.
  static String? refreshToken;

  /// Callback que se ejecuta cuando el refresh token también expira.
  /// El AuthService lo configura para forzar logout.
  static Future<void> Function()? onSessionExpired;

  /// Obtiene la instancia singleton de Dio, configurada con todos los
  /// interceptores. La primera llamada la crea; las siguientes la reutilizan.
  static Dio get instance {
    if (_instance != null) return _instance!;

    final dio = Dio(BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));

    // Orden de interceptores importa:
    // 1. Auth (añade token) → 2. Retry (reintenta si falla) → 3. Refresh (renueva token)
    // 4. Logging (al final para ver todo)
    dio.interceptors.addAll([
      _AuthInterceptor(),
      _RetryInterceptor(dio),
      _RefreshTokenInterceptor(dio),
      if (!kReleaseMode) _LoggingInterceptor(),
    ]);

    _instance = dio;
    AppLogger.d('DioClient inicializado con baseUrl=${Env.apiBaseUrl}');
    return dio;
  }

  /// Métodos de conveniencia para no exponer Dio directamente.
  /// Esto permite cambiar la implementación interna sin tocar el código caller.

  static Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return await instance.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  static Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return await instance.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  static Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return await instance.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  static Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return await instance.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// Limpia la instancia (útil para tests o logout completo).
  static void reset() {
    authToken = null;
    refreshToken = null;
    _instance = null;
  }
}

// ─────────────────────────────────────────────────────────────────
// INTERCEPTOR 1: AUTENTICACIÓN
// ─────────────────────────────────────────────────────────────────
/// Inyecta el token JWT en el header `Authorization` de cada petición.
/// Si no hay token, la petición se envía sin el header (para endpoints públicos).
class _AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (DioClient.authToken != null && DioClient.authToken!.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer ${DioClient.authToken}';
    }
    handler.next(options);
  }
}

// ─────────────────────────────────────────────────────────────────
// INTERCEPTOR 2: REINTENTOS AUTOMÁTICOS
// ─────────────────────────────────────────────────────────────────
/// Reintenta automáticamente peticiones que fallan por errores de red
/// (timeout, conexión rechazada, errores 5xx del servidor).
///
/// NO reintenta en:
/// - Errores 4xx (cliente) — son errores de la app, no de red
/// - Errores 401 — los maneja el RefreshTokenInterceptor
class _RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;

  _RetryInterceptor(this.dio, {this.maxRetries = 2});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra['retryAttempt'] as int?) ?? 0;

    // ¿Es reintentable?
    final isRetryable = _isRetryableError(err) && attempt < maxRetries;

    if (!isRetryable) {
      handler.next(err);
      return;
    }

    AppLogger.w('Retry ${attempt + 1}/$maxRetries para ${err.requestOptions.path} '
        '(error: ${err.type})');

    // Backoff exponencial: 500ms, 1000ms, 2000ms...
    final delay = Duration(milliseconds: 500 * (1 << attempt));
    await Future.delayed(delay);

    // Incrementar contador y reintentar
    err.requestOptions.extra['retryAttempt'] = attempt + 1;
    try {
      final response = await dio.fetch(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  bool _isRetryableError(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.badResponse:
        final status = err.response?.statusCode ?? 0;
        // Reintentar solo en errores 5xx del servidor
        return status >= 500 && status < 600;
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
        return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// INTERCEPTOR 3: REFRESH TOKEN AUTOMÁTICO
// ─────────────────────────────────────────────────────────────────
/// Cuando el backend responde 401 (token expirado), intenta refrescar
/// el token automáticamente y reintentar la petición original.
///
/// Si el refresh también falla, dispara `onSessionExpired` para forzar logout.
class _RefreshTokenInterceptor extends Interceptor {
  final Dio dio;
  static bool _isRefreshing = false;
  static final List<_PendingRequest> _pendingRequests = [];

  _RefreshTokenInterceptor(this.dio);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;

    // Solo actuar en 401
    if (status != 401) {
      handler.next(err);
      return;
    }

    // Si no hay refresh token, no podemos refrescar
    if (DioClient.refreshToken == null || DioClient.refreshToken!.isEmpty) {
      AppLogger.w('RefreshTokenInterceptor: no hay refresh token, sesión expirada');
      await _forceLogout();
      handler.next(err);
      return;
    }

    // Si ya estamos refrescando, encolar la petición con su handler
    if (_isRefreshing) {
      AppLogger.d('RefreshTokenInterceptor: refresh en progreso, encolando petición');
      _pendingRequests.add(_PendingRequest(err.requestOptions, handler));
      return;
    }

    // Intentar refresh
    _isRefreshing = true;
    AppLogger.i('RefreshTokenInterceptor: token expirado, intentando refresh...');

    try {
      final refreshed = await _tryRefresh();

      if (refreshed) {
        AppLogger.i('RefreshTokenInterceptor: refresh exitoso, reintentando petición original');

        // Reintentar la petición original con el nuevo token
        err.requestOptions.headers['Authorization'] = 'Bearer ${DioClient.authToken}';
        try {
          final response = await dio.fetch(err.requestOptions);
          handler.resolve(response);
        } catch (e) {
          handler.next(e is DioException ? e : DioException(requestOptions: err.requestOptions, error: e));
        }

        // Procesar peticiones pendientes
        await _processPendingRequests();
      } else {
        AppLogger.w('RefreshTokenInterceptor: refresh falló, forzando logout');
        await _forceLogout();
        handler.next(err);
        // Rechazar también las pendientes
        _rejectPending(err);
      }
    } catch (e) {
      AppLogger.e('RefreshTokenInterceptor: error durante refresh', e);
      await _forceLogout();
      handler.next(err);
      _rejectPending(err);
    } finally {
      _isRefreshing = false;
    }
  }

  /// Llama al endpoint /refresh.php con el refresh token almacenado.
  /// Retorna true si el refresh fue exitoso.
  Future<bool> _tryRefresh() async {
    try {
      // Usar un Dio separado SIN interceptores para evitar recursión
      final rawDio = Dio(BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      final response = await rawDio.post(
        '/refresh.php',
        data: {'refresh_token': DioClient.refreshToken},
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );

      if (response.statusCode != 200) return false;

      final data = response.data;
      if (data is! Map || data['status'] != 'ok') return false;

      // Actualizar tokens
      DioClient.authToken = data['token'] as String?;
      if (data['refresh_token'] != null) {
        DioClient.refreshToken = data['refresh_token'] as String?;
      }

      AppLogger.i('RefreshTokenInterceptor: nuevos tokens obtenidos');
      return true;
    } catch (e) {
      AppLogger.e('RefreshTokenInterceptor: error en _tryRefresh', e);
      return false;
    }
  }

  /// Reintenta todas las peticiones que quedaron encoladas durante el refresh.
  Future<void> _processPendingRequests() async {
    final pending = List<_PendingRequest>.from(_pendingRequests);
    _pendingRequests.clear();

    for (final req in pending) {
      try {
        req.options.headers['Authorization'] = 'Bearer ${DioClient.authToken}';
        final response = await dio.fetch(req.options);
        req.handler.resolve(response);
        AppLogger.d('RefreshTokenInterceptor: petición pendiente completada');
      } on DioException catch (e) {
        req.handler.next(e);
      } catch (e) {
        req.handler.next(DioException(
          requestOptions: req.options,
          error: e,
        ));
      }
    }
  }

  /// Rechaza todas las peticiones pendientes con el error original.
  void _rejectPending(DioException err) {
    for (final req in _pendingRequests) {
      req.handler.next(err);
    }
    _pendingRequests.clear();
  }

  /// Fuerza el logout cuando ni el token ni el refresh funcionan.
  Future<void> _forceLogout() async {
    _pendingRequests.clear();
    if (DioClient.onSessionExpired != null) {
      await DioClient.onSessionExpired!();
    }
  }
}

/// Wrapper para encolar peticiones pendientes con sus handlers.
class _PendingRequest {
  final RequestOptions options;
  final ErrorInterceptorHandler handler;

  _PendingRequest(this.options, this.handler);
}

// ─────────────────────────────────────────────────────────────────
// INTERCEPTOR 4: LOGGING (solo en debug)
// ─────────────────────────────────────────────────────────────────
/// Registra cada petición y respuesta con timestamps y duración.
/// Solo se activa en modo debug (kReleaseMode = false).
class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['requestStartTime'] = DateTime.now().millisecondsSinceEpoch;
    AppLogger.d('→ ${options.method} ${options.path}'
        '${options.queryParameters.isNotEmpty ? '?${options.queryParameters}' : ''}'
        '${options.data != null ? '\n  body: ${_truncate(options.data.toString())}' : ''}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final startTime = response.requestOptions.extra['requestStartTime'] as int?;
    final duration = startTime != null
        ? DateTime.now().millisecondsSinceEpoch - startTime
        : null;

    AppLogger.api(
      response.requestOptions.method,
      response.requestOptions.path,
      statusCode: response.statusCode,
    );

    if (duration != null) {
      AppLogger.d('← ${response.statusCode} ${response.requestOptions.path} '
          '(${duration}ms)');
    }

    // Log del body solo si es chico (para no spamear logs con respuestas enormes)
    final bodyStr = response.data?.toString() ?? '';
    if (bodyStr.length < 500) {
      AppLogger.d('  body: $bodyStr');
    } else {
      AppLogger.d('  body: ${bodyStr.substring(0, 500)}... (${bodyStr.length} bytes)');
    }

    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    AppLogger.e('✗ ${err.requestOptions.method} ${err.requestOptions.path} '
        '(type: ${err.type}, status: ${err.response?.statusCode})',
        err);

    if (err.response?.data != null) {
      AppLogger.d('  error body: ${_truncate(err.response!.data.toString())}');
    }

    handler.next(err);
  }

  String _truncate(String s, [int max = 200]) {
    return s.length <= max ? s : '${s.substring(0, max)}... (${s.length} bytes)';
  }
}
