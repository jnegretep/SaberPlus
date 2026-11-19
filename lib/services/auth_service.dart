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

  /// ✅ v2.0: tras un login fallido, contiene {user_id, email} si la causa
  /// fue un correo sin verificar (backend 403 unverified). Null en el resto
  /// de casos. Lo consume LoginScreen para redirigir a la verificación.
  Map<String, dynamic>? _lastUnverifiedLogin;
  Map<String, dynamic>? get lastUnverifiedLogin => _lastUnverifiedLogin;

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

    // ✅ v2.0: se limpia en cada intento; se rellena si el backend responde
    // 403 {status:'unverified'} para que la UI pueda guiar al usuario a la
    // pantalla de verificación de correo (antes se perdía y mostraba
    // "Credenciales inválidas").
    _lastUnverifiedLogin = null;

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
      // ✅ v2.0: capturar el 403 unverified para la UI.
      final resp = e.response;
      if (resp?.statusCode == 403) {
        try {
          final Map<String, dynamic> data;
          if (resp!.data is Map<String, dynamic>) {
            data = resp.data as Map<String, dynamic>;
          } else {
            data = Map<String, dynamic>.from(
                jsonDecode(resp.data?.toString() ?? '{}') as Map);
          }
          if (data['status'] == 'unverified') {
            _lastUnverifiedLogin = {
              'user_id': data['user_id'],
              'email': data['email'] ?? email,
            };
          }
        } catch (_) {}
      }
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

    // ✅ v2.0 (biometría rediseñada): el logout NO toca el flag del bloqueo
    // local (app_lock_enabled). La biometría ya no es un mecanismo de login
    // ni depende de tokens: es una preferencia del dispositivo que protege
    // el acceso a la app cuando HAY sesión. Sin sesión no hay nada que
    // desbloquear, así que el flag simplemente queda inerte hasta el
    // siguiente login.
    // (Legado v1.x: se limpian las claves del modelo antiguo si existieran.)
    await _storage.delete(key: AppConstants.keyBiometricEnabled);
    await _storage.delete(key: AppConstants.keyBiometricEmail);
    await _storage.delete(key: AppConstants.keyBiometricRefreshToken);

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

  /// ✅ v1.7.1: Callback usado por DioClient.onTokensRefreshed.
  /// Cuando el interceptor refresca los tokens automáticamente, este
  /// método los persiste en storage y sincroniza AuthService.token
  /// para que también lo vean las pantallas que usan http directo
  /// (chat IA, etc.). Sin esto, al reabrir la app el refresh token
  /// guardado ya estaba rotado en el servidor → logout forzado.
  Future<void> persistRefreshedTokens(String newToken, String? newRefresh) async {
    token = newToken;
    await _storage.write(key: AppConstants.keyJwt, value: newToken);
    if (newRefresh != null && newRefresh.isNotEmpty) {
      refreshToken = newRefresh;
      await _storage.write(key: AppConstants.keyRefreshToken, value: newRefresh);
    }
    DioClient.authToken = token;
    DioClient.refreshToken = refreshToken;
    notifyListeners();
    AppLogger.i('AuthService: tokens refrescados y persistidos');
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

    // ✅ v1.7.1: refresh PROACTIVO — si el JWT está vencido o vence en
    // menos de 1 hora, renovarlo ya (en silencio) para que ninguna
    // pantalla llegue a ver un 401 al volver tras inactividad.
    if (token != null && refreshToken != null) {
      final exp = _jwtExpiry(token!);
      if (exp == null || exp.isBefore(DateTime.now().add(const Duration(hours: 1)))) {
        AppLogger.i('JWT vencido o por vencer — refresh proactivo');
        try {
          await tryRefresh();
        } catch (e) {
          AppLogger.w('Refresh proactivo falló (se reintentará en el primer 401)',);
        }
      }
    }
  }

  /// Lee el campo `exp` de un JWT sin validar la firma (solo informativo).
  /// Devuelve null si el token no se puede decodificar.
  static DateTime? _jwtExpiry(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = String.fromCharCodes(base64Url.decode(payload));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = map['exp'];
      if (exp is num) {
        return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      }
      return null;
    } catch (_) {
      return null;
    }
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
  // ✅ v2.0 — BLOQUEO BIOMÉTRICO LOCAL (app lock)
  // ────────────────────────────────────────────
  // Modelo rediseñado: la biometría ya NO es un mecanismo de login ni
  // guarda credenciales/tokens dedicados (el modelo v1.x era contradictorio:
  // el logout borraba las flags, la rotación de refresh tokens invalidaba el
  // token biométrico en el servidor y el botón de huella casi nunca aparecía
  // habilitado). Ahora la biometría es SOLO una protección local de acceso:
  //
  //   - Sesión del servidor: JWT + refresh normales, sin cambios.
  //   - Al abrir/reanudar la app con sesión activa + bloqueo activado →
  //     LockScreen pide huella; si falla/cancela se puede reintentar o
  //     cerrar sesión e ir al login con contraseña.
  //   - Si la sesión expiró, los interceptores existentes mandan al login:
  //     la biometría NUNCA sustituye credenciales inexistentes.
  //   - Dispositivo sin biometría → acceso normal (la UI ni lo ofrece).

  /// ¿Está activado el bloqueo biométrico local en este dispositivo?
  Future<bool> isAppLockEnabled() async {
    final flag = await _storage.read(key: AppConstants.keyAppLockEnabled);
    return flag == 'true';
  }

  /// Activa el bloqueo biométrico local.
  /// Requiere sesión activa (el usuario lo activa desde Perfil o aceptando
  /// el aviso post-login). No guarda contraseñas ni tokens: solo un flag.
  Future<bool> enableAppLock() async {
    if (token == null || (user?['email'] as String?) == null) {
      AppLogger.w('enableAppLock: se requiere sesión activa');
      return false;
    }
    await _storage.write(key: AppConstants.keyAppLockEnabled, value: 'true');
    AppLogger.i('enableAppLock: bloqueo biométrico activado');
    notifyListeners();
    return true;
  }

  /// Desactiva el bloqueo biométrico local (desde Perfil).
  Future<void> disableAppLock() async {
    await _storage.delete(key: AppConstants.keyAppLockEnabled);
    AppLogger.i('disableAppLock: bloqueo biométrico desactivado');
    notifyListeners();
  }
}
