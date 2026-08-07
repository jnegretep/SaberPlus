import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:math';
import 'auth_service.dart';
import '../config/env.dart';
import '../models/course.dart';
import '../models/quiz.dart';
import '../models/attempt.dart';
import '../models/quiz_question.dart';
import '../models/attempt_summary.dart';
import '../models/course_section.dart';   
import '../models/course_module.dart';   
import '../models/module_content.dart';  
import '../models/plan.dart';
import '../models/summary_stats.dart';
import '../models/area_trend_point.dart';
import '../models/context_stats.dart';
import '../models/rank_stats.dart';
import '../parsers/quiz_question_parser.dart';
import '../utils/error_handler.dart';
import '../core/utils/app_logger.dart';
import '../models/ad_model.dart';



class ApiService {
  final AuthService auth;
  static final String _baseUrl = Env.apiBaseUrl;  // Configurado desde .env

  ApiService(this.auth);
DateTime? lastSyncTime;
DateTime? lastServerTime;
  // ✅ Getter público para usar en main.dart
  static String get baseUrl => _baseUrl;

  /// -------------------------
  /// Cursos
  /// -------------------------
  // api_service.dart (parche)
Future<List<Course>> fetchCourses({String category = 'courses'}) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/moodle/get_courses.php');
  _log('GET $uri (category=$category)');
  final resp = await http.get(uri, headers: _headers(token));
  _log('response (${resp.statusCode})', resp.body);

  final body = _safeDecode(resp);
  if (body is! Map || body['status'] != 'ok') {
    throw Exception('API error: ${body is Map ? (body['msg'] ?? 'Error al cargar cursos') : 'Respuesta inválida'}');
  }

  final items = body[category];
  if (items is! List) throw Exception('Formato inesperado en $category');

  return items
      .map((e) => Course.fromJson(e as Map<String, dynamic>))
      .toList();
}
Future<Map<String, dynamic>> deleteChallenge({required int challengeId}) async {
  final resp = await http.post(
    Uri.parse('$baseUrl/challenges/delete_challenge.php'),
    headers: {
  'Content-Type': 'application/json',
  'Authorization': 'Bearer ${auth.token}',
},

    body: jsonEncode({'challenge_id': challengeId}),
  );

  final data = jsonDecode(resp.body);
  if (data['status'] != 'ok') {
    throw data['msg'] ?? 'Error al eliminar reto';
  }

  return data;
}

/// ---------------------------------------------------------------------------
/// CONTENIDOS DE CURSO — versión totalmente blindada (CORRECCIÓN contents)
// ---------------------------------------------------------------------------
Future<List<CourseSection>> fetchCourseContents(int courseId) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/moodle/get_course_contents.php?courseid=$courseId');
  _log('GET $uri');

  final resp = await http.get(uri, headers: _headers(token));
  _log('response (${resp.statusCode})', resp.body);

  final body = _safeDecode(resp);
  if (body == null) throw Exception('Respuesta vacía del servidor');

  // NORMALIZACIÓN DEL ROOT
  Map<String, dynamic> normalized;
  if (body is Map<String, dynamic>) {
    normalized = body;
  } else if (body is List) {
    normalized = {'sections': body};
  } else if (body is String) {
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) normalized = d;
      else if (d is List) normalized = {'sections': d};
      else throw Exception('JSON inválido en cuerpo de respuesta');
    } catch (_) {
      throw Exception('JSON inválido en cuerpo de respuesta');
    }
  } else {
    final raw = body.toString().trim();
    try {
      final d = jsonDecode(raw);
      if (d is Map<String, dynamic>) normalized = d;
      else if (d is List) normalized = {'sections': d};
      else throw Exception('JSON inválido en respuesta');
    } catch (_) {
      throw Exception('Formato inesperado de la API');
    }
  }

  if (normalized.containsKey('status') && normalized['status'] != 'ok') {
    throw Exception(normalized['msg'] ?? 'Error API');
  }

  // EXTRACCIÓN DE SECCIONES (con respaldos)
  dynamic sectionsRaw = normalized['sections']
      ?? normalized['data']
      ?? normalized['courses']
      ?? normalized['modules'];

  if (sectionsRaw == null) return [];

  // string -> parse
  if (sectionsRaw is String) {
    try {
      sectionsRaw = jsonDecode(sectionsRaw);
    } catch (_) {
      return [];
    }
  }

  if (sectionsRaw is Map) sectionsRaw = sectionsRaw.values.toList();
  if (sectionsRaw is! List) throw Exception('El servidor devolvió formato inválido de secciones');

  final List<CourseSection> sections = [];

  for (var sRaw in sectionsRaw) {
    Map<String, dynamic>? sMap;

    if (sRaw is Map<String, dynamic>) sMap = sRaw;
    else if (sRaw is String) {
      try {
        final d = jsonDecode(sRaw);
        if (d is Map<String, dynamic>) sMap = d;
      } catch (_) {
        // no es JSON; saltamos
      }
    } else {
      try {
        final d = jsonDecode(jsonEncode(sRaw));
        if (d is Map<String, dynamic>) sMap = d;
      } catch (_) {}
    }

    if (sMap == null) continue;

    // PARSE MODULES
    dynamic rawModules = sMap['modules'] ?? sMap['mods'] ?? sMap['items'] ?? [];
    if (rawModules is String) {
      try {
        rawModules = jsonDecode(rawModules);
      } catch (_) {
        rawModules = [];
      }
    }
    if (rawModules is Map) rawModules = rawModules.values.toList();
    if (rawModules is! List) rawModules = [];

    final modules = <CourseModule>[];
    for (var mRaw in rawModules) {
      Map<String, dynamic> mMap = {};

      if (mRaw is Map<String, dynamic>) mMap = Map<String, dynamic>.from(mRaw);
      else if (mRaw is String) {
        try {
          final d = jsonDecode(mRaw);
          if (d is Map<String, dynamic>) mMap = d;
        } catch (_) {
          // si es string HTML, lo dejamos en un campo adecuado abajo
          mMap = {'name': mRaw};
        }
      } else {
        try {
          final d = jsonDecode(jsonEncode(mRaw));
          if (d is Map<String, dynamic>) mMap = d;
        } catch (_) {
          mMap = {};
        }
      }

      // --- CORRECCIÓN FUNDAMENTAL: normalizar cada elemento de contents a Map ---
      dynamic rawContents = mMap['contents'] ?? mMap['files'] ?? [];
      List<dynamic> listContents = [];
      if (rawContents is List) {
        listContents = rawContents;
      } else if (rawContents is String) {
        try {
          final d = jsonDecode(rawContents);
          if (d is List) listContents = d;
        } catch (_) {
          // posiblemente es HTML empaquetado como string -> lo mantenemos como 1 elemento
          listContents = [rawContents];
        }
      } else if (rawContents != null) {
        // intento convertir cualquier otra cosa a lista
        try {
          final d = jsonDecode(jsonEncode(rawContents));
          if (d is List) listContents = d;
        } catch (_) {
          listContents = [];
        }
      }

      // Normalize each content element into Map<String,dynamic> so ModuleContent.fromJson will succeed
      final List<Map<String, dynamic>> normalizedContents = [];
      for (var c in listContents) {
        if (c is Map<String, dynamic>) {
          normalizedContents.add(c);
        } else if (c is String) {
          // try decode string as JSON first
          bool pushed = false;
          try {
            final decoded = jsonDecode(c);
            if (decoded is Map<String, dynamic>) {
              normalizedContents.add(decoded);
              pushed = true;
            }
          } catch (_) {}
          if (!pushed) {
            // fallback: wrap as {'content': <string>}
            normalizedContents.add({'content': c});
          }
        } else {
          // lastly, attempt encode/decode
          try {
            final decoded = jsonDecode(jsonEncode(c));
            if (decoded is Map<String, dynamic>) normalizedContents.add(decoded);
            else normalizedContents.add({'content': decoded.toString()});
          } catch (_) {
            normalizedContents.add({'content': c.toString()});
          }
        }
      }

      // assign normalized contents into mMap so CourseModule.fromJson receives maps
      mMap['contents'] = normalizedContents;

      // ensure minimal keys expected by CourseModule.fromJson (avoid null issues)
      mMap['id'] = mMap['id'] ?? mMap['instance'] ?? 0;
      mMap['name'] = mMap['name'] ?? '';
      mMap['modname'] = mMap['modname'] ?? mMap['modName'] ?? mMap['modtype'] ?? '';

      final module = CourseModule.fromJson(mMap);
      modules.add(module);
    }

    // PARSE FILES (sección)
    dynamic rawFiles = sMap['files'] ?? [];
    if (rawFiles is String) {
      try {
        rawFiles = jsonDecode(rawFiles);
      } catch (_) {
        rawFiles = [];
      }
    }
    if (rawFiles is Map) rawFiles = rawFiles.values.toList();
    if (rawFiles is! List) rawFiles = [];

    final files = <String>[];
    for (var f in rawFiles) {
      if (f is String) files.add(f);
      else if (f is Map && f.containsKey('fileurl')) files.add(f['fileurl'].toString());
      else if (f is Map && f.containsKey('file')) files.add(f['file'].toString());
      else files.add(f.toString());
    }

    sections.add(CourseSection(
      id: int.tryParse(sMap['sectionid']?.toString() ?? '') ?? 0,
      name: sMap['name']?.toString() ?? 'Sección',
      summary: sMap['summary']?.toString() ?? '',
      files: files,
      modules: modules,
    ));
  }

  _log('FINAL SECTIONS COUNT: ${sections.length}');
  return sections;
}

// Resumen estadistico general
Future<SummaryStats> fetchSummaryStats() async {
  final token = auth.token;
  final userId = auth.userId; // asegúrate de tener este campo
  if (token == null || userId == null) {
    throw Exception('No estás autenticado');
  }

  final uri = Uri.parse('$_baseUrl/stats/summary.php');
  _log('POST $uri (userId=$userId)');

  final resp = await http.post(
    uri,
    headers: _headers(token), // ya incluye application/json; charset=UTF-8
    body: jsonEncode({'userId': userId}),
  );

  _log('response (${resp.statusCode})', resp.body);

  final body = _safeDecode(resp);
  if (body is! Map || body['status'] != 'ok') {
    throw Exception(body is Map ? (body['msg'] ?? 'Error al cargar estadísticas') : 'Respuesta inválida');
  }

  return SummaryStats.fromJson(Map<String, dynamic>.from(body));
}

//Tendencia de áreas
Future<List<AreaTrendPoint>> fetchAreaTrend(String area) async {
  final token = auth.token;
  final userId = auth.userId; // asegúrate de tener este campo
  if (token == null || userId == null) {
    throw Exception('No estás autenticado');
  }

  final uri = Uri.parse('$_baseUrl/stats/area_trend.php');
  _log('POST $uri (userId=$userId, area=$area)');

  final resp = await http.post(
    uri,
    headers: _headers(token),
    body: jsonEncode({'userId': userId, 'area': area}),
  );

  _log('response (${resp.statusCode})', resp.body);

  final body = _safeDecode(resp);
  if (body is! Map || body['status'] != 'ok') {
    throw Exception(body is Map ? (body['msg'] ?? 'Error al cargar evolución') : 'Respuesta inválida');
  }

  final items = body['data'] as List? ?? [];
  return items.map((e) => AreaTrendPoint.fromJson(Map<String, dynamic>.from(e))).toList();
}

  /// -------------------------
  /// Quizzes
  /// -------------------------
  Future<List<Quiz>> fetchQuizzes(int courseId) async {
    final token = auth.token;
    if (token == null) throw Exception('No estás autenticado');

    final uri =
        Uri.parse('$_baseUrl/moodle/get_quizzes.php?courseid=$courseId');
    _log('GET $uri');
    final resp = await http.get(uri, headers: _headers(token));
    _log('response (${resp.statusCode})', resp.body);

    final body = _safeDecode(resp);
    if (body is! Map || body['status'] != 'ok') {
      throw Exception('API error: ${body is Map ? (body['msg'] ?? 'Error al obtener quizzes') : 'Respuesta inválida'}');
    }

    final warnings = body['warnings'] as List<dynamic>? ?? [];
    if (warnings.isNotEmpty) AppLogger.w('API Warnings: $warnings');

    final quizzes = body['quizzes'];
    if (quizzes is! List) throw Exception('Formato inesperado en quizzes');

    return quizzes
        .map((q) => Quiz.fromJson(q as Map<String, dynamic>))
        .toList();
  }

Future<ContextStats> fetchContextStats(String area, String scope) async {
  final url = Uri.parse('$baseUrl/stats/context.php');
  try {
    final response = await http.post(
      url,
      body: jsonEncode({
        'userId': currentUserId,
        'area': area,
        'scope': scope,
      }),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.body.isEmpty) {
      throw Exception('Respuesta vacía del servidor (context.php)');
    }

    final json = jsonDecode(response.body);

    if (json is Map && json['status'] == 'error') {
      throw Exception(json['msg'] ?? 'Error en context.php');
    }

    return ContextStats.fromJson(json['data']);
  } catch (e) {
    throw Exception('Fallo al obtener estadísticas de contexto: $e');
  }
}

Future<RankStats> fetchRankStats(String area, String scope) async {
  final url = Uri.parse('$baseUrl/stats/rank.php');
  try {
    final response = await http.post(
      url,
      body: jsonEncode({
        'userId': currentUserId,
        'area': area,
        'scope': scope,
        'top': 20,
      }),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.body.isEmpty) {
      throw Exception('Respuesta vacía del servidor (rank.php)');
    }

    final json = jsonDecode(response.body);

    if (json is Map && json['status'] == 'error') {
      throw Exception(json['msg'] ?? 'Error en rank.php');
    }

    return RankStats.fromJson(json['data']);
  } catch (e) {
    throw Exception('Fallo al obtener ranking: $e');
  }
}


  Future<dynamic> getCourses({String category = ''}) async {
    try {
      final response = await ErrorHandler.withRetry(
        () => http.get(
          Uri.parse('$baseUrl/moodle/get_courses.php?category=$category'),
          headers: _getHeaders(),
        ),
        'getCourses-$category',
        2, // 2 reintentos
      );
      
      return _handleResponse(response);
    } catch (e) {
      AppLogger.e('Error en getCourses($category)', e);
      rethrow;
    }
  }
  
  Future<dynamic> getStats(int userId) async {
    try {
      final response = await ErrorHandler.withRetry(
        () => http.post(
          Uri.parse('$baseUrl/stats/summary.php'),
          headers: _getHeaders(),
          body: jsonEncode({'userId': userId}),
        ),
        'getStats-$userId',
        2,
      );
      
      return _handleResponse(response);
    } catch (e) {
      AppLogger.e('Error en getStats', e);
      rethrow;
    }
  }
  
Map<String, String> _getHeaders() {
  final headers = {
    'Content-Type': 'application/json',
  };

  if (auth.token != null) {
    headers['Authorization'] = 'Bearer ${auth.token}';
  }

  return headers;
}



// 🔹 Nuevo método público para otros servicios
Future<Map<String, String>> getHeaders() async { 
// Aquí podrías refrescar token si lo necesitas en el futuro 
return _getHeaders(); 
}

  
  dynamic _handleResponse(http.Response response) {
    final body = response.body;
    
    if (body.isEmpty) {
      throw Exception('Respuesta vacía del servidor');
    }
    
    final data = jsonDecode(body);
    
    if (response.statusCode == 200) {
      if (data['status'] == 'error') {
        // Manejar errores específicos del backend
        throw Exception(data['msg'] ?? 'Error del servidor');
      }
      return data;
    } else {
      throw Exception('HTTP ${response.statusCode}: ${data['msg'] ?? 'Error del servidor'}');
    }
  }


  /// -------------------------
  /// Obtener intento activo de un quiz
  /// -------------------------
  Future<Attempt?> getActiveAttempt(int quizId) async {
    final token = auth.token;
    if (token == null) throw Exception('Usuario no autenticado');

    final uri =
        Uri.parse('$_baseUrl/moodle/get_active_attempt.php?quizid=$quizId');
    _log('GET $uri');

    final resp = await http.get(uri, headers: _headers(token));
    _log('response (${resp.statusCode})', resp.body);

    final body = _safeDecode(resp);

    if (body is! Map || body['status'] != 'ok') {
      throw Exception(
          'API error: ${body is Map ? (body['msg'] ?? 'Error al obtener intento activo') : 'Respuesta inválida'}');
    }

    final attemptJson = body['attempt'];
    if (attemptJson == null) return null;

    return Attempt.fromJson(attemptJson as Map<String, dynamic>);
  }

// ===========================
// ApiService.startAttempt()
// ===========================
Future<Attempt> startAttempt(int quizId) async {
  final token = auth.token;
  if (token == null) throw Exception('Usuario no autenticado');

  final uri = Uri.parse('$_baseUrl/moodle/start_attempt.php'); // ✅ corregido el path
  _log('POST $uri', {'quizid': quizId});

  final resp = await http.post(
    uri,
    headers: _headers(token),
    body: jsonEncode({'quizid': quizId}),
  );

  _log('response (${resp.statusCode})', resp.body);

  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}: ${resp.reasonPhrase}');
  }

  final data = _safeDecode(resp);

  if (data is! Map || data['status'] != 'ok' || data['attemptid'] == null) {
    throw Exception('Error al iniciar intento: ${data is Map ? (data['msg'] ?? resp.body) : resp.body}');
  }

  // ✅ ahora usamos Attempt.manual que coincide con tu modelo
  return Attempt.manual(
    id: data['attemptid'],
    timelimit: data['timelimit'] ?? 0,
    timestart: data['timestart'] ?? 0,
    timefinish: data['timefinish'] ?? 0,
    timeleft: data['timeleft'] ?? 0,
  );
}


Future<Map<String, dynamic>> fetchAttempts(int quizId) async {
  final token = auth.token;
  if (token == null) throw Exception('Usuario no autenticado');

  final uri = Uri.parse('$_baseUrl/moodle/quiz_attempts_list.php');
  final resp = await http.post(
    uri,
    headers: _headers(token),
    body: jsonEncode({'quizid': quizId}),
  );

  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}: ${resp.reasonPhrase}');
  }

  final body = _safeDecode(resp);
  if (body is! Map || body['status'] != 'ok') {
    throw Exception('API error: ${body is Map ? (body['msg'] ?? 'Error al obtener intentos') : 'Respuesta inválida'}');
  }

  final data = body['data'] as Map<String, dynamic>? ?? {};
  final attemptsJson = data['attempts'] as List<dynamic>? ?? [];
  final accessInfo = data['accessinfo'] ?? {};

  return {
    'attempts': attemptsJson.map((a) => AttemptSummary.fromJson(a)).toList(),
    'accessinfo': accessInfo,
  };
}

// Método para convertir a plan premium

Future<void> upgradeToPremium() async {
  final token = auth.token;
  final url = Uri.parse('$baseUrl/upgrade_to_premium.php');

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
  );

  if (response.statusCode != 200) {
    throw Exception('Error al actualizar a premium');
  }

  final data = json.decode(response.body);
  if (data['status'] != 'ok') {
    throw Exception(data['msg'] ?? 'Error desconocido');
  }
}

Future<List<Plan>> getActivePlans() async {
  final url = Uri.parse('$baseUrl/get_all_active_plans.php');
  
  AppLogger.d('Llamando a: $url');

  final response = await http.get(url).timeout(
    const Duration(seconds: 15),
  );

  AppLogger.api('GET', '/get_all_active_plans.php', statusCode: response.statusCode);
  AppLogger.d('Body: ${response.body}');

  if (response.statusCode != 200) {
    throw Exception('Error cargando planes: ${response.statusCode}');
  }

  final data = json.decode(response.body);

  if (data['status'] != 'ok') {
    throw Exception(data['msg'] ?? 'Error al obtener los planes');
  }

  if (data['plans'] == null || data['plans'] is! List) {
    throw Exception('Formato de respuesta inválido');
  }

  // Debug: estructura de planes (solo en debug)
  assert(() {
    for (var i = 0; i < (data['plans'] as List).length; i++) {
      AppLogger.d('Plan $i: ${data['plans'][i]}');
    }
    return true;
  }());

  // Convertir a List<Plan>
  return (data['plans'] as List)
      .map((planJson) => Plan.fromJson(planJson))
      .toList();
}

Future<Map<String, dynamic>> createWompiPayment({
  required int planId,  // 🔴 CAMBIO: Ahora recibe planId, no planCode
}) async {
  final token = auth.token;

  if (token == null) {
    throw Exception('Usuario no autenticado');
  }

  final url = Uri.parse('$baseUrl/create_wompi_payment.php');

  final response = await http
      .post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'plan_id': planId,  // 🔴 CAMBIO: Enviar plan_id en lugar de plan_code
        }),
      )
      .timeout(const Duration(seconds: 30));

  if (response.body.isEmpty) {
    throw Exception('Respuesta vacía del servidor');
  }

  if (response.statusCode != 200) {
    throw Exception('Error HTTP ${response.statusCode}');
  }

  final dynamic data = json.decode(response.body);

  if (data is! Map<String, dynamic>) {
    throw Exception('Formato de respuesta inválido');
  }

  if (data['status'] != 'ok') {
    throw Exception(data['msg'] ?? 'Error al crear el pago');
  }

  return data;
}

  /// -------------------------
  /// Obtener datos de un intento (AHORA: obtiene todas las páginas)
  /// -------------------------
  Future<Map<String, dynamic>> fetchAttemptData(int attemptId) async {
    final token = auth.token;
    if (token == null) throw Exception('Usuario no autenticado');

    int page = 0;
    final merged = <String, dynamic>{};
    merged['questions'] = <dynamic>[];
    merged['savedResponses'] = <String, dynamic>{};

    while (true) {
      final uri = Uri.parse('$_baseUrl/moodle/get_attempt_data.php?attemptid=$attemptId&page=$page');
      _log('GET $uri');

      final resp = await http.get(uri, headers: _headers(token));
      _log('response (${resp.statusCode})', resp.body);

      // Manejo de errores HTTP
      if (resp.statusCode != 200) {
        // Tratar como error para que el controlador lo capture y muestre al usuario
        throw Exception('HTTP ${resp.statusCode}: ${resp.reasonPhrase}');
      }

      final body = _safeDecode(resp);
      if (body is! Map || body['status'] != 'ok') {
        throw Exception('API error: ${body is Map ? (body['msg'] ?? 'Error al obtener datos del intento') : 'Respuesta inválida'}');
      }

      // Agregar preguntas si vienen en esta página
      final pageQuestions = body['questions'] as List<dynamic>? ?? [];
      (merged['questions'] as List).addAll(pageQuestions);

      // If savedResponses present, merge (backend may provide once)
      final rawSaved = body['savedResponses'];
      if (rawSaved is Map) {
        final mapSaved = Map<String, dynamic>.from(rawSaved);
        (merged['savedResponses'] as Map<String, dynamic>).addAll(mapSaved);
      }

      // Copiar algunos campos útiles desde la última página (timelimit, timestart, timeleft...)
      // Sobrescribimos para tener valores actualizados
      for (final k in ['timelimit', 'timestart', 'timefinish', 'timeleft']) {
        if (body.containsKey(k)) merged[k] = body[k];
      }

      // nextpage: si -1 o null -> terminamos; si >=0 -> continuar
      final nextPage = body.containsKey('nextpage') ? body['nextpage'] : null;
      if (nextPage == null || (nextPage is int && nextPage == -1)) {
        break;
      } else if (nextPage is int && nextPage >= 0) {
        page = nextPage;
        // continue loop to fetch next page
      } else {
        // Fallback: si nextpage no viene en el formato esperado, rompemos
        break;
      }
    }

    _log('Preguntas totales cargadas: ${(merged['questions'] as List).length}');
    return merged;
  }

  /// -------------------------
  /// Obtener todas las preguntas (se mantiene por compatibilidad)
  /// -------------------------
  Future<List<QuizQuestion>> fetchAllQuestions(int attemptId) async {
    final token = auth.token;
    if (token == null) throw Exception('Usuario no autenticado');

    final data = await fetchAttemptData(attemptId);
    final questionsJson = data['questions'];
    if (questionsJson is! List) {
      throw Exception('Formato inesperado en preguntas');
    }

    final questions = questionsJson
        .map((q) => parseQuizQuestion(q as Map<String, dynamic>))
        .toList();

    _log('Preguntas cargadas (fetchAllQuestions): ${questions.length}');
    return questions;
  }

  /// -------------------------
  /// Enviar respuesta
  /// -------------------------
  Future<void> submitAnswer(int attemptId, Map<String, dynamic> answers) async {
    final token = auth.token;
    if (token == null) throw Exception('Usuario no autenticado');

    final uri = Uri.parse('$_baseUrl/moodle/submit_attempt.php');
    _log('POST $uri', answers);

    final bodyData = {
      'attemptid': attemptId,
      'answers': answers,
    };

    final resp = await http.post(
      uri,
      headers: _headers(token),
      body: jsonEncode(bodyData),
    );
    _log('response (${resp.statusCode})', resp.body);

    final body = _safeDecode(resp);
    if (body is! Map || body['status'] != 'ok') {
      throw Exception(
          'API error: ${body is Map ? (body['msg'] ?? 'Error al enviar respuesta') : 'Respuesta inválida'}');
    }
  }

  /// -------------------------
  /// Finalizar intento
  /// -------------------------
  Future<Map<String, dynamic>> finishAttempt(int attemptId) async {
    final token = auth.token;
    if (token == null) throw Exception('Usuario no autenticado');

    final uri = Uri.parse('$_baseUrl/moodle/finish_attempt.php');
    _log('POST $uri', {'attemptid': attemptId});

    final resp = await http.post(
      uri,
      headers: _headers(token),
      body: jsonEncode({'attemptid': attemptId}),
    );
    _log('response (${resp.statusCode})', resp.body);

    final body = _safeDecode(resp);
    if (body is! Map || body['status'] != 'ok') {
      throw Exception(
          'API error: ${body is Map ? (body['msg'] ?? 'Error al finalizar intento') : 'Respuesta inválida'}');
    }

    final reviewData = await reviewAttempt(attemptId);

    return {
      'finish': body['data'],
      'review': reviewData,
    };
  }

  /// -------------------------
  /// Revisar intento
  /// -------------------------
  Future<Map<String, dynamic>> reviewAttempt(int attemptId) async {
    final token = auth.token;
    if (token == null) throw Exception('Usuario no autenticado');

    final uri = Uri.parse('$_baseUrl/moodle/review_attempt.php');
    _log('POST $uri', {'attemptid': attemptId});

    final resp = await http.post(
      uri,
      headers: _headers(token),
      body: jsonEncode({'attemptid': attemptId}),
    );
    _log('response (${resp.statusCode})', resp.body);

    final body = _safeDecode(resp);
    if (body is! Map || body['status'] != 'ok') {
      throw Exception('API error: ${body is Map ? (body['msg'] ?? 'Error al revisar intento') : 'Respuesta inválida'}');
    }

    final data = body['data'];
    if (data is! Map) throw Exception('Formato inesperado en revisión');

    return Map<String, dynamic>.from(data);
  }

Future<void> saveSimulacroResult(Map<String, dynamic> data) async {
  final token = auth.token;
  if (token == null) throw Exception('Usuario no autenticado');

  final uri = Uri.parse('$_baseUrl/simulacros/save_result.php');

  // Log seguro (sin exponer Bearer token)
  AppLogger.api('POST', '/simulacros/save_result.php');
  AppLogger.d('Body: ${jsonEncode(data)}');

  final resp = await http.post(
    uri,
    headers: _headers(token),
    body: jsonEncode(data),
  );

  AppLogger.api('POST', '/simulacros/save_result.php', statusCode: resp.statusCode);
  AppLogger.d('Response body: ${resp.body}');

  final body = _safeDecode(resp);
  if (body is! Map || body['status'] != 'ok') {
    throw Exception('Error guardando estadísticas del simulacro');
  }
}
Future<Set<int>> fetchSimulacroAttempts(int userId) async {
  final url = Uri.parse('$baseUrl/simulacros/simulacros_attempts.php');
  final response = await http.post(url, body: {'userId': userId.toString()});

  if (response.statusCode != 200) {
    throw Exception('Error al consultar intentos de simulacros');
  }

  final data = jsonDecode(response.body);
  if (data['status'] != 'ok') {
    throw Exception('Respuesta inválida del servidor');
  }

  final attempts = data['attempts'] as List;
  return attempts.map<int>((a) => a['courseId'] as int).toSet();
}


/// ----------------------------------------------
/// Obtener estadísticas completas de un simulacro
/// ----------------------------------------------
Future<Map<String, dynamic>> fetchSimulacroStats(int simulacroId) async {
  final token = auth.token;
  if (token == null) throw Exception('Usuario no autenticado');

  final uri = Uri.parse('$_baseUrl/simulacros/stats.php?simulacro_id=$simulacroId');
  _log('GET $uri');

  final resp = await http.get(uri, headers: _headers(token));
  _log('response (${resp.statusCode})', resp.body);

  final body = _safeDecode(resp);
  if (body is! Map || body['status'] != 'ok') {
    throw Exception(body is Map ? (body['msg'] ?? 'Error al obtener estadísticas') : 'Respuesta inválida');
  }

  return Map<String, dynamic>.from(body);
}

/// ----------------------------------------------
/// Obtener ranking del simulacro
/// ----------------------------------------------
Future<Map<String, dynamic>> fetchSimulacroRanking(int simulacroId) async {
  final token = auth.token;
  if (token == null) throw Exception('Usuario no autenticado');

  final uri = Uri.parse('$_baseUrl/simulacros/ranking.php?simulacro_id=$simulacroId');
  _log('GET $uri');

  final resp = await http.get(uri, headers: _headers(token));
  _log('response (${resp.statusCode})', resp.body);

  final body = _safeDecode(resp);
  if (body is! Map || body['status'] != 'ok') {
    throw Exception(body is Map ? (body['msg'] ?? 'Error al obtener ranking') : 'Respuesta inválida');
  }

  return Map<String, dynamic>.from(body);
}



// -------------------------
// Retos (Challenge)
// -------------------------

Future<Map<String, dynamic>> createChallenge({
  required String title,
  required String area,
  required String level,
  required int quizId,
  required String scheduledDatetime,
  int durationMinutes = 10,
  List<int> invitedUsers = const [],
}) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/challenges/create_challenge.php');
  final bodyData = {
    'title': title,
    'area': area,
    'level': level,
    'quiz_id': quizId,
    'scheduled_datetime': scheduledDatetime,
    'duration_minutes': durationMinutes,
    // 👇 Ajuste: el backend espera "user_ids"
    'user_ids': invitedUsers,
    // 👇 Ajuste: el backend espera "type"
    'type': 'challenge',
  };

  _log('POST $uri', bodyData);
  final resp = await http.post(
    uri,
    headers: _headers(token),
    body: jsonEncode(bodyData),
  );

  // Decodificar siempre el body
  try {
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    } else {
      return {
        'status': 'error',
        'msg': 'Formato inesperado en respuesta',
        'raw': resp.body,
        'statusCode': resp.statusCode,
      };
    }
  } catch (e) {
    return {
      'status': 'error',
      'msg': resp.body.isNotEmpty ? resp.body : 'Respuesta inválida del servidor',
      'statusCode': resp.statusCode,
    };
  }
}

Future<Map<String, dynamic>> getChallengeTime(int challengeId) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/challenges/get_challenge_time.php?challenge_id=$challengeId');
  
  _log('GET $uri');
  final resp = await http.get(uri, headers: _headers(token));
  final body = _safeDecode(resp);

  if (body is! Map<String, dynamic> || body['status'] != 'ok') {
    throw Exception('Error al obtener tiempo del reto');
  }
  
  // Guardar tiempos para cálculo de desfase
  lastSyncTime = DateTime.now();
  lastServerTime = DateTime.fromMillisecondsSinceEpoch(body['server_time'] * 1000);
  
  return body;
}

Future<Map<String, dynamic>> forceFinishChallenge(int challengeId) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/challenges/force_finish_challenge.php');
  
  _log('POST $uri');
  final resp = await http.post(
    uri,
    headers: _headers(token),
    body: jsonEncode({'challenge_id': challengeId}),
  );
  final body = _safeDecode(resp);

  if (body is! Map<String, dynamic>) {
    throw Exception('Error al forzar finalización del reto');
  }
  return body;
}

Future<Map<String, dynamic>> getChallengeWaitingStatus(int challengeId) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/challenges/get_challenge_waiting_status.php?challenge_id=$challengeId');
  
  _log('GET $uri');
  final resp = await http.get(uri, headers: _headers(token));
  final body = _safeDecode(resp);

  if (body is! Map<String, dynamic>) {
    throw Exception('Error al obtener estado de espera del reto');
  }
  return body;
}

Future<Map<String, dynamic>> respondInvitation({
  required int challengeId,
  required String response, // 'aceptar' o 'rechazar'
}) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/challenges/respond_invitation.php');
  final bodyData = {
    'challenge_id': challengeId,
    'response': response,
  };

  _log('POST $uri', bodyData);
  final resp = await http.post(uri, headers: _headers(token), body: jsonEncode(bodyData));
  final body = _safeDecode(resp);

  if (body is! Map || body['status'] != 'ok') {
    throw Exception('Error al responder invitación: ${body is Map ? body['msg'] : resp.body}');
  }
  return Map<String, dynamic>.from(body);
}

Future<Map<String, dynamic>> startChallenge({
  required int challengeId,
  String action = 'ready', // 'ready' o 'force_start'
}) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/challenges/start_challenge.php');
  final bodyData = {
    'challenge_id': challengeId,
    'action': action,
  };

  _log('POST $uri', bodyData);
  final resp = await http.post(uri, headers: _headers(token), body: jsonEncode(bodyData));
  final body = _safeDecode(resp);

  if (body is! Map) throw Exception('Respuesta inválida al iniciar reto');
  return Map<String, dynamic>.from(body);
}

Future<Map<String, dynamic>> finishChallenge({
  required int challengeId,
  required double score,
  required List<Map<String, dynamic>> answers,
}) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/challenges/finish_challenge.php');

  final payload = {
    'challenge_id': challengeId,
    'score': score,
    'answers': answers,
  };

  _log('POST $uri', payload);

  late http.Response resp;
  try {
    resp = await http
        .post(
          uri,
          headers: _headers(token),
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 25));
  } on TimeoutException {
    throw Exception('Tiempo de espera agotado al finalizar el reto');
  }

  final decoded = _safeDecode(resp);

  if (decoded is! Map<String, dynamic>) {
    throw Exception('Respuesta inválida del servidor');
  }

  // si el backend mandó status != ok, disparar excepción
  if (decoded['status'] != 'ok') {
    throw Exception(decoded['msg'] ?? 'Error al finalizar el reto');
  }

  return decoded;
}


Future<Map<String, dynamic>> getChallengeDetail(int challengeId) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/challenges/get_challenge_detail.php?challenge_id=$challengeId');
  _log('GET $uri');
  final resp = await http.get(uri, headers: _headers(token));
  final body = _safeDecode(resp);

  if (body is! Map<String, dynamic> || body['status'] != 'ok') {
    throw Exception('Error al obtener detalle del reto');
  }
  return body;
}

Future<Map<String, dynamic>> getChallenges() async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/challenges/get_challenges.php?user_id=${auth.userId}');
  _log('GET $uri');
  final resp = await http.get(uri, headers: _headers(token));
  final body = _safeDecode(resp);

  if (body is! Map<String, dynamic> || body['status'] != 'ok') {
    throw Exception('Error al obtener lista de retos');
  }
  return body;
}

Future<Map<String, dynamic>> getChallengeResults(int challengeId) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/challenges/get_challenge_results.php?challenge_id=$challengeId');
  _log('GET $uri');
  final resp = await http.get(uri, headers: _headers(token));
  final body = _safeDecode(resp);

  if (body is! Map<String, dynamic> || body['status'] != 'ok') {
    throw Exception('Error al obtener resultados del reto');
  }
  return body;
}


    /// -------------------------
  /// Helpers
  /// -------------------------
  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  dynamic _safeDecode(http.Response resp) {
  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}: ${resp.reasonPhrase}');
  }

  final raw = resp.body;

  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    // Si no es JSON válido, devolvemos un error uniforme
    return {
      'status': 'error',
      'msg': 'Respuesta no es JSON válido',
      'raw': raw,
    };
  }

  // Si es un Map (lo esperado)
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }

  // Si el backend devuelve una lista
  if (decoded is List) {
    if (decoded.isNotEmpty && decoded.first is Map<String, dynamic>) {
      return Map<String, dynamic>.from(decoded.first);
    }
    return {
      'status': 'error',
      'msg': 'La respuesta es una lista sin Maps válidos',
      'raw': decoded,
    };
  }

  // Cualquier otra cosa
  return {
    'status': 'error',
    'msg': 'Estructura JSON inesperada',
    'raw': decoded,
  };
}


  void _log(String msg, [Object? data]) {
    if (data == null) {
      AppLogger.d('[API] $msg');
    } else {
      AppLogger.d('[API] $msg: $data');
    }
  }

    /// -------------------------
  /// Métodos faltantes
  /// -------------------------

  // Helper POST genérico
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> bodyData) async {
    final token = auth.token;
    if (token == null) throw Exception('No estás autenticado');

    final uri = Uri.parse('$_baseUrl$path');
    _log('POST $uri', bodyData);

    final resp = await http.post(uri, headers: _headers(token), body: jsonEncode(bodyData));
    final body = _safeDecode(resp);

    if (body is! Map) throw Exception('Respuesta inválida del servidor');
    return Map<String, dynamic>.from(body);
  }

  // Getter para currentUserId (para usar en ChallengeDetailScreen)
  int? get currentUserId => auth.userId;

 // Obtener quizzes por área y nivel (para usar en CreateChallengeScreen)
Future<List<Map<String, dynamic>>> getQuizzes({
  required String area,
  required String level,
}) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/challenges/get_quizzes.php')
      .replace(queryParameters: {
    'area': area,
    'level': level,
  });

  _log('GET $uri');

  final resp = await http.get(uri, headers: _headers(token));
  final body = _safeDecode(resp);

  if (body is! Map || body['status'] != 'ok') {
    throw Exception('Error al obtener quizzes: ${resp.statusCode} ${resp.body}');
  }

  final quizzes = body['quizzes'] as List<dynamic>? ?? [];
  return quizzes.map((q) => Map<String, dynamic>.from(q)).toList();
}

// Buscar usuarios (para invitar a retos)
Future<List<Map<String, dynamic>>> searchUsers(String query) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/challenges/search_users.php')
      .replace(queryParameters: {
    'query': query,
  });

  _log('GET $uri');

  final resp = await http.get(uri, headers: _headers(token));
  final body = _safeDecode(resp);

  if (body is! Map || body['status'] != 'ok') {
    throw Exception('Error al buscar usuarios: ${resp.statusCode} ${resp.body}');
  }

  final users = body['users'] as List<dynamic>? ?? [];
  return users.map((u) => Map<String, dynamic>.from(u)).toList();
}

// Aceptar / rechazar invitación al reto
Future<Map<String, dynamic>> respondChallenge({
  required int challengeId,
  required String action,
}) async {
  final token = auth.token;
  if (token == null) throw Exception('No estás autenticado');

  final uri = Uri.parse('$_baseUrl/challenges/respond_challenge.php');
  _log('POST $uri action=$action challengeId=$challengeId');

  final resp = await http.post(
    uri,
    headers: {
      ..._headers(token),
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'challenge_id': challengeId, 'action': action}),
  );

  _log('respond_challenge STATUS: ${resp.statusCode}');
  _log('respond_challenge HEADERS: ${resp.headers}');
  _log('respond_challenge BODY STRING: "${resp.body}"');
  _log('respond_challenge BODY BYTES: ${resp.bodyBytes.length > 0 ? resp.bodyBytes : []}');

  if (resp.statusCode != 200) {
    throw Exception('HTTP ${resp.statusCode}: ${resp.reasonPhrase}');
  }

  // si el body viene vacío, intentamos un fallback robusto:
  if (resp.body.trim().isEmpty) {
    _log('respond_challenge: cuerpo VACÍO -> intentando fallback get_challenge_detail');
    try {
      final detail = await getChallengeDetail(challengeId);
      // detail debería contener 'challenge' y 'participants'
      return {
        'status': 'ok',
        'msg': 'OK (respuesta reconstruida desde get_challenge_detail)',
        'challenge': detail['challenge'],
        'participants': detail['participants'] ?? detail['challenge']['participants'] ?? [],
      };
    } catch (e) {
      throw Exception('Servidor devolvió cuerpo VACÍO y fallback falló: $e');
    }
  }

  // parse normal
  dynamic body;
  try {
    body = jsonDecode(resp.body);
  } catch (e) {
    throw Exception('Error al responder reto: JSON inválido');
  }

  if (body is Map<String, dynamic>) {
    if (body['status'] == 'ok') return Map<String, dynamic>.from(body);
    throw Exception('Error al responder reto: ${body['msg'] ?? 'Respuesta inválida'}');
  }

  if (body is List && body.isNotEmpty && body.first is Map<String, dynamic>) {
    final first = Map<String, dynamic>.from(body.first as Map);
    if (first['status'] == 'ok') return first;
    throw Exception('Error al responder reto: ${first['msg'] ?? 'Respuesta inválida'}');
  }

  throw Exception('Error al responder reto: estructura inesperada');
}

Future<AdModel?> getActiveAd() async {
  final token = auth.token;
  if (token == null) return null;

  final response = await http.get(
    Uri.parse('$baseUrl/get_active_ad.php'),
    headers: {
      'Authorization': 'Bearer $token',
    },
  );

  if (response.statusCode != 200 || response.body.isEmpty) {
    return null;
  }

  final data = json.decode(response.body);

  if (data['status'] != 'ok') return null;

  return AdModel.fromJson(data['ad']);
}


Future<void> trackAdEvent({
  required int adId,
  required String event,
  int watchedSeconds = 0,
}) async {
  final token = auth.token;

  await http.post(
    Uri.parse('$baseUrl/track_ad_event.php'),
    headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
    body: json.encode({
      'ad_id': adId,
      'event': event,
      'watched_seconds': watchedSeconds,
    }),
  );
}



}