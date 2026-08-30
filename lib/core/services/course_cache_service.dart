// lib/core/services/course_cache_service.dart
// Saber+ — Servicio de caché offline para cursos y contenido
//
// Estrategia:
// - Lista de cursos por categoría: TTL 30 min (cambia poco)
// - Contenido de un curso (secciones/módulos): TTL 24 horas (cambia casi nunca)
// - Modo offline: si no hay internet, usar caché aunque esté expirado
//
// Uso típico:
// ```dart
// // Cargar cursos (con caché)
// final courses = await CourseCacheService.fetchCoursesWithCache(
//   api: api,
//   category: 'simulacros',
// );
//
// // Cargar contenido de un curso (con caché)
// final sections = await CourseCacheService.fetchCourseContentsWithCache(
//   api: api,
//   courseId: 5,
// );
// ```

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';
import '../../services/api_service.dart';
import '../../models/course.dart';
import '../../models/course_section.dart';
import 'cache_service.dart';

class CourseCacheService {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    AppLogger.d('CourseCacheService inicializado');
  }

  static SharedPreferences get _instance {
    if (_prefs == null) {
      throw StateError('CourseCacheService no inicializado. Llama init() primero.');
    }
    return _prefs!;
  }

  /// ── Cursos por categoría ──

  /// Carga cursos con estrategia de caché.
  ///
  /// 1. Si hay caché válido (TTL 30 min) → devolver caché
  /// 2. Si no hay caché → cargar desde API y guardar
  /// 3. Si hay caché expirado y no hay internet → devolver caché expirado
  static Future<List<Course>> fetchCoursesWithCache({
    required ApiService api,
    required String category,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${CacheKeys.coursesList}_$category';
    final ttl = const Duration(minutes: 30);

    // 1. Intentar caché primero (si no es forceRefresh)
    if (!forceRefresh) {
      final cached = await _readCache<List<dynamic>>(cacheKey);
      if (cached != null) {
        try {
          final courses = cached
              .map((e) => Course.fromJson(e as Map<String, dynamic>))
              .toList();
          AppLogger.d('CourseCache: HIT para $category (${courses.length} cursos)');
          return courses;
        } catch (e) {
          AppLogger.e('CourseCache: error parseando caché de cursos', e);
        }
      }
    }

    // 2. Cargar desde API
    try {
      final courses = await api.fetchCourses(category: category);
      AppLogger.d('CourseCache: cargados ${courses.length} cursos desde API para $category');

      // Guardar en caché
      await _writeCache(
        cacheKey,
        courses.map((c) => c.toJson()).toList(),
        ttl,
      );

      return courses;
    } catch (e) {
      AppLogger.e('CourseCache: error cargando cursos desde API para $category', e);

      // 3. Fallback: intentar caché expirado (modo offline)
      final stale = await _readCacheStale<List<dynamic>>(cacheKey);
      if (stale != null) {
        try {
          final courses = stale
              .map((e) => Course.fromJson(e as Map<String, dynamic>))
              .toList();
          AppLogger.w('CourseCache: usando caché EXPIRADO para $category '
              '(sin conexión, ${courses.length} cursos)');
          return courses;
        } catch (_) {}
      }

      // No hay caché ni internet → propagar error
      rethrow;
    }
  }

  /// ── Contenido de un curso (secciones/módulos) ──

  /// Carga el contenido de un curso con caché de 24 horas.
  ///
  /// El contenido de los cursos cambia muy raramente, así que TTL largo.
  /// En modo offline, se devuelve el caché aunque esté expirado.
  static Future<List<CourseSection>> fetchCourseContentsWithCache({
    required ApiService api,
    required int courseId,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'course_contents_$courseId';
    final ttl = const Duration(hours: 24);

    // 1. Intentar caché primero
    if (!forceRefresh) {
      final cached = await _readCache<List<dynamic>>(cacheKey);
      if (cached != null) {
        try {
          final sections = cached
              .map((e) => CourseSection.fromJson(e as Map<String, dynamic>))
              .toList();
          AppLogger.d('CourseCache: HIT para contenido de curso $courseId '
              '(${sections.length} secciones)');
          return sections;
        } catch (e) {
          AppLogger.e('CourseCache: error parseando caché de contenido', e);
        }
      }
    }

    // 2. Cargar desde API
    try {
      final sections = await api.fetchCourseContents(courseId);
      AppLogger.d('CourseCache: cargadas ${sections.length} secciones desde API '
          'para curso $courseId');

      // Guardar en caché
      await _writeCache(
        cacheKey,
        sections.map((s) => s.toJson()).toList(),
        ttl,
      );

      return sections;
    } catch (e) {
      AppLogger.e('CourseCache: error cargando contenido de curso $courseId', e);

      // 3. Fallback: caché expirado
      final stale = await _readCacheStale<List<dynamic>>(cacheKey);
      if (stale != null) {
        try {
          final sections = stale
              .map((e) => CourseSection.fromJson(e as Map<String, dynamic>))
              .toList();
          AppLogger.w('CourseCache: usando caché EXPIRADO para contenido '
              'curso $courseId (sin conexión)');
          return sections;
        } catch (_) {}
      }

      rethrow;
    }
  }

  /// ── Helpers de caché ──

  static Future<void> _writeCache(
    String key,
    dynamic data,
    Duration ttl,
  ) async {
    try {
      final entry = {
        'data': data,
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
        'ttl': ttl.inMilliseconds,
      };
      await _instance.setString('coursecache_$key', jsonEncode(entry));
    } catch (e) {
      AppLogger.e('CourseCache: error escribiendo caché $key', e);
    }
  }

  static Future<T?> _readCache<T>(String key) async {
    try {
      final raw = _instance.getString('coursecache_$key');
      if (raw == null) return null;

      final entry = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = entry['cachedAt'] as int;
      final ttl = entry['ttl'] as int;
      final age = DateTime.now().millisecondsSinceEpoch - cachedAt;

      if (age > ttl) {
        // Expirado
        return null;
      }

      return entry['data'] as T?;
    } catch (e) {
      AppLogger.e('CourseCache: error leyendo caché $key', e);
      return null;
    }
  }

  /// Lee el caché sin importar si expiró (para modo offline).
  static Future<T?> _readCacheStale<T>(String key) async {
    try {
      final raw = _instance.getString('coursecache_$key');
      if (raw == null) return null;

      final entry = jsonDecode(raw) as Map<String, dynamic>;
      return entry['data'] as T?;
    } catch (_) {
      return null;
    }
  }

  /// Verifica si un curso tiene contenido cacheado (aunque esté expirado).
  static Future<bool> isCourseCached(int courseId) async {
    final raw = _instance.getString('course_contents_$courseId');
    return raw != null;
  }

  /// Edad del caché de un curso en horas (null si no existe).
  static Future<int?> courseCacheAgeHours(int courseId) async {
    try {
      final raw = _instance.getString('coursecache_course_contents_$courseId');
      if (raw == null) return null;
      final entry = jsonDecode(raw) as Map<String, dynamic>;
      final cachedAt = entry['cachedAt'] as int;
      final ageMs = DateTime.now().millisecondsSinceEpoch - cachedAt;
      return (ageMs / 3600000).round();
    } catch (_) {
      return null;
    }
  }

  /// Elimina el caché de un curso específico.
  static Future<void> clearCourseCache(int courseId) async {
    await _instance.remove('coursecache_course_contents_$courseId');
    AppLogger.d('CourseCache: eliminado caché de curso $courseId');
  }

  /// Elimina todo el caché de cursos.
  static Future<void> clearAll() async {
    final keys = _instance.getKeys().where((k) => k.startsWith('coursecache_'));
    for (final key in keys) {
      await _instance.remove(key);
    }
    AppLogger.i('CourseCache: limpiado todo (${keys.length} entradas)');
  }
}
