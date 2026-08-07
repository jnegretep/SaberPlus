// lib/features/auth/data/auth_repository.dart
// Repository para autenticación — separa lógica de datos de UI
// Usa Result<T> para error handling type-safe

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../config/env.dart';
import '../../../core/types/result.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/constants/app_constants.dart';

/// Modelo ligero de usuario autenticado
class AuthUser {
  final int? id;
  final String? nombre;
  final String? username;
  final String? email;
  final String? tipoUsuario;
  final String? avatarPath;
  final String? colegio;
  final String? grado;
  final int? moodleId;
  final Map<String, dynamic>? raw;

  const AuthUser({
    this.id,
    this.nombre,
    this.username,
    this.email,
    this.tipoUsuario,
    this.avatarPath,
    this.colegio,
    this.grado,
    this.moodleId,
    this.raw,
  });

  bool get isProfesor => tipoUsuario == AppConstants.roleProfesor;
  bool get isEstudiante => tipoUsuario == AppConstants.roleEstudiante || tipoUsuario == null;
  bool get isAdmin => tipoUsuario == AppConstants.roleAdmin;

  String get avatarUrl {
    if (avatarPath == null || avatarPath!.isEmpty) return Env.defaultAvatarUrl;
    if (avatarPath!.startsWith('http') || avatarPath!.startsWith('data:')) return avatarPath!;
    var cleanPath = avatarPath!;
    if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);
    if (cleanPath.startsWith('uploads/avatars/')) cleanPath = cleanPath.replaceFirst('uploads/avatars/', '');
    return '${Env.avatarBaseUrl}$cleanPath';
  }

  factory AuthUser.fromMap(Map<String, dynamic> m) => AuthUser(
    id: int.tryParse(m['id_usuario']?.toString() ?? ''),
    nombre: m['nombre']?.toString(),
    username: (m['username'] ?? m['moodle_username'])?.toString(),
    email: m['email']?.toString(),
    tipoUsuario: m['tipo_usuario']?.toString() ?? AppConstants.roleEstudiante,
    avatarPath: (m['avatar_path'] ?? m['avatar'] ?? m['avatar_url'] ?? m['foto'])?.toString(),
    colegio: m['colegio']?.toString(),
    grado: m['grado']?.toString(),
    moodleId: int.tryParse(m['moodle_id']?.toString() ?? ''),
    raw: m,
  );
}

/// Sessión autenticada completa
class AuthSession {
  final String token;
  final String? refreshToken;
  final AuthUser? user;

  const AuthSession({required this.token, this.refreshToken, this.user});
}

/// Repository de autenticación
class AuthRepository {
  static const _storage = FlutterSecureStorage();

  // ── Login ──
  Future<Result<AuthSession>> login(String email, String password) async {
    final url = Uri.parse('${Env.apiBaseUrl}/login.php');
    AppLogger.d('login POST → $url');

    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      AppLogger.api('POST', '/login.php', statusCode: resp.statusCode);

      if (resp.statusCode != 200) {
        return const Failure('Credenciales incorrectas');
      }

      final data = jsonDecode(resp.body);
      if (data['status'] != 'ok') {
        return Failure(data['msg']?.toString() ?? 'Error en login');
      }

      final session = AuthSession(
        token: data['token'] as String,
        refreshToken: data['refresh_token'] as String?,
        user: data['user'] != null ? AuthUser.fromMap(data['user'] as Map<String, dynamic>) : null,
      );

      // Persistir
      await _storage.write(key: AppConstants.keyJwt, value: session.token);
      if (session.refreshToken != null) {
        await _storage.write(key: AppConstants.keyRefreshToken, value: session.refreshToken);
      }
      if (session.user?.raw != null) {
        await _storage.write(key: AppConstants.keyUser, value: jsonEncode(session.user!.raw));
      }

      return Success(session);
    } catch (e) {
      AppLogger.e('login ERROR', e);
      return Failure('Error de conexión. Verifica tu internet.');
    }
  }

  // ── Token Refresh ──
  Future<Result<String>> refreshToken(String currentRefreshToken) async {
    final url = Uri.parse('${Env.apiBaseUrl}/refresh.php');

    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'refresh_token': currentRefreshToken},
      );

      if (resp.statusCode != 200) return const Failure('Sesión expirada');

      final data = jsonDecode(resp.body);
      if (data['status'] != 'ok') return const Failure('Sesión expirada');

      final newToken = data['token'] as String;
      await _storage.write(key: AppConstants.keyJwt, value: newToken);

      if (data['refresh_token'] != null) {
        final newRefresh = data['refresh_token'] as String;
        await _storage.write(key: AppConstants.keyRefreshToken, value: newRefresh);
      }

      return Success(newToken);
    } catch (e) {
      AppLogger.e('refreshToken ERROR', e);
      return const Failure('Error al renovar sesión');
    }
  }

  // ── Logout ──
  Future<void> logout(String? token) async {
    if (token != null) {
      try {
        final url = Uri.parse('${Env.apiBaseUrl}/logout.php');
        await http.post(url, headers: {'Authorization': 'Bearer $token'});
      } catch (_) {}
    }

    await _storage.delete(key: AppConstants.keyJwt);
    await _storage.delete(key: AppConstants.keyRefreshToken);
    await _storage.delete(key: AppConstants.keyUser);
    await _storage.delete(key: AppConstants.keySavedEmail);
    await _storage.delete(key: AppConstants.keyRememberMe);

    AppLogger.i('logout completed');
  }

  // ── Load from storage ──
  Future<AuthSession?> loadFromStorage() async {
    final token = await _storage.read(key: AppConstants.keyJwt);
    if (token == null) return null;

    final refreshToken = await _storage.read(key: AppConstants.keyRefreshToken);
    final userRaw = await _storage.read(key: AppConstants.keyUser);

    AuthUser? user;
    if (userRaw != null) {
      try {
        user = AuthUser.fromMap(jsonDecode(userRaw) as Map<String, dynamic>);
      } catch (_) {}
    }

    return AuthSession(token: token, refreshToken: refreshToken, user: user);
  }

  // ── Remember me ──
  Future<void> saveRememberMe(String email) async {
    await _storage.write(key: AppConstants.keySavedEmail, value: email);
    await _storage.write(key: AppConstants.keyRememberMe, value: 'true');
  }

  Future<String?> loadSavedEmail() async {
    final remember = await _storage.read(key: AppConstants.keyRememberMe);
    if (remember == 'true') {
      return await _storage.read(key: AppConstants.keySavedEmail);
    }
    return null;
  }

  Future<void> clearRememberMe() async {
    await _storage.delete(key: AppConstants.keySavedEmail);
    await _storage.delete(key: AppConstants.keyRememberMe);
  }
}
