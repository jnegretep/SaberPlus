// lib/core/services/cache_service.dart
// Saber+ — Cache Service con TTL v1.0
// Servicio genérico de caché usando SharedPreferences.
// Almacena cualquier dato JSON con un timestamp de expiración.
//
// Estrategia:
// - Guarda datos como JSON string con metadata (timestamp, ttl)
// - Al leer, verifica si expiró (age > ttl)
// - Si expiró, retorna null (caller debe refrescar)
// - Si no expiró, retorna los datos cacheados

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

/// Entrada de caché con metadata
class _CacheEntry {
  final dynamic data;
  final int cachedAt; // epoch millis
  final int ttlMillis;

  _CacheEntry({
    required this.data,
    required this.cachedAt,
    required this.ttlMillis,
  });

  Map<String, dynamic> toJson() => {
        'data': data,
        'cachedAt': cachedAt,
        'ttl': ttlMillis,
      };

  factory _CacheEntry.fromJson(Map<String, dynamic> json) {
    return _CacheEntry(
      data: json['data'],
      cachedAt: json['cachedAt'] as int,
      ttlMillis: json['ttl'] as int,
    );
  }

  bool get isExpired {
    final age = DateTime.now().millisecondsSinceEpoch - cachedAt;
    return age > ttlMillis;
  }

  int get ageSeconds =>
      ((DateTime.now().millisecondsSinceEpoch - cachedAt) / 1000).round();
}

/// Servicio de caché genérico.
///
/// Uso típico:
/// ```dart
/// // Guardar
/// await CacheService.set('dashboard_simulacros', simulacrosJson,
///     ttl: Duration(minutes: 5));
///
/// // Leer (devuelve null si expiró o no existe)
/// final cached = await CacheService.get('dashboard_simulacros');
/// if (cached != null) {
///   // usar datos cacheados y refrescar en background
/// }
/// ```
class CacheService {
  static SharedPreferences? _prefs;

  /// Inicializar (llamar en main.dart antes de runApp)
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    AppLogger.d('CacheService inicializado');
  }

  static SharedPreferences get _instance {
    if (_prefs == null) {
      throw StateError('CacheService no inicializado. Llama CacheService.init() primero.');
    }
    return _prefs!;
  }

  /// Guarda datos en caché con un TTL.
  /// Los datos deben ser serializables a JSON (Map, List, primitives).
  static Future<void> set(
    String key,
    dynamic data, {
    Duration ttl = const Duration(minutes: 5),
  }) async {
    try {
      final entry = _CacheEntry(
        data: data,
        cachedAt: DateTime.now().millisecondsSinceEpoch,
        ttlMillis: ttl.inMilliseconds,
      );
      await _instance.setString('cache_$key', jsonEncode(entry.toJson()));
      AppLogger.d('Cache SET: $key (TTL=${ttl.inSeconds}s)');
    } catch (e) {
      AppLogger.e('CacheService.set($key) error', e);
    }
  }

  /// Lee datos del caché. Retorna null si:
  /// - No existe la key
  /// - Expiró (age > ttl)
  /// - Error al deserializar
  static Future<dynamic> get(String key) async {
    try {
      final raw = _instance.getString('cache_$key');
      if (raw == null) return null;

      final entry = _CacheEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (entry.isExpired) {
        AppLogger.d('Cache EXPIRED: $key (age=${entry.ageSeconds}s)');
        return null;
      }

      AppLogger.d('Cache HIT: $key (age=${entry.ageSeconds}s)');
      return entry.data;
    } catch (e) {
      AppLogger.e('CacheService.get($key) error', e);
      return null;
    }
  }

  /// Lee datos del caché sin importar si expiró.
  /// Útil para modo offline (mostrar datos viejos mejor que nada).
  static Future<dynamic> getStale(String key) async {
    try {
      final raw = _instance.getString('cache_$key');
      if (raw == null) return null;

      final entry = _CacheEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      AppLogger.d('Cache STALE READ: $key (age=${entry.ageSeconds}s, expired=${entry.isExpired})');
      return entry.data;
    } catch (e) {
      return null;
    }
  }

  /// Verifica si existe una key y no ha expirado.
  static Future<bool> isValid(String key) async {
    try {
      final raw = _instance.getString('cache_$key');
      if (raw == null) return false;
      final entry = _CacheEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return !entry.isExpired;
    } catch (_) {
      return false;
    }
  }

  /// Elimina una key del caché.
  static Future<void> remove(String key) async {
    try {
      await _instance.remove('cache_$key');
      AppLogger.d('Cache REMOVE: $key');
    } catch (e) {
      AppLogger.e('CacheService.remove($key) error', e);
    }
  }

  /// Limpia todo el caché (solo keys que empiezan con 'cache_').
  static Future<void> clearAll() async {
    try {
      final keys = _instance.getKeys().where((k) => k.startsWith('cache_'));
      for (final key in keys) {
        await _instance.remove(key);
      }
      AppLogger.i('Cache CLEARED (${keys.length} entries)');
    } catch (e) {
      AppLogger.e('CacheService.clearAll error', e);
    }
  }

  /// Edad del caché en segundos (null si no existe).
  static Future<int?> ageOf(String key) async {
    try {
      final raw = _instance.getString('cache_$key');
      if (raw == null) return null;
      final entry = _CacheEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return entry.ageSeconds;
    } catch (_) {
      return null;
    }
  }
}

/// Keys de caché centralizadas para evitar typos.
class CacheKeys {
  CacheKeys._();

  // Dashboard
  static const String dashboardSimulacros = 'dashboard_simulacros';
  static const String dashboardCursos = 'dashboard_cursos';
  static const String dashboardRetos = 'dashboard_retos';
  static const String dashboardSummary = 'dashboard_summary';
  static const String dashboardSimulacroAttempts = 'dashboard_simulacro_attempts';
  static const String dashboardFullSnapshot = 'dashboard_full_snapshot';

  // Cursos
  static const String coursesList = 'courses_list';

  // Estadísticas
  static const String summaryStats = 'summary_stats';
  static const String rankStats = 'rank_stats';

  // Perfil
  static const String userProfile = 'user_profile';
}
