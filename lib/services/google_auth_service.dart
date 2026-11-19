// lib/services/google_auth_service.dart
// Saber+ — Google Sign-In Service v1.0
// Permite login/registro con cuenta Google.
// El idToken de Google se envía al backend (google_login.php) que lo valida
// con Firebase Admin SDK y devuelve el JWT propio de Saber+.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';

import '../config/env.dart';
import '../core/utils/app_logger.dart';
import '../core/constants/app_constants.dart';
import '../core/services/dio_client.dart';

/// Resultado del flujo de Google Sign-In.
/// El frontend decide qué hacer según [isNewUser].
class GoogleAuthResult {
  final bool success;
  final bool isNewUser;        // true → debe completar el registro (step2)
  final String? jwtToken;
  final String? refreshToken;
  final Map<String, dynamic>? user;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String? errorMessage;

  GoogleAuthResult({
    required this.success,
    this.isNewUser = false,
    this.jwtToken,
    this.refreshToken,
    this.user,
    this.email,
    this.displayName,
    this.photoUrl,
    this.errorMessage,
  });
}

class GoogleAuthService {
  static const _storage = FlutterSecureStorage();

  /// Configuración de GoogleSignIn.
  /// Los scopes solicitan email, profile y openid (suficiente para validar
  /// la identidad y precargar el formulario de registro).
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const [
      'email',
      'profile',
      'openid',
    ],
    // forceCodeForRefreshToken: true, // descomenta si en el futuro necesitas server-auth code
  );

  /// Ejecuta el flujo completo de Sign-In con Google y comunica con el backend.
  ///
  /// Retorna [GoogleAuthResult] con:
  /// - success=true + isNewUser=false → login directo (usuario ya existía)
  /// - success=true + isNewUser=true  → el frontend debe llevar al step2 con email/name precargados
  /// - success=false                  → error o cancelado por el usuario
  static Future<GoogleAuthResult> signInWithGoogle() async {
    try {
      AppLogger.d('GoogleAuthService: iniciando sign-in...');

      // 1. Abrir el flujo de Google (UI nativa de selección de cuenta)
      final GoogleSignInAccount? account = await _googleSignIn.signIn();

      // Usuario canceló el flujo
      if (account == null) {
        AppLogger.d('GoogleAuthService: usuario canceló el sign-in');
        return GoogleAuthResult(
          success: false,
          errorMessage: 'cancelled',
        );
      }

      AppLogger.i('GoogleAuthService: cuenta seleccionada → ${account.email}');

      // 2. Obtener el idToken (JWT de Google que el backend validará)
      final GoogleSignInAuthentication auth = await account.authentication;

      final String? idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        AppLogger.e('GoogleAuthService: idToken vacío tras autenticación', null);
        return GoogleAuthResult(
          success: false,
          errorMessage: 'No se pudo obtener el token de Google',
        );
      }

      // 3. Enviar idToken al backend para validación
      final response = await _sendToBackend(
        idToken: idToken,
        email: account.email,
        displayName: account.displayName ?? '',
        photoUrl: account.photoUrl ?? '',
      );

      return response;
    } on PlatformException catch (e) {
      AppLogger.e('GoogleAuthService: PlatformException', e);
      return GoogleAuthResult(
        success: false,
        errorMessage: e.message ?? 'Error nativo de Google Sign-In',
      );
    } catch (e) {
      AppLogger.e('GoogleAuthService: error inesperado', e);
      return GoogleAuthResult(
        success: false,
        errorMessage: 'Error inesperado: $e',
      );
    }
  }

  /// Llama al endpoint `/google_login.php` del backend con el idToken.
  ///
  /// El backend responde con:
  /// ```json
  /// {
  ///   "status": "ok",
  ///   "is_new_user": true|false,
  ///   "token": "<jwt>",
  ///   "refresh_token": "<rt>",
  ///   "user": { ... },
  ///   // Si is_new_user=true, también incluye:
  ///   "google_email": "...",
  ///   "google_name": "...",
  ///   "google_picture": "..."
  /// }
  /// ```
  static Future<GoogleAuthResult> _sendToBackend({
    required String idToken,
    required String email,
    required String displayName,
    required String photoUrl,
  }) async {
    AppLogger.d('GoogleAuthService: POST → /google_login.php');

    try {
      // ✅ FASE 1.3: Usar DioClient (con interceptores de logging y retry)
      // Google login es endpoint público, no necesita token JWT
      final response = await DioClient.post(
        '/google_login.php',
        data: {
          'id_token': idToken,
          'email': email,
          'display_name': displayName,
          'photo_url': photoUrl,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      if (response.statusCode != 200) {
        final errBody = response.data is Map
            ? response.data as Map<String, dynamic>
            : <String, dynamic>{};
        return GoogleAuthResult(
          success: false,
          errorMessage: errBody['msg']?.toString() ?? 'Error en el servidor',
        );
      }

      final data = response.data as Map<String, dynamic>;

      if (data['status'] != 'ok') {
        return GoogleAuthResult(
          success: false,
          errorMessage: data['msg']?.toString() ?? 'Error desconocido',
        );
      }

      // Si es usuario nuevo → no hay JWT todavía, el frontend debe completar step2
      if (data['is_new_user'] == true) {
        return GoogleAuthResult(
          success: true,
          isNewUser: true,
          email: data['google_email']?.toString() ?? email,
          displayName: data['google_name']?.toString() ?? displayName,
          photoUrl: data['google_picture']?.toString() ?? photoUrl,
        );
      }

      // Usuario existente → guardamos tokens y devolvemos info
      final token = data['token'] as String?;
      final refreshToken = data['refresh_token'] as String?;

      if (token == null) {
        return GoogleAuthResult(
          success: false,
          errorMessage: 'Token JWT no recibido del servidor',
        );
      }

      // Persistir en secure storage (igual que en el login convencional)
      await _storage.write(key: AppConstants.keyJwt, value: token);
      if (refreshToken != null) {
        await _storage.write(key: AppConstants.keyRefreshToken, value: refreshToken);
      }

      return GoogleAuthResult(
        success: true,
        isNewUser: false,
        jwtToken: token,
        refreshToken: refreshToken,
        user: data['user'] is Map
            ? Map<String, dynamic>.from(data['user'] as Map)
            : null,
        email: email,
        displayName: displayName,
        photoUrl: photoUrl,
      );
    } on DioException catch (e) {
      AppLogger.e('GoogleAuthService: Dio error en /google_login.php', e);
      return GoogleAuthResult(
        success: false,
        errorMessage: _dioToMessage(e),
      );
    } catch (e) {
      AppLogger.e('GoogleAuthService: error en POST /google_login.php', e);
      return GoogleAuthResult(
        success: false,
        errorMessage: 'No se pudo conectar con el servidor',
      );
    }
  }

  /// Convierte un DioException a un mensaje amigable para el usuario.
  static String _dioToMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'El servidor tardó demasiado en responder. Inténtalo de nuevo.';
      case DioExceptionType.connectionError:
        return 'Sin conexión a internet. Verifica tu red.';
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode ?? 0;
        if (status >= 500) return 'El servidor tiene problemas temporales.';
        return 'Error del servidor ($status).';
      default:
        return 'No se pudo conectar con el servidor.';
    }
  }

  /// Cierra la sesión de Google (no afecta la sesión local de Saber+).
  /// Útil cuando el usuario hace logout completo.
  static Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      AppLogger.e('GoogleAuthService: error en signOut', e);
    }
  }

  /// Verifica si hay una cuenta de Google ya conectada (sin pedir UI).
  static Future<bool> isSignedIn() async {
    try {
      return _googleSignIn.currentUser != null;
    } catch (_) {
      return false;
    }
  }
}
