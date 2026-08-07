import 'package:flutter/material.dart';
import '../models/course.dart';
import '../models/summary_stats.dart';
import '../services/api_service.dart';

class DashboardProvider extends ChangeNotifier {
  final ApiService api;

  DashboardProvider(this.api);

  bool isLoading = false;
  String? error;

  List<Course> simulacros = [];
  List<Course> cursos = [];
  List<Course> retos = [];

  /// 🔹 NUEVO: resumen estadístico
  SummaryStats? summary;

  Future<void> loadDashboardData() async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        api.fetchCourses(category: 'simulacros'),
        api.fetchCourses(category: 'courses'),
        api.fetchCourses(category: 'retos'),
        api.fetchSummaryStats(), // 👈 NUEVO
      ]);

      // 🔹 SIMULACROS
      var simulacrosRaw = results[0] as List<Course>;

      // 1️⃣ Marcar intentos (idéntico a CourseListScreen)
      final attempts =
          await api.fetchSimulacroAttempts(api.auth.userId!);
      for (var c in simulacrosRaw) {
        if (attempts.contains(c.id)) {
          c.attempted = true;
        }
      }

      // 2️⃣ Ordenar simulacros (NO TOCAR)
      simulacrosRaw = _orderedSimulacros(simulacrosRaw);

      // 3️⃣ Tomar solo los primeros 5
      simulacros = simulacrosRaw.take(5).toList();

      // 🔹 CURSOS / RETOS (NO TOCAR)
      cursos = results[1] as List<Course>;
      retos = results[2] as List<Course>;

      // 🔹 SUMMARY (nuevo)
      final SummaryStats summaryStats = results[3] as SummaryStats;
summary = summaryStats;

    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// 🔹 Orden idéntico a CourseListScreen (NO TOCAR)
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
}
