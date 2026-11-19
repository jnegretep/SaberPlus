// lib/core/services/focus_mode_service.dart
// Saber+ - Modo enfoque durante simulacros
//
// Cuando el usuario esta en un simulacro, silencia las notificaciones
// de la app para que no lo interrumpen.
// Se activa automaticamente al entrar a QuestionScreen y se desactiva al salir.

import 'package:flutter/material.dart';

class FocusModeService extends ChangeNotifier {
  bool _isActive = false;

  bool get isActive => _isActive;

  void activate() {
    _isActive = true;
    notifyListeners();
    debugPrint('[FOCUS_MODE] Modo enfoque ACTIVADO - notificaciones silenciadas');
  }

  void deactivate() {
    _isActive = false;
    notifyListeners();
    debugPrint('[FOCUS_MODE] Modo enfoque DESACTIVADO - notificaciones restauradas');
  }
}
