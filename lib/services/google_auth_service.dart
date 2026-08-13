// lib/services/google_auth_service.dart
// Saber+ — Google Sign-In Service v1.0
// Permite login/registro con cuenta Google.
// El idToken de Google se envía al backend (google_login.php) que lo valida
// con Firebase Admin SDK y devuelve el JWT propio de Saber+.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../core/utils/app_logger.dart';
import '../core/constants/app_constants.dart';

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
    final url = Uri.parse('${Env.apiBaseUrl}/google_login.php');
    AppLogger.d('GoogleAuthService: POST → $url');

    try {
      final resp = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id_token': idToken,
          'email': email,
          'display_name': displayName,
          'photo_url': photoUrl,
        }),
      ).timeout(const Duration(seconds: 20));

      AppLogger.api('POST', '/google_login.php', statusCode: resp.statusCode);

      if (resp.statusCode != 200) {
        final errBody = jsonDecode(resp.body);
        return GoogleAuthResult(
          success: false,
          errorMessage: errBody['msg'] ?? 'Error en el servidor',
        );
      }

      final data = jsonDecode(resp.body);

      if (data['status'] != 'ok') {
        return GoogleAuthResult(
          success: false,
          errorMessage: data['msg'] ?? 'Error desconocido',
        );
      }

      // Si es usuario nuevo → no hay JWT todavía, el frontend debe completar step2
      if (data['is_new_user'] == true) {
        return GoogleAuthResult(
          success: true,
          isNewUser: true,
          email: data['google_email'] ?? email,
          displayName: data['google_name'] ?? displayName,
          photoUrl: data['google_picture'] ?? photoUrl,
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
        user: data['user'] is Map ? Map<String, dynamic>.from(data['user']) : null,
        email: email,
        displayName: displayName,
        photoUrl: photoUrl,
      );
    } catch (e) {
      AppLogger.e('GoogleAuthService: error en POST /google_login.php', e);
      return GoogleAuthResult(
        success: false,
        errorMessage: 'No se pudo conectar con el servidor',
      );
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
