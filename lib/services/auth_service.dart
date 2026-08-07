// lib/services/auth_service.dart
// Servicio de autenticación — v1.5.0
// Cambios: URLs desde Env, AppLogger, constantes centralizadas

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../core/utils/app_logger.dart';
import '../core/constants/app_constants.dart';

class AuthService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();

  String? token;
  String? refreshToken;
  Map<String, dynamic>? user;

  // Campos de perfil
  String? nombre;
  String? username;
  String? departamento;
  String? ciudad;
  String? colegio;
  String? grado;
  String? _avatarPath;

  // Roles
  String? tipoUsuario;
  int? idUsuario;
  int? moodleId;

  // ── Getters de rol ──
  bool get isProfesor => tipoUsuario == AppConstants.roleProfesor;
  bool get isEstudiante =>
      tipoUsuario == AppConstants.roleEstudiante || tipoUsuario == null;
  bool get isAdmin => tipoUsuario == AppConstants.roleAdmin;

  // ── Avatar URL ──
  String get avatarUrl {
    if (_avatarPath == null || _avatarPath!.isEmpty) {
      return Env.defaultAvatarUrl;
    }

    // Si ya es URL completa, devolverla
    if (_avatarPath!.startsWith('http://') ||
        _avatarPath!.startsWith('https://') ||
        _avatarPath!.startsWith('data:')) {
      return _avatarPath!;
    }

    // Construir URL completa desde path relativo
    var cleanPath = _avatarPath!;
    if (cleanPath.startsWith('/')) {
      cleanPath = cleanPath.substring(1);
    }
    if (cleanPath.startsWith('uploads/avatars/')) {
      cleanPath = cleanPath.replaceFirst('uploads/avatars/', '');
    }

    return '${Env.avatarBaseUrl}$cleanPath';
  }

  // ── Constructor ──
  AuthService();

  /// Cargar sesión desde almacenamiento seguro
  Future<void> loadFromStorage() async {
    await _loadFromStorage();
  }

  /// Verificar si hay token almacenado
  Future<bool> hasStoredToken() async {
    final storedToken = await _storage.read(key: AppConstants.keyJwt);
    return storedToken != null && storedToken.isNotEmpty;
  }

  /// ID del usuario autenticado
  int? get userId {
    if (user == null) return null;
    return int.tryParse(user!['id_usuario']?.toString() ?? '');
  }

  // ────────────────────────────────────────────
  // LOGIN
  // ────────────────────────────────────────────
  Future<bool> login(String email, String password) async {
    final url = Uri.parse('${Env.apiBaseUrl}/login.php');
    AppLogger.d('login POST → $url');

    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      AppLogger.api('POST', '/login.php', statusCode: resp.statusCode);

      if (resp.statusCode != 200) return false;

      final data = jsonDecode(resp.body);
      if (data['status'] != 'ok') return false;

      token = data['token'];
      refreshToken = data['refresh_token'];

      await _storage.write(key: AppConstants.keyJwt, value: token);
      await _storage.write(key: AppConstants.keyRefreshToken, value: refreshToken);

      if (data['user'] != null) {
        user = data['user'];
        _mapUserFields(user!);
        await _storage.write(
            key: AppConstants.keyUser, value: jsonEncode(user));
      } else {
        await fetchProfile();
      }

      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.e('login ERROR', e);
      return false;
    }
  }

  // ────────────────────────────────────────────
  // LOGOUT
  // ────────────────────────────────────────────
  Future<void> logout() async {
    AppLogger.i('logout triggered');

    try {
      if (token != null) {
        final url = Uri.parse('${Env.apiBaseUrl}/logout.php');
        await http.post(url,
            headers: {'Authorization': 'Bearer $token'});
      }
    } catch (_) {
      AppLogger.w('logout API error (ignored)');
    }

    // Limpiar estado
    token = null;
    refreshToken = null;
    user = null;
    nombre = null;
    username = null;
    departamento = null;
    ciudad = null;
    colegio = null;
    grado = null;
    _avatarPath = null;
    tipoUsuario = null;
    idUsuario = null;
    moodleId = null;

    // Limpiar storage
    await _storage.delete(key: AppConstants.keyJwt);
    await _storage.delete(key: AppConstants.keyRefreshToken);
    await _storage.delete(key: AppConstants.keyUser);

    notifyListeners();
  }

  // ────────────────────────────────────────────
  // REFRESH TOKEN
  // ────────────────────────────────────────────
  Future<bool> tryRefresh() async {
    if (refreshToken == null) {
      refreshToken =
          await _storage.read(key: AppConstants.keyRefreshToken);
      if (refreshToken == null) {
        AppLogger.d('No refresh token stored');
        return false;
      }
    }

    AppLogger.d('Trying token refresh...');

    final url = Uri.parse('${Env.apiBaseUrl}/refresh.php');

    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'refresh_token': refreshToken},
      );

      if (resp.statusCode != 200) return false;

      final data = jsonDecode(resp.body);
      if (data['status'] != 'ok') return false;

      token = data['token'];

      if (data['refresh_token'] != null) {
        refreshToken = data['refresh_token'];
        await _storage.write(
            key: AppConstants.keyRefreshToken, value: refreshToken);
      }

      await _storage.write(key: AppConstants.keyJwt, value: token);

      AppLogger.i('Token refreshed successfully');
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.e('Token refresh ERROR', e);
      return false;
    }
  }

  // ────────────────────────────────────────────
  // FETCH PROFILE
  // ────────────────────────────────────────────
  Future<Map<String, dynamic>?> fetchProfile() async {
    if (token == null) {
      token = await _storage.read(key: AppConstants.keyJwt);
      if (token == null) return null;
    }

    final url = Uri.parse('${Env.apiBaseUrl}/perfil.php');
    AppLogger.d('fetchProfile — tipoUsuario actual: $tipoUsuario');

    try {
      final resp = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      AppLogger.api('POST', '/perfil.php', statusCode: resp.statusCode);

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);

        if (data['status'] == 'ok') {
          user = data['user'];
          _mapUserFields(user!);

          await _storage.write(
              key: AppConstants.keyUser, value: jsonEncode(user));

          notifyListeners();
          return user;
        }
      }

      // Si falla → intentar refresh
      if (await tryRefresh()) {
        return fetchProfile();
      }
    } catch (e) {
      AppLogger.e('fetchProfile ERROR', e);
    }

    return null;
  }

  // ────────────────────────────────────────────
  // HELPERS
  // ────────────────────────────────────────────
  void _mapUserFields(Map<String, dynamic> u) {
    nombre = u['nombre'];
    username = u['username'] ?? u['moodle_username'];
    departamento = u['departamento'];
    ciudad = u['ciudad'];
    colegio = u['colegio'];
    grado = u['grado'];

    _avatarPath = u['avatar_path']?.toString() ??
        u['avatar']?.toString() ??
        u['avatar_url']?.toString() ??
        u['foto']?.toString() ??
        '';

    AppLogger.d('Avatar path: $_avatarPath → $avatarUrl');

    tipoUsuario = u['tipo_usuario'] ?? AppConstants.roleEstudiante;
    idUsuario = _safeParseInt(u['id_usuario']);
    moodleId = _safeParseInt(u['moodle_id']);

    AppLogger.d(
        'User mapped — tipo: $tipoUsuario, id: $idUsuario, moodleId: $moodleId');
  }

  int? _safeParseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  void updateAvatar(String newAvatarPath) {
    _avatarPath = newAvatarPath;
    if (user != null) {
      user!['avatar_path'] = newAvatarPath;
    }
    _saveUserToStorage();
    notifyListeners();
  }

  Future<void> _saveUserToStorage() async {
    if (user != null) {
      await _storage.write(
          key: AppConstants.keyUser, value: jsonEncode(user));
    }
  }

  Future<void> _loadFromStorage() async {
    token = await _storage.read(key: AppConstants.keyJwt);
    refreshToken = await _storage.read(key: AppConstants.keyRefreshToken);

    final userRaw = await _storage.read(key: AppConstants.keyUser);
    if (userRaw != null) {
      try {
        user = jsonDecode(userRaw);
        _mapUserFields(user!);
      } catch (_) {}
    }

    AppLogger.d(
        'Storage loaded — token: ${token != null}, refresh: ${refreshToken != null}, '
        'tipo: $tipoUsuario, id: $idUsuario, moodleId: $moodleId');

    notifyListeners();
  }
}
