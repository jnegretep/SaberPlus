import '../config/env.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'auth_service.dart';
import '../core/utils/app_logger.dart';

class TeacherService {
  final String baseUrl = Env.apiBaseUrl; // ✅ Variable real, no string literal
  final AuthService authService;

  TeacherService({required this.authService});

  Future<Map<String, dynamic>?> _getTeacherInfo() async {
    final user = authService.user;
    if (user != null && user['tipo_usuario'] == 'profesor') {
      final gradosDisponibles = user['grados_disponibles'] as List<dynamic>?;
      String gradoDefault = '';
      if (gradosDisponibles != null && gradosDisponibles.isNotEmpty) {
        gradoDefault = gradosDisponibles.first.toString();
      } else {
        gradoDefault = user['grado']?.toString() ?? '';
      }

      String anioDefault = '2025';

      return {
        'colegio': user['colegio'] ?? '',
        'grado': gradoDefault,
        'anio': anioDefault,
        'profesor_id': user['id_usuario']?.toString() ?? '',
      };
    }
    return null;
  }

  Future<String?> _getToken() async {
    return authService.token;
  }

  Future<List<Map<String, dynamic>>> fetchStudents(String? grado, String? anio) async {
    final teacherInfo = await _getTeacherInfo();
    if (teacherInfo == null || teacherInfo.isEmpty) {
      AppLogger.w('TeacherInfo vacío o nulo');
      return [];
    }

    final url = Uri.parse('$baseUrl/teacher_students.php');
    final token = await _getToken();

    AppLogger.d('Token: ${token != null && token.isNotEmpty ? "PRESENTE" : "AUSENTE"}');
    AppLogger.d('Colegio: ${teacherInfo['colegio']}, Grado: ${grado ?? teacherInfo['grado']}, Año: ${anio ?? teacherInfo['anio']}');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'colegio': teacherInfo['colegio'],
          'grado': grado ?? teacherInfo['grado'],
          'anio': anio ?? teacherInfo['anio'],
        }),
      );

      AppLogger.api('POST', '/teacher_students.php', statusCode: response.statusCode);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'ok') {
          final List<dynamic> rawStudents = data['students'];
          AppLogger.d('Estudiantes encontrados: ${rawStudents.length}');

          return rawStudents.map((student) {
            return {
              'id': student['id'] ?? 0,
              'nombre': student['nombre'] ?? '',
              'grado': student['grado'] ?? '',
              'avatar': student['avatar'],
              'puntaje_global': student['puntaje_global'] ?? 0,
              'ultimo_simulacro': student['ultimo_simulacro'] ?? '',
              'simulacros_realizados': student['simulacros_realizados'] ?? 0,
              'tendencia': student['tendencia'] ?? '+0%',
              'areas': {
                'lectura': student['areas']['lectura'] ?? 0,
                'matematicas': student['areas']['matematicas'] ?? 0,
                'sociales': student['areas']['sociales'] ?? 0,
                'naturales': student['areas']['naturales'] ?? 0,
                'ingles': student['areas']['ingles'] ?? 0,
              },
            };
          }).toList();
        } else {
          AppLogger.w('Status no es OK: ${data['message'] ?? "Sin mensaje"}');
        }
      }

      return [];
    } catch (e) {
      AppLogger.e('Error fetching students', e);
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchGroupStats(String colegio, String? grado, String? anio) async {
    final token = await _getToken();
    final url = Uri.parse('$baseUrl/teacher_stats.php');

    AppLogger.d('Cargando estadísticas: colegio=$colegio, grado=$grado, anio=$anio');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'colegio': colegio,
          'grado': grado,
          'anio': anio,
        }),
      );

      AppLogger.api('POST', '/teacher_stats.php', statusCode: response.statusCode);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'ok') {
          AppLogger.d('Estadísticas cargadas exitosamente');
          return Map<String, dynamic>.from(data['stats']);
        } else {
          AppLogger.w('Status no es OK: ${data['message'] ?? "Sin mensaje"}');
        }
      } else {
        AppLogger.e('Error HTTP: ${response.statusCode}');
      }

      return {};
    } catch (e) {
      AppLogger.e('Error fetching group stats', e);
      return {};
    }
  }

  Future<Map<String, dynamic>> fetchSimulacroDetail(int simulacroId, String colegio, String? grado, String? anio) async {
    final token = await _getToken();
    final url = Uri.parse('$baseUrl/teacher_simulacro_detail.php');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'simulacro_id': simulacroId,
          'colegio': colegio,
          'grado': grado,
          'anio': anio,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'ok') {
          return Map<String, dynamic>.from(data['detail']);
        }
      }

      return {};
    } catch (e) {
      AppLogger.e('Error fetching simulacro detail', e);
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> fetchAvailableSimulacros(
    String colegio,
    String? grado,
    String? anio,
  ) async {
    final token = await _getToken();
    final url = Uri.parse('$baseUrl/teacher_list_simulacros.php');

    AppLogger.d('Obteniendo simulacros para: $colegio, grado: $grado, año: $anio');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'colegio': colegio,
          'grado': grado,
          'anio': anio,
        }),
      );

      AppLogger.api('POST', '/teacher_list_simulacros.php', statusCode: response.statusCode);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'ok') {
          final List<dynamic> rawSimulacros = data['simulacros'] ?? [];
          AppLogger.d('Simulacros encontrados: ${rawSimulacros.length}');

          return rawSimulacros.map((sim) {
            double promedioGlobal;
            if (sim['promedio_global'] is int) {
              promedioGlobal = (sim['promedio_global'] as int).toDouble();
            } else if (sim['promedio_global'] is double) {
              promedioGlobal = sim['promedio_global'];
            } else {
              promedioGlobal = double.tryParse(sim['promedio_global']?.toString() ?? '0') ?? 0.0;
            }

            return {
              'id': sim['id'] ?? 0,
              'course_id': sim['course_id'] ?? 0,
              'nombre': sim['nombre'] ?? 'Simulacro',
              'descripcion': sim['descripcion'] ?? '',
              'fecha': sim['fecha'] ?? '2024-01-01',
              'total_estudiantes': sim['total_estudiantes'] ?? 0,
              'promedio_global': promedioGlobal,
              'total_intentos': sim['total_intentos'] ?? 0,
              'fecha_inicio': sim['fecha_inicio'],
              'fecha_fin': sim['fecha_fin'],
              'completado': sim['completado'] ?? false,
            };
          }).toList();
        } else {
          AppLogger.w('Error en respuesta: ${data['message']}');
        }
      } else {
        AppLogger.e('HTTP Error: ${response.statusCode}');
      }

      return [];
    } catch (e) {
      AppLogger.e('Error fetching simulacros', e);
      return [];
    }
  }

  Future<Map<String, dynamic>> generateReport({
    required int simulacroId,
    required String colegio,
    required int courseId,
    String? grado,
    String? anio,
  }) async {
    final token = await _getToken();
    final url = Uri.parse('$baseUrl/teacher_generate_report.php');

    AppLogger.d('Generando reporte para simulacro: $simulacroId, curso: $courseId');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'simulacro_id': simulacroId,
          'colegio': colegio,
          'grado': grado,
          'anio': anio ?? DateTime.now().year.toString(),
          'courseid': courseId,
        }),
      );

      AppLogger.api('POST', '/teacher_generate_report.php', statusCode: response.statusCode);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      return {
        'status': 'error',
        'message': 'Error HTTP ${response.statusCode}'
      };
    } catch (e) {
      AppLogger.e('Error generating report', e);
      return {'status': 'error', 'message': e.toString()};
    }
  }
}
