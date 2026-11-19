// lib/core/theme/app_colors.dart
// Design System de colores para Saber+
// Basado en el branding actual: azul principal + amarillo acento

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Primarios (Brand) ──
  static const Color primary = Color(0xFF1E4ED8);
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1E3A8A);
  static const Color primaryDeep = Color(0xFF1E3A8A);

  // ── Acentos ──
  static const Color accent = Color(0xFFFACC15);
  static const Color accentDark = Color(0xFFEAB308);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color sky = Color(0xFF0EA5E9);

  // ── Estados ──
  static const Color success = Color(0xFF22C55E);
  static const Color successDark = Color(0xFF10B981);
  static const Color successDeep = Color(0xFF065F46);
  static const Color successLight = Color(0xFFD1FAE5);
  static const Color successFg = Color(0xFF34D399);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningDark = Color(0xFF92400E);
  static const Color error = Color(0xFFEF4444);
  static const Color errorDark = Color(0xFFDC2626);
  static const Color errorDeep = Color(0xFF991B1B);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color errorFaint = Color(0xFFFEF2F2);
  static const Color errorFg = Color(0xFFFCA5A5);
  static const Color errorDeepDark = Color(0xFF7F1D1D);
  static const Color info = Color(0xFF3B82F6);

  // ── Superficies semánticas (info cards) ──
  static const Color infoBg = Color(0xFFF0F9FF);
  static const Color infoBorder = Color(0xFFE0F2FE);
  static const Color infoDark = Color(0xFF0369A1);
  static const Color infoDeeper = Color(0xFF0C4A6E);
  static const Color infoFg = Color(0xFF38BDF8);

  // ── Superficies semánticas (warning cards) ──
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color warningBorder = Color(0xFFFDE68A);
  static const Color warningText = Color(0xFFD97706);

  // ── Superficies semánticas (explanation / teaching) ──
  static const Color explanationBg = Color(0xFFE0E7FF);
  static const Color explanationText = Color(0xFF3730A3);

  // ── Superficies (Light) ──
  static const Color background = Color(0xFFF4F6FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9);
  static const Color surfaceClean = Color(0xFFF8FAFC);

  // ── Sombras y elevación ──
  static const Color shadowSm = Color(0x0D000000);  // ~black 5%
  static const Color shadowMd = Color(0x0A000000);  // ~black 4%
  static const Color shadowLg = Color(0x1A000000);  // ~black 10%
  static const Color shadowXl = Color(0x29000000);  // ~black 16%
  static const Color overlay = Color(0x80000000);   // ~black 50% (modal scrim)

  // ── Bordes & Dividers ──
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFF1F5F9);
  static const Color borderDark = Color(0xFF334155);
  static const Color borderMedium = Color(0xFF475569);

  // ── Texto ──
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF1E293B);
  static const Color textTertiary = Color(0xFF64748B);
  static const Color textDisabled = Color(0xFF94A3B8);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnPrimarySubtle = Color(0xB3FFFFFF); // white70
  static const Color textSubtle = Color(0xFFCBD5E1);
  static const Color textMuted = Color(0xFF6B7280);   // Grey-500

  // ── Steps & Progreso ──
  static const Color stepInactive = Color(0xFFE2E8F0);
  static const Color stepActive = primary;

  // ── Colores de materias / gráficos ──
  static const Color subjectMath = Color(0xFF2563EB);
  static const Color subjectReading = Color(0xFF22C55E);
  static const Color subjectScience = Color(0xFFF97316);
  static const Color subjectSocial = Color(0xFF8B5CF6);
  static const Color subjectEnglish = Color(0xFF0EA5E9);
  static const Color subjectTeal = Color(0xFF14B8A6);

  // ── Colores de podio / ranking ──
  static const Color gold = Color(0xFFFFD700);
  static const Color goldDark = Color(0xFFD97706);
  static const Color silver = Color(0xFFC0C0C0);
  static const Color bronze = Color(0xFFCD7F32);

  // ── Colores de estado para tiles / badges ──
  static const Color statusDefault = Color(0xFF9CA3AF);
  static const Color statusActive = Color(0xFF22C55E);
  static const Color statusWarning = Color(0xFFF97316);
  static const Color statusInactive = Color(0xFF6B7280);

  // ── Gradientes ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient chatUserGradient = LinearGradient(
    colors: [primary, primaryLight],
  );

  // ── Dark Mode Overrides ──
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkSurfaceVariant = Color(0xFF334155);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFFCBD5E1);
  static const Color darkTextTertiary = Color(0xFF94A3B8);
}
