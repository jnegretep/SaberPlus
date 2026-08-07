// lib/core/theme/app_theme.dart
// Tema Material 3 para Saber+ — Light & Dark
// Centraliza TODA la definición visual de la app.

import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  // ── Tipografía ──
  static const String fontFamily = 'Inter';

  static final TextTheme _textTheme = TextTheme(
    // Display
    displayLarge: TextStyle(fontFamily: fontFamily, fontSize: 57, height: 1.12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    displayMedium: TextStyle(fontFamily: fontFamily, fontSize: 45, height: 1.16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    displaySmall: TextStyle(fontFamily: fontFamily, fontSize: 36, height: 1.22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    // Headline
    headlineLarge: TextStyle(fontFamily: fontFamily, fontSize: 32, height: 1.25, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    headlineMedium: TextStyle(fontFamily: fontFamily, fontSize: 28, height: 1.29, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    headlineSmall: TextStyle(fontFamily: fontFamily, fontSize: 24, height: 1.33, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
    // Title
    titleLarge: TextStyle(fontFamily: fontFamily, fontSize: 22, height: 1.27, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    titleMedium: TextStyle(fontFamily: fontFamily, fontSize: 16, height: 1.50, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    titleSmall: TextStyle(fontFamily: fontFamily, fontSize: 14, height: 1.43, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
    // Body
    bodyLarge: TextStyle(fontFamily: fontFamily, fontSize: 16, height: 1.50, fontWeight: FontWeight.w400, color: AppColors.textPrimary),
    bodyMedium: TextStyle(fontFamily: fontFamily, fontSize: 14, height: 1.43, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
    bodySmall: TextStyle(fontFamily: fontFamily, fontSize: 12, height: 1.33, fontWeight: FontWeight.w400, color: AppColors.textTertiary),
    // Label
    labelLarge: TextStyle(fontFamily: fontFamily, fontSize: 14, height: 1.43, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    labelMedium: TextStyle(fontFamily: fontFamily, fontSize: 12, height: 1.33, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
    labelSmall: TextStyle(fontFamily: fontFamily, fontSize: 11, height: 1.45, fontWeight: FontWeight.w500, color: AppColors.textTertiary),
  );

  // ── Color Scheme ──
  static final ColorScheme _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primary,
    onPrimary: AppColors.textOnPrimary,
    primaryContainer: AppColors.primaryLight,
    onPrimaryContainer: AppColors.primaryDark,
    secondary: AppColors.accent,
    onSecondary: AppColors.textPrimary,
    secondaryContainer: const Color(0xFFFDE68A),
    onSecondaryContainer: const Color(0xFF713F12),
    tertiary: AppColors.success,
    onTertiary: Colors.white,
    error: AppColors.error,
    onError: Colors.white,
    errorContainer: const Color(0xFFFEE2E2),
    onErrorContainer: const Color(0xFF991B1B),
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    surfaceContainerHighest: AppColors.background,
    outline: AppColors.border,
    outlineVariant: AppColors.divider,
    shadow: Colors.black,
    scrim: Colors.black,
  );

  static final ColorScheme _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.primaryLight,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primaryDark,
    onPrimaryContainer: const Color(0xFFDBEAFE),
    secondary: AppColors.accent,
    onSecondary: AppColors.textPrimary,
    secondaryContainer: const Color(0xFF713F12),
    onSecondaryContainer: const Color(0xFFFDE68A),
    tertiary: AppColors.success,
    onTertiary: Colors.white,
    error: const Color(0xFFFCA5A5),
    onError: const Color(0xFF450A0A),
    errorContainer: const Color(0xFF991B1B),
    onErrorContainer: const Color(0xFFFEE2E2),
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkTextPrimary,
    surfaceContainerHighest: AppColors.darkBackground,
    outline: AppColors.darkBorder,
    outlineVariant: const Color(0xFF475569),
    shadow: Colors.black,
    scrim: Colors.black,
  );

  // ── Light Theme ──
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: _lightColorScheme,
    fontFamily: fontFamily,
    textTheme: _textTheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.border, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(
        color: AppColors.textDisabled,
        fontSize: 15,
        fontFamily: fontFamily,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      backgroundColor: AppColors.textSecondary,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 24,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );

  // ── Dark Theme ──
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorScheme: _darkColorScheme,
    fontFamily: fontFamily,
    textTheme: _textTheme.apply(
      bodyColor: AppColors.darkTextPrimary,
      displayColor: AppColors.darkTextPrimary,
    ),
    scaffoldBackgroundColor: AppColors.darkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkSurface,
      foregroundColor: AppColors.darkTextPrimary,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: AppColors.darkSurface,
      surfaceTintColor: Colors.transparent,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryLight,
        foregroundColor: Colors.white,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryLight,
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.darkSurfaceVariant,
      labelStyle: TextStyle(color: AppColors.darkTextPrimary, fontFamily: fontFamily),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.darkTextPrimary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.darkBorder, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.darkBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.primaryLight, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: const Color(0xFFFCA5A5), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(
        color: AppColors.darkTextTertiary,
        fontSize: 15,
        fontFamily: fontFamily,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      backgroundColor: AppColors.darkSurfaceVariant,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.darkBorder,
      thickness: 1,
      space: 24,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
