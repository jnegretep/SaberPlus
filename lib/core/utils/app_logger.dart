// lib/core/utils/app_logger.dart
// Logger centralizado — reemplaza todos los print() del proyecto.
// En release, los logs se silencian automáticamente.

import 'package:logger/logger.dart';

class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    level: Level.debug,
  );

  /// Debug — solo visible en desarrollo
  static void d(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    assert(() {
      _logger.d(message, error: error, stackTrace: stackTrace);
      return true;
    }());
  }

  /// Info — eventos normales del app
  static void i(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Warning — algo inesperado pero no fatal
  static void w(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Error — algo que falló
  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// API Request logging
  static void api(String method, String url, {int? statusCode, int? durationMs}) {
    assert(() {
      final arrow = statusCode != null && statusCode >= 200 && statusCode < 300
          ? '>>>' : '!!!';
      final timing = durationMs != null ? ' (${durationMs}ms)' : '';
      _logger.d('$arrow $method $url [$statusCode]$timing');
      return true;
    }());
  }
}
