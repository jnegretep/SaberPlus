// test/providers/theme_provider_test.dart
// Unit tests for ThemeProvider

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saberplus_app/providers/theme_provider.dart';

void main() {
  group('ThemeProvider', () {
    late ThemeProvider themeProvider;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      themeProvider = ThemeProvider();
      await themeProvider.loadFromPrefs();
    });

    test('initial theme mode is system', () {
      expect(themeProvider.themeMode, equals(ThemeMode.system));
    });

    test('setThemeMode updates mode correctly', () async {
      await themeProvider.setThemeMode(ThemeMode.dark);
      expect(themeProvider.themeMode, equals(ThemeMode.dark));
      expect(themeProvider.isDarkMode, isTrue);
      expect(themeProvider.isLightMode, isFalse);
    });

    test('setThemeMode to light works', () async {
      await themeProvider.setThemeMode(ThemeMode.light);
      expect(themeProvider.themeMode, equals(ThemeMode.light));
      expect(themeProvider.isLightMode, isTrue);
    });

    test('toggleDarkMode switches between light and dark', () async {
      // Start with light
      await themeProvider.setThemeMode(ThemeMode.light);
      expect(themeProvider.isDarkMode, isFalse);

      // Toggle → dark
      await themeProvider.toggleDarkMode();
      expect(themeProvider.isDarkMode, isTrue);

      // Toggle → light
      await themeProvider.toggleDarkMode();
      expect(themeProvider.isLightMode, isTrue);
    });

    test('setDark convenience method works', () async {
      await themeProvider.setDark();
      expect(themeProvider.isDarkMode, isTrue);
    });

    test('setLight convenience method works', () async {
      await themeProvider.setLight();
      expect(themeProvider.isLightMode, isTrue);
    });

    test('setSystem convenience method works', () async {
      await themeProvider.setSystem();
      expect(themeProvider.isSystemMode, isTrue);
    });

    test('setThemeMode notifies listeners', () async {
      bool notified = false;
      themeProvider.addListener(() => notified = true);

      await themeProvider.setThemeMode(ThemeMode.dark);
      expect(notified, isTrue);
    });

    test('setThemeMode does not notify if same mode', () async {
      await themeProvider.setThemeMode(ThemeMode.dark);

      bool notified = false;
      themeProvider.addListener(() => notified = true);

      await themeProvider.setThemeMode(ThemeMode.dark);
      expect(notified, isFalse);
    });

    test('persists theme preference', () async {
      await themeProvider.setThemeMode(ThemeMode.dark);

      // Create new provider and load
      final newProvider = ThemeProvider();
      await newProvider.loadFromPrefs();
      expect(newProvider.themeMode, equals(ThemeMode.dark));
    });
  });
}
