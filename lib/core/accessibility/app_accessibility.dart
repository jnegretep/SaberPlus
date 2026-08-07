// lib/core/accessibility/app_accessibility.dart
// Accessibility utilities for Saber+ Phase 4
// Semantic labels, tap target enforcement, contrast utilities

import 'package:flutter/material.dart';

// ── Semantic Labels ──

/// Centralized semantic labels for screen readers (TalkBack / VoiceOver)
class SemanticsLabels {
  SemanticsLabels._();

  // Navigation
  static const String navHome = 'Ir a inicio';
  static const String navChallenges = 'Ir a retos';
  static const String navStats = 'Ir a estadísticas';
  static const String navMore = 'Ver más opciones';
  static const String navProfile = 'Ir a perfil';
  static const String navBack = 'Volver atrás';

  // Dashboard
  static const String dashboardGreeting = 'Saludo de bienvenida';
  static const String dashboardProgress = 'Progreso general';
  static const String dashboardSimulacros = 'Sección de simulacros';
  static const String dashboardCursos = 'Sección de cursos';
  static const String dashboardRetos = 'Sección de retos';
  static const String dashboardFab = 'Abrir asistente Saber+ IA';

  // Auth
  static const String loginButton = 'Iniciar sesión';
  static const String registerButton = 'Crear cuenta';
  static const String forgotPassword = 'Recuperar contraseña';
  static const String emailField = 'Campo de correo electrónico';
  static const String passwordField = 'Campo de contraseña';
  static const String showPassword = 'Mostrar contraseña';
  static const String hidePassword = 'Ocultar contraseña';

  // Quiz
  static const String submitAnswer = 'Enviar respuesta';
  static const String nextQuestion = 'Siguiente pregunta';
  static const String previousQuestion = 'Pregunta anterior';
  static const String finishQuiz = 'Finalizar simulacro';
  static const String quizTimer = 'Temporizador del simulacro';

  // Chat
  static const String chatInput = 'Escribe tu pregunta';
  static const String chatSend = 'Enviar mensaje';
  static const String chatResponse = 'Respuesta del asistente';

  // General
  static const String refresh = 'Actualizar contenido';
  static const String retry = 'Reintentar';
  static const String close = 'Cerrar';
  static const String expand = 'Expandir';
  static const String collapse = 'Colapsar';
  static const String loading = 'Cargando contenido';
  static const String error = 'Error de conexión';
  static const String noData = 'No hay datos disponibles';
  static const String lockedContent = 'Contenido bloqueado';
  static const String completedContent = 'Contenido completado';

  // Profile
  static const String editProfile = 'Editar perfil';
  static const String changeAvatar = 'Cambiar foto de perfil';
  static const String themeToggle = 'Cambiar tema de la aplicación';
  static const String darkMode = 'Modo oscuro';
  static const String lightMode = 'Modo claro';
  static const String systemMode = 'Modo automático';
}

// ── Tap Target Enforcement ──

/// Ensures a minimum tap target size of 48x48dp (Material Design guideline).
/// Wraps any widget to guarantee accessibility compliance.
class MinimumTapTarget extends StatelessWidget {
  final Widget child;
  final double minSize;
  final VoidCallback? onTap;

  const MinimumTapTarget({
    super.key,
    required this.child,
    this.minSize = 48.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minSize,
        minHeight: minSize,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(minSize / 2),
        child: Center(child: child),
      ),
    );
  }
}

// ── Semantic Button ──

/// A button wrapper that adds proper semantics for screen readers.
class SemanticButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String label;
  final String? hint;
  final bool isEnabled;

  const SemanticButton({
    super.key,
    required this.child,
    this.onPressed,
    required this.label,
    this.hint,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      hint: hint,
      enabled: isEnabled,
      child: GestureDetector(
        onTap: isEnabled ? onPressed : null,
        child: child,
      ),
    );
  }
}

// ── Semantic Image ──

/// An image wrapper that provides meaningful semantic labels for screen readers.
class SemanticImage extends StatelessWidget {
  final Widget image;
  final String label;
  final bool isDecorative;

  const SemanticImage({
    super.key,
    required this.image,
    required this.label,
    this.isDecorative = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: isDecorative ? '' : label,
      child: ExcludeSemantics(
        excluding: isDecorative,
        child: image,
      ),
    );
  }
}

// ── Accessibility Size Constants ──

class AccessibilitySizes {
  AccessibilitySizes._();

  /// Minimum tap target size (Material Design spec)
  static const double minTapTarget = 48.0;

  /// Minimum touch target size for interactive elements
  static const double minTouchTarget = 44.0;

  /// Minimum font size for readable text (WCAG AA)
  static const double minReadableFontSize = 12.0;

  /// Recommended minimum font size for body text
  static const double minBodyFontSize = 14.0;

  /// Minimum stroke width for visible borders
  static const double minStrokeWidth = 1.5;

  /// Focus border width for keyboard navigation
  static const double focusBorderWidth = 2.0;

  /// Spacing between interactive elements
  static const double minInteractiveSpacing = 8.0;
}

// ── Labeled Section ──

/// Wraps a section of UI with a semantic header for screen reader navigation.
class LabeledSection extends StatelessWidget {
  final String label;
  final Widget child;
  final bool isHeader;

  const LabeledSection({
    super.key,
    required this.label,
    required this.child,
    this.isHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isHeader)
            Semantics(
              header: true,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 0,
                  height: 0,
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}
