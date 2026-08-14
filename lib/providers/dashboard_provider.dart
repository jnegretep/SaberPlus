// lib/providers/dashboard_provider.dart
// Saber+ — Dashboard Provider v2.0
// Cambios vs v1.0:
//   - ✅ Cache inteligente con TTL de 5 min (CacheService)
//   - ✅ Carga optimista: muestra datos cacheados al instante, refresca en background
//   - ✅ Pull-to-refresh real: forceRefresh ignora el caché
//   - ✅ Estado diferenciado: isLoading (carga inicial) vs isRefreshing (background)
//   - ✅ Manejo de errores mejorado: si falla el refresh pero hay caché, no muestra error
//   - ✅ Snapshot completo: guarda todo el dashboard en una sola entrada de caché

import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/summary_stats.dart';
import '../services/api_service.dart';
import '../core/services/cache_service.dart';
import '../core/utils/app_logger.dart';

class DashboardProvider extends ChangeNotifier {
  final ApiService api;
  DashboardProvider(this.api);

  // ── Estado ──
  /// true cuando NO hay datos previos (carga inicial completa)
  bool isLoading = false;

  /// true cuando hay datos mostrados pero se está refrescando en background
  bool isRefreshing = false;

  /// Mensaje de error (null si todo OK). Si hay caché, no se muestra.
  String? error;

  /// Edad del caché actual en segundos (para mostrar "actualizado hace X min")
  int? cacheAgeSeconds;

  // ── Datos ──
  List<Course> simulacros = [];
  List<Course> cursos = [];
  List<Course> retos = [];
  SummaryStats? summary;

  /// TTL del caché del dashboard
  static const Duration _cacheTtl = Duration(minutes: 5);

  /// Carga los datos del dashboard.
  ///
  /// Estrategia:
  /// 1. Si hay caché válido → mostrarlo al instante (isLoading=false)
  ///    y refrescar en background (isRefreshing=true)
  /// 2. Si no hay caché → mostrar loading (isLoading=true) y cargar
  /// 3. Si el refresh falla pero hay caché → mantener caché, no mostrar error
  /// 4. Si [forceRefresh]=true → ignorar caché y cargar fresco siempre
  Future<void> loadDashboardData({bool forceRefresh = false}) async {
    // Si ya estamos cargando, no hacer nada
    if (isLoading || isRefreshing) {
      AppLogger.d('DashboardProvider: ya cargando, skip');
      return;
    }

    // Intentar cargar desde caché primero (si no es forceRefresh)
    if (!forceRefresh) {
      final hasCache = await _loadFromCache();
      if (hasCache) {
        // Caché válido → refrescar en background silenciosamente
        AppLogger.i('DashboardProvider: caché válido, refrescando en background');
        _refreshInBackground();
        return;
      }
    }

    // No hay caché (o forceRefresh) → cargar con loading visible
    await _loadFromNetwork(showLoading: true);
  }

  /// Carga los datos desde el caché. Retorna true si había caché válido.
  Future<bool> _loadFromCache() async {
    try {
      final cached = await CacheService.get(CacheKeys.dashboardFullSnapshot);
      if (cached == null) {
        AppLogger.d('DashboardProvider: no hay caché');
        return false;
      }

      final snapshot = cached as Map<String, dynamic>;

      // Deserializar datos
      final simulacrosRaw = (snapshot['simulacros'] as List<dynamic>)
          .map((e) => Course.fromJson(e as Map<String, dynamic>))
          .toList();
      final cursosRaw = (snapshot['cursos'] as List<dynamic>)
          .map((e) => Course.fromJson(e as Map<String, dynamic>))
          .toList();
      final retosRaw = (snapshot['retos'] as List<dynamic>)
          .map((e) => Course.fromJson(e as Map<String, dynamic>))
          .toList();

      SummaryStats? summaryStats;
      if (snapshot['summary'] != null) {
        summaryStats =
            SummaryStats.fromJson(snapshot['summary'] as Map<String, dynamic>);
      }

      // Aplicar al estado
      simulacros = simulacrosRaw;
      cursos = cursosRaw;
      retos = retosRaw;
      summary = summaryStats;
      error = null;
      cacheAgeSeconds = await CacheService.ageOf(CacheKeys.dashboardFullSnapshot);

      notifyListeners();
      AppLogger.i('DashboardProvider: caché cargado '
          '(${simulacros.length} sim, ${cursos.length} cursos, ${retos.length} retos)');
      return true;
    } catch (e) {
      AppLogger.e('DashboardProvider: error leyendo caché', e);
      return false;
    }
  }

  /// Refresca los datos en background sin mostrar loading.
  /// Solo actualiza la UI si los datos cambiaron o si hay error.
  Future<void> _refreshInBackground() async {
    isRefreshing = true;
    notifyListeners();

    try {
      await _loadFromNetwork(showLoading: false);
    } finally {
      isRefreshing = false;
      notifyListeners();
    }
  }

  /// Carga los datos desde la red.
  /// Si [showLoading]=true, muestra el spinner de carga completo.
  Future<void> _loadFromNetwork({required bool showLoading}) async {
    if (showLoading) {
      isLoading = true;
      error = null;
      notifyListeners();
    }

    try {
      // ✅ Peticiones paralelas para máxima velocidad
      final results = await Future.wait([
        api.fetchCourses(category: 'simulacros'),
        api.fetchCourses(category: 'courses'),
        api.fetchCourses(category: 'retos'),
        api.fetchSummaryStats(),
      ]);

      // 🔹 SIMULACROS
      var simulacrosRaw = results[0] as List<Course>;

      // Marcar intentos
      final attempts = await api.fetchSimulacroAttempts(api.auth.userId!);
      for (var c in simulacrosRaw) {
        if (attempts.contains(c.id)) {
          c.attempted = true;
        }
      }

      // Ordenar simulacros
      simulacrosRaw = _orderedSimulacros(simulacrosRaw);

      // Tomar solo los primeros 5
      simulacros = simulacrosRaw.take(5).toList();

      // 🔹 CURSOS / RETOS
      cursos = results[1] as List<Course>;
      retos = results[2] as List<Course>;

      // 🔹 SUMMARY
      summary = results[3] as SummaryStats;

      // ✅ Guardar en caché (snapshot completo)
      await _saveToCache();

      error = null;
      cacheAgeSeconds = 0; // recién actualizado

      AppLogger.i('DashboardProvider: datos cargados desde red y cacheados');
    } catch (e) {
      AppLogger.e('DashboardProvider: error cargando desde red', e);

      // Si ya tenemos datos (de caché o carga previa), no mostrar error
      // Solo mostrar error si es la carga inicial y no hay datos previos
      if (simulacros.isEmpty && cursos.isEmpty && retos.isEmpty) {
        error = _friendlyErrorMessage(e.toString());
      } else {
        // Tenemos datos previos → mantenerlos, solo log del error
        AppLogger.w('DashboardProvider: refresh falló pero se mantienen datos previos');
      }
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Guarda el snapshot completo del dashboard en caché.
  Future<void> _saveToCache() async {
    try {
      final snapshot = {
        'simulacros': simulacros.map((c) => c.toJson()).toList(),
        'cursos': cursos.map((c) => c.toJson()).toList(),
        'retos': retos.map((c) => c.toJson()).toList(),
        'summary': summary?.toJson(),
        'savedAt': DateTime.now().toIso8601String(),
      };

      await CacheService.set(
        CacheKeys.dashboardFullSnapshot,
        snapshot,
        ttl: _cacheTtl,
      );
    } catch (e) {
      AppLogger.e('DashboardProvider: error guardando caché', e);
    }
  }

  /// Convierte mensajes de error técnicos a mensajes amigables para el usuario.
  String _friendlyErrorMessage(String error) {
    if (error.contains('SocketException') ||
        error.contains('HandshakeException') ||
        error.contains('Failed host lookup')) {
      return 'Sin conexión a internet. Verifica tu red e inténtalo de nuevo.';
    }
    if (error.contains('TimeoutException') || error.contains('timed out')) {
      return 'El servidor tardó demasiado en responder. Inténtalo de nuevo.';
    }
    if (error.contains('401') || error.contains('Unauthorized')) {
      return 'Tu sesión ha expirado. Cierra sesión y vuelve a ingresar.';
    }
    if (error.contains('500') || error.contains('502') || error.contains('503')) {
      return 'El servidor tiene problemas temporales. Inténtalo en unos minutos.';
    }
    return 'No se pudo cargar la información. Inténtalo de nuevo.';
  }

  /// Orden idéntico a CourseListScreen (NO TOCAR)
  List<Course> _orderedSimulacros(List<Course> courses) {
    final simulacros =
        courses.where((c) => c.name.toLowerCase().contains("simulacro")).toList();
    final otros =
        courses.where((c) => !c.name.toLowerCase().contains("simulacro")).toList();

    simulacros.sort((a, b) {
      if (a.name.toLowerCase().contains("diagnostico")) return -1;
      if (b.name.toLowerCase().contains("diagnostico")) return 1;

      final numA =
          int.tryParse(a.name.replaceAll(RegExp(r'[^0-9]'), "")) ?? 9999;
      final numB =
          int.tryParse(b.name.replaceAll(RegExp(r'[^0-9]'), "")) ?? 9999;
      return numA.compareTo(numB);
    });

    return [...simulacros, ...otros];
  }

  /// Limpia el caché del dashboard (útil al cerrar sesión).
  Future<void> clearCache() async {
    await CacheService.remove(CacheKeys.dashboardFullSnapshot);
    simulacros = [];
    cursos = [];
    retos = [];
    summary = null;
    error = null;
    cacheAgeSeconds = null;
    notifyListeners();
  }
}
