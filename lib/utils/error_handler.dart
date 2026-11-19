// lib/utils/error_handler.dart
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/app_logger.dart';

class ErrorHandler {
  static bool isCriticalError(dynamic error) {
    final errorStr = error.toString();
    
    // Errores NO críticos (solo log, no mostrar al usuario)
    final nonCriticalPatterns = [
      'Duplicate entry',
      'contextlevel',
      'mdl_cont_conins_uix',
      'Error Moodle WS',
      'Respuesta inesperada de WS',
      'Unexpected response',
    ];
    
    return !nonCriticalPatterns.any((pattern) => errorStr.contains(pattern));
  }
  
  static void handleApiError(BuildContext context, dynamic error, {String? contextMessage}) {
    final errorStr = error.toString();
    
    // Si es error no crítico, solo loguear
    if (!isCriticalError(error)) {
      AppLogger.w('Error no crítico [$contextMessage]: $errorStr');
      return;
    }
    
    // Error crítico: mostrar al usuario
    final message = _getUserFriendlyMessage(errorStr);
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Error: $message')),
            ],
          ),
          backgroundColor: AppColors.errorDark,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
  
  static String _getUserFriendlyMessage(String error) {
    if (error.contains('SocketException') || error.contains('Connection refused')) {
      return 'Problema de conexión. Verifica tu internet.';
    } else if (error.contains('TimeoutException')) {
      return 'El servidor está tardando. Intenta nuevamente.';
    } else if (error.contains('404')) {
      return 'Recurso no encontrado.';
    } else if (error.contains('401') || error.contains('403')) {
      return 'Sesión expirada. Vuelve a iniciar sesión.';
    } else if (error.contains('500')) {
      return 'Error temporal del servidor. Intenta en unos minutos.';
    } else {
      return 'Ocurrió un error. Intenta nuevamente.';
    }
  }
  
  static Future<T> withRetry<T>(
    Future<T> Function() operation,
    String context,
    int maxRetries,
  ) async {
    int attempt = 0;
    
    while (attempt < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        AppLogger.w('Intento $attempt/$maxRetries fallado para [$context]: $e');
        
        // Si es el último intento, re-lanzar
        if (attempt >= maxRetries) {
          rethrow;
        }
        
        // Esperar antes de reintentar (backoff exponencial)
        await Future.delayed(Duration(seconds: attempt));
      }
    }
    
    throw Exception('No se pudo completar la operación después de $maxRetries intentos');
  }
}