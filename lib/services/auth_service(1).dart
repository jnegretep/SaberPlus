// lib/services/auth_service.dart
// Servicio de autenticación — v1.6.0
// Cambios vs v1.5.1:
//   - ✅ FASE 1.3: Migración completa a Dio con interceptores
//     (auth automático, retry, refresh token automático, logging)
//   - ✅ FIX #4: loginWithGoogle() para Google Sign-In
//   - ✅ FIX #5: Soporte para login biométrico
//   - URLs desde Env, AppLogger, constantes centralizadas

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';

import '../config/env.dart';
import '../core/utils/app_logger.dart';
import '../core/constants/app_constants.dart';
import '../core/services/dio_client.dart';
import 'google_auth_service.dart';

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
  /// Inicia sesión con email y contraseña.
  ///
  /// ✅ FASE 1.3: Migrado a Dio. Los interceptores se encargan de:
  /// - Logging automático de la petición
  /// - Retry automático si hay error de red
  /// - No necesita inyectar el token manualmente (login es endpoint público)
  Future<bool> login(String email, String password) async {
    AppLogger.d('login POST → /login.php');

    try {
      final response = await DioClient.post(
        '/login.php',
        data: {'email': email, 'password': password},
      );

      if (response.statusCode != 200) return false;

      final data = response.data as Map<String, dynamic>;
      if (data['status'] != 'ok') return false;

      token = data['token'] as String?;
      refreshToken = data['refresh_token'] as String?;

      // ✅ Sincronizar tokens con el DioClient para que los interceptores los usen
      DioClient.authToken = token;
      DioClient.refreshToken = refreshToken;

      await _storage.write(key: AppConstants.keyJwt, value: token);
      await _storage.write(key: AppConstants.keyRefreshToken, value: refreshToken);

      if (data['user'] != null) {
        user = data['user'] as Map<String, dynamic>;
        _mapUserFields(user!);
        await _storage.write(
            key: AppConstants.keyUser, value: jsonEncode(user));
      } else {
        await fetchProfile();
      }

      notifyListeners();
      return true;
    } on DioException catch (e) {
      AppLogger.e('login ERROR (Dio)', e);
      return false;
    } catch (e) {
      AppLogger.e('login ERROR', e);
      return false;
    }
  }

  // ────────────────────────────────────────────
  // LOGOUT
  // ────────────────────────────────────────────
  /// Cierra la sesión del usuario.
  ///
  /// ✅ FASE 1.3: Migrado a Dio. El AuthInterceptor inyecta el token
  /// automáticamente, no necesitamos pasarlo manualmente.
  Future<void> logout() async {
    AppLogger.i('logout triggered');

    try {
      if (token != null) {
        // El AuthInterceptor se encarga del header Authorization
        await DioClient.post('/logout.php');
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

    // ✅ Limpiar tokens del DioClient
    DioClient.authToken = null;
    DioClient.refreshToken = null;

    // Limpiar storage
    await _storage.delete(key: AppConstants.keyJwt);
    await _storage.delete(key: AppConstants.keyRefreshToken);
    await _storage.delete(key: AppConstants.keyUser);

    // ✅ FIX #5: Al cerrar sesión, también deshabilitamos la biometría
    // (forzamos al usuario a re-loguearse con credenciales la próxima vez).
    await _storage.delete(key: AppConstants.keyBiometricEnabled);
    await _storage.delete(key: AppConstants.keyBiometricEmail);

    notifyListeners();
  }

  // ────────────────────────────────────────────
  // REFRESH TOKEN
  // ────────────────────────────────────────────
  /// Refresca el token JWT usando el refresh token.
  ///
  /// ✅ FASE 1.3: Migrado a Dio. Usa un Dio separado sin interceptores
  /// para evitar recursión (el RefreshTokenInterceptor llamaría a este
  /// método infinitamente si usáramos la instancia principal).
  ///
  /// Nota: El RefreshTokenInterceptor del DioClient también hace refresh
  /// automáticamente cuando detecta un 401. Este método público se usa
  /// para el login biométrico (que parte sin sesión activa en memoria).
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

    try {
      // Dio separado sin interceptores para evitar recursión
      final rawDio = Dio(BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ));

      final response = await rawDio.post(
        '/refresh.php',
        data: {'refresh_token': refreshToken},
        options: Options(
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );

      if (response.statusCode != 200) return false;

      final data = response.data as Map<String, dynamic>;
      if (data['status'] != 'ok') return false;

      token = data['token'] as String?;

      if (data['refresh_token'] != null) {
        refreshToken = data['refresh_token'] as String?;
        await _storage.write(
            key: AppConstants.keyRefreshToken, value: refreshToken);
      }

      await _storage.write(key: AppConstants.keyJwt, value: token);

      // ✅ Sincronizar con DioClient
      DioClient.authToken = token;
      DioClient.refreshToken = refreshToken;

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
  /// Obtiene el perfil del usuario desde el backend.
  ///
  /// ✅ FASE 1.3: Migrado a Dio. El AuthInterceptor inyecta el token
  /// automáticamente, y el RefreshTokenInterceptor renueva el token si
  /// el backend responde 401. Ya no necesitamos manejar refresh manualmente.
  Future<Map<String, dynamic>?> fetchProfile() async {
    if (token == null) {
      token = await _storage.read(key: AppConstants.keyJwt);
      if (token == null) return null;
      // Sincronizar con DioClient
      DioClient.authToken = token;
    }

    AppLogger.d('fetchProfile — tipoUsuario actual: $tipoUsuario');

    try {
      final response = await DioClient.post('/perfil.php');

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;

        if (data['status'] == 'ok') {
          user = data['user'] as Map<String, dynamic>;
          _mapUserFields(user!);

          await _storage.write(
              key: AppConstants.keyUser, value: jsonEncode(user));

          notifyListeners();
          return user;
        }
      }

      // Si llegamos aquí, el RefreshTokenInterceptor ya intentó renovar
      // y falló. No reintentar manualmente para evitar bucles.
      AppLogger.w('fetchProfile: status ${response.statusCode}, refresh ya intentado por interceptor');
    } on DioException catch (e) {
      // Si es 401, el RefreshTokenInterceptor ya lo manejó
      if (e.response?.statusCode == 401) {
        AppLogger.w('fetchProfile: 401 (refresh ya intentado por interceptor)');
      } else {
        AppLogger.e('fetchProfile ERROR (Dio)', e);
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

    // ✅ Sincronizar tokens con DioClient para que los interceptores los usen
    DioClient.authToken = token;
    DioClient.refreshToken = refreshToken;

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

  // ────────────────────────────────────────────
  // GOOGLE SIGN-IN (FIX #4)
  // ────────────────────────────────────────────

  /// Inicia el flujo de Google Sign-In y, si el usuario ya existe,
  /// completa el login en el [AuthService].
  ///
  /// Retorna un [GoogleAuthResult] que permite al llamador decidir
  /// qué hacer (ir al dashboard o al step2 si es usuario nuevo).
  Future<GoogleAuthResult> loginWithGoogle() async {
    final result = await GoogleAuthService.signInWithGoogle();

    if (!result.success) return result;

    if (result.isNewUser) {
      // Usuario nuevo — el frontend debe llevarlo a completar el registro
      // Hacemos signOut en Google para no dejar la sesión colgada
      await GoogleAuthService.signOut();
      AppLogger.i('loginWithGoogle: usuario nuevo, redirigir a step2');
      return result;
    }

    // Usuario existente — aplicar el JWT recibido
    token = result.jwtToken;
    refreshToken = result.refreshToken;

    // ✅ Sincronizar tokens con DioClient
    DioClient.authToken = token;
    DioClient.refreshToken = refreshToken;

    if (result.user != null) {
      user = result.user;
      _mapUserFields(user!);
      await _storage.write(
          key: AppConstants.keyUser, value: jsonEncode(user));
    } else {
      // Si el backend no devolvió user, fetch profile
      await fetchProfile();
    }

    AppLogger.i('loginWithGoogle: login exitoso para ${result.email}');
    notifyListeners();
    return result;
  }

  // ────────────────────────────────────────────
  // BIOMETRIC LOGIN (FIX #5)
  // ────────────────────────────────────────────

  /// Verifica si el login biométrico está habilitado para algún usuario
  /// en este dispositivo. No muestra UI.
  Future<bool> isBiometricEnabled() async {
    final flag = await _storage.read(key: AppConstants.keyBiometricEnabled);
    final hasRefresh = await _storage.read(key: AppConstants.keyRefreshToken);
    return flag == 'true' && hasRefresh != null && hasRefresh.isNotEmpty;
  }

  /// Devuelve el email asociado al login biométrico (para mostrar en UI).
  Future<String?> getBiometricEmail() async {
    return await _storage.read(key: AppConstants.keyBiometricEmail);
  }

  /// Habilita el login biométrico para el usuario actualmente autenticado.
  /// A partir de este momento, [loginWithBiometric] podrá usarse para
  /// iniciar sesión sin pedir email/contraseña.
  ///
  /// Requiere que el usuario tenga un refresh token válido almacenado.
  Future<bool> enableBiometricLogin() async {
    if (refreshToken == null || refreshToken!.isEmpty) {
      AppLogger.w('enableBiometricLogin: no hay refresh token disponible');
      return false;
    }

    final email = this.user?['email'] as String? ?? '';
    if (email.isEmpty) {
      AppLogger.w('enableBiometricLogin: no se pudo determinar el email');
      return false;
    }

    await _storage.write(key: AppConstants.keyBiometricEnabled, value: 'true');
    await _storage.write(key: AppConstants.keyBiometricEmail, value: email);

    AppLogger.i('enableBiometricLogin: biometría habilitada para $email');
    return true;
  }

  /// Deshabilita el login biométrico.
  Future<void> disableBiometricLogin() async {
    await _storage.delete(key: AppConstants.keyBiometricEnabled);
    await _storage.delete(key: AppConstants.keyBiometricEmail);
    AppLogger.i('disableBiometricLogin: biometría deshabilitada');
    notifyListeners();
  }

  /// Ejecuta el login biométrico.
  ///
  /// Flujo:
  /// 1. Verifica que la biometría esté habilitada y haya refresh token.
  /// 2. El llamador debe invocar [BiometricService.authenticate()] para mostrar
  ///    el prompt nativo. Si la autenticación biométrica es exitosa, este
  ///    método intenta refrescar el token usando el refresh token almacenado.
  /// 3. Si el refresh funciona → login completo (notifyListeners).
  /// 4. Si el refresh falla → retorna false (el usuario debe re-loguearse).
  Future<bool> loginWithBiometric() async {
    final enabled = await isBiometricEnabled();
    if (!enabled) {
      AppLogger.w('loginWithBiometric: biometría no habilitada');
      return false;
    }

    // Cargar el refresh token desde storage (puede que el usuario no tenga
    // una sesión activa en memoria pero sí un refresh token persistido).
    refreshToken ??=
        await _storage.read(key: AppConstants.keyRefreshToken);

    if (refreshToken == null) {
      AppLogger.w('loginWithBiometric: no hay refresh token almacenado');
      return false;
    }

    AppLogger.i('loginWithBiometric: intentando refresh...');
    final ok = await tryRefresh();
    if (!ok) {
      AppLogger.w('loginWithBiometric: refresh falló, requiere re-login');
      return false;
    }

    // Cargar perfil para completar datos en memoria
    final profile = await fetchProfile();
    if (profile == null) {
      AppLogger.w('loginWithBiometric: fetchProfile falló tras refresh');
      return false;
    }

    AppLogger.i('loginWithBiometric: login biométrico exitoso');
    return true;
  }
}
