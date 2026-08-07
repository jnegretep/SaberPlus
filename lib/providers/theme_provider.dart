// lib/providers/theme_provider.dart
// Theme provider with persistence — Saber+ Phase 4
// Allows user to toggle between light, dark, and system theme modes.
// Persists the choice to SharedPreferences.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _keyThemeMode = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get isLightMode => _themeMode == ThemeMode.light;
  bool get isSystemMode => _themeMode == ThemeMode.system;

  /// Load saved theme preference from SharedPreferences
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIndex = prefs.getInt(_keyThemeMode);

    if (savedIndex != null && savedIndex >= 0 && savedIndex <= 2) {
      _themeMode = ThemeMode.values[savedIndex];
      notifyListeners();
    }
  }

  /// Set theme mode and persist
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThemeMode, mode.index);
  }

  /// Convenience: toggle between light and dark (ignoring system)
  Future<void> toggleDarkMode() async {
    final newMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(newMode);
  }

  /// Convenience: set to dark
  Future<void> setDark() async => setThemeMode(ThemeMode.dark);

  /// Convenience: set to light
  Future<void> setLight() async => setThemeMode(ThemeMode.light);

  /// Convenience: set to system
  Future<void> setSystem() async => setThemeMode(ThemeMode.system);
}
