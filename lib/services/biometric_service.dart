// lib/services/biometric_service.dart
// Saber+ — Biometric Authentication Service v1.0
// Wrapper sobre local_auth para mostrar el prompt nativo de huella/rostro.
// No maneja tokens ni sesión — eso lo hace AuthService.loginWithBiometric().

import 'package:local_auth/local_auth.dart';
import '../core/utils/app_logger.dart';

/// Capacidad biométrica reportada por el dispositivo.
enum BiometricSupport {
  /// No hay hardware biométrico o no está configurado
  unavailable,
  /// El dispositivo soporta biometría pero el usuario no ha inscrito huellas/rostro
  availableButNotEnrolled,
  /// Listo para usarse
  ready,
}

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Verifica si el dispositivo puede usar autenticación biométrica.
  /// Retorna el nivel de soporte para que el frontend pueda mostrar
  /// mensajes de UI apropiados.
  static Future<BiometricSupport> checkSupport() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();

      if (!canCheck || !isDeviceSupported) {
        // Distinguir si el dispositivo tiene hardware pero no hay huellas enroladas
        // No hay API directa para esto en local_auth; lo aproximamos así:
        if (isDeviceSupported && !canCheck) {
          return BiometricSupport.availableButNotEnrolled;
        }
        return BiometricSupport.unavailable;
      }

      // Listar biometrías disponibles (fingerprint, face, iris)
      final enrolled = await _auth.getAvailableBiometrics();
      if (enrolled.isEmpty) {
        return BiometricSupport.availableButNotEnrolled;
      }

      return BiometricSupport.ready;
    } catch (e) {
      AppLogger.e('BiometricService.checkSupport: error', e);
      return BiometricSupport.unavailable;
    }
  }

  /// Lista los tipos de biometría enrolados (fingerprint, face, iris).
  /// Útil para mostrar "Huella" o "Reconocimiento facial" en la UI.
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      AppLogger.e('BiometricService.getAvailableBiometrics: error', e);
      return [];
    }
  }

  /// Muestra el prompt nativo de autenticación biométrica.
  ///
  /// [reason] es el mensaje que se muestra al usuario (ej: "Autentícate para
  /// ingresar a Saber+"). En iOS es el título del diálogo; en Android se
  /// usa el título por defecto del sistema.
  ///
  /// Retorna `true` si la autenticación fue exitosa, `false` si el usuario
  /// canceló o falló, y lanza excepción si hay un error del sistema.
  static Future<bool> authenticate({
    String reason = 'Autentícate para ingresar a Saber+',
  }) async {
    try {
      AppLogger.d('BiometricService.authenticate: mostrando prompt...');

      // ✅ API correcta de local_auth 2.2.0:
      // - localizedReason: requerido (string simple, no messages list)
      // - options: opciones de comportamiento
      // Los mensajes nativos por defecto del SO se usan automáticamente.
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,            // solo huella/rostro, no PIN del sistema
          useErrorDialogs: true,          // mostrar errores nativos del SO
          sensitiveTransaction: true,
        ),
      );

      AppLogger.i('BiometricService.authenticate: resultado=$ok');
      return ok;
    } catch (e) {
      AppLogger.e('BiometricService.authenticate: error', e);
      return false;
    }
  }

  /// Detiene cualquier flujo de autenticación activo.
  static Future<void> stopAuthentication() async {
    try {
      await _auth.stopAuthentication();
    } catch (e) {
      AppLogger.e('BiometricService.stopAuthentication: error', e);
    }
  }
}
