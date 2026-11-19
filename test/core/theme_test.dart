// test/core/theme_test.dart
// Unit tests for AppTheme and AppColors design system

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saberplus_app/core/theme/app_theme.dart';
import 'package:saberplus_app/core/theme/app_colors.dart';

void main() {
  group('AppTheme', () {
    test('light theme uses Material 3', () {
      final theme = AppTheme.light;
      expect(theme.useMaterial3, isTrue);
    });

    test('dark theme uses Material 3', () {
      final theme = AppTheme.dark;
      expect(theme.useMaterial3, isTrue);
    });

    test('light theme has correct brightness', () {
      final theme = AppTheme.light;
      expect(theme.brightness, equals(Brightness.light));
    });

    test('dark theme has correct brightness', () {
      final theme = AppTheme.dark;
      expect(theme.brightness, equals(Brightness.dark));
    });

    test('light theme uses Inter font family', () {
      expect(AppTheme.fontFamily, equals('Inter'));
    });

    test('light theme has defined color scheme', () {
      final theme = AppTheme.light;
      expect(theme.colorScheme.primary, isNotNull);
      expect(theme.colorScheme.surface, isNotNull);
      expect(theme.colorScheme.error, isNotNull);
    });

    test('dark theme has defined color scheme', () {
      final theme = AppTheme.dark;
      expect(theme.colorScheme.primary, isNotNull);
      expect(theme.colorScheme.surface, isNotNull);
      expect(theme.colorScheme.error, isNotNull);
    });

    test('light scaffold background is not white (uses subtle gray)', () {
      final theme = AppTheme.light;
      expect(theme.scaffoldBackgroundColor, isNot(equals(Colors.white)));
    });

    test('dark scaffold background is dark', () {
      final theme = AppTheme.dark;
      expect(theme.scaffoldBackgroundColor, equals(AppColors.darkBackground));
    });

    test('light theme has Cupertino page transitions on Android', () {
      final theme = AppTheme.light;
      final pageTransitions = theme.pageTransitionsTheme;
      expect(pageTransitions, isNotNull);
    });

    test('dark theme has Cupertino page transitions on Android', () {
      final theme = AppTheme.dark;
      final pageTransitions = theme.pageTransitionsTheme;
      expect(pageTransitions, isNotNull);
    });

    test('light theme has defined input decoration theme', () {
      final theme = AppTheme.light;
      expect(theme.inputDecorationTheme.filled, isTrue);
      expect(theme.inputDecorationTheme.border, isNotNull);
    });

    test('dark theme has defined input decoration theme', () {
      final theme = AppTheme.dark;
      expect(theme.inputDecorationTheme.filled, isTrue);
      expect(theme.inputDecorationTheme.border, isNotNull);
    });

    test('light theme card has rounded corners', () {
      final theme = AppTheme.light;
      final cardShape = theme.cardTheme.shape as RoundedRectangleBorder?;
      expect(cardShape, isNotNull);
    });

    test('dark theme card has rounded corners', () {
      final theme = AppTheme.dark;
      final cardShape = theme.cardTheme.shape as RoundedRectangleBorder?;
      expect(cardShape, isNotNull);
    });
  });

  group('AppColors', () {
    test('primary color is deep blue', () {
      expect(AppColors.primary, equals(const Color(0xFF1E4ED8)));
    });

    test('accent color is golden yellow', () {
      expect(AppColors.accent, equals(const Color(0xFFFACC15)));
    });

    test('dark background is Slate-900', () {
      expect(AppColors.darkBackground, equals(const Color(0xFF0F172A)));
    });

    test('dark surface is Slate-800', () {
      expect(AppColors.darkSurface, equals(const Color(0xFF1E293B)));
    });

    test('dark text primary is light', () {
      expect(AppColors.darkTextPrimary, equals(const Color(0xFFF1F5F9)));
    });

    test('subject colors are defined', () {
      expect(AppColors.subjectMath, isNotNull);
      expect(AppColors.subjectReading, isNotNull);
      expect(AppColors.subjectScience, isNotNull);
      expect(AppColors.subjectSocial, isNotNull);
      expect(AppColors.subjectEnglish, isNotNull);
    });

    test('state colors are distinct', () {
      expect(AppColors.success, isNot(equals(AppColors.error)));
      expect(AppColors.success, isNot(equals(AppColors.warning)));
      expect(AppColors.error, isNot(equals(AppColors.warning)));
    });

    test('podium colors are defined', () {
      expect(AppColors.gold, isNotNull);
      expect(AppColors.silver, isNotNull);
      expect(AppColors.bronze, isNotNull);
    });

    test('gradient is defined', () {
      expect(AppColors.primaryGradient, isNotNull);
      expect(AppColors.primaryGradient.colors.length, equals(2));
    });
  });
}
