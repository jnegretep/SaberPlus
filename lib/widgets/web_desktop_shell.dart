// lib/widgets/web_desktop_shell.dart
// Saber+ — Piezas del shell de ESCRITORIO WEB (solo kIsWeb).
//
// Lo usan:
//   - main.dart → _webFrame: fondo de escritorio elegante (degradado según
//     modo claro/oscuro + watermark del logo al 4% abajo-derecha).
//   - widgets/global_scaffold.dart: barra lateral (NavigationRail de 200px
//     con los mismos destinos del bottom nav) + contenido ancho (880px).
//
// ⚠️ WEB ONLY: cada widget de este archivo se autolimita con `kIsWeb`
// (en móvil/tablet renderiza nada o devuelve el child tal cual), además
// de que todos los puntos de invocación están guardados con `kIsWeb`.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Ancho del rail lateral de escritorio (NavigationRail extendida).
const double kWebRailWidth = 200.0;

/// Ancho máximo del contenido en el shell de escritorio.
const double kWebContentMaxWidth = 880.0;

/// Breakpoint (ancho de ventana) a partir del cual se usa el shell de
/// escritorio. Debe coincidir con el usado en main.dart (_webFrame) y en
/// GlobalScaffold.
const double kWebDesktopBreakpoint = 1100.0;

/// Fondo de escritorio: degradado elegante + watermark del logo.
///
/// - Dark:  #0A0F1E → #111827 (casi negro).
/// - Light: #EEF2F9 → #DCE5F3 (gris azulado claro muy sutil, para que las
///   tarjetas blancas del contenido resalten).
///
/// El logo (assets/images/saberplus.png) se pinta al 4% de opacidad,
/// posicionado abajo-derecha, como branding sutil. El child (la app) usa
/// su propio Scaffold/background encima, así que este fondo solo se ve
/// donde las pantallas son transparentes (p. ej. GlobalScaffold en modo
/// escritorio).
class WebDesktopBackground extends StatelessWidget {
  final bool isDark;
  final Widget child;

  const WebDesktopBackground({
    super.key,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // 🛡️ Guard estricto: en móvil/tablet no aplica (child tal cual).
    if (!kIsWeb) return child;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF0A0F1E), Color(0xFF111827)]
              : const [Color(0xFFEEF2F9), Color(0xFFDCE5F3)],
        ),
        // Watermark sutil del logo (branding) — abajo-derecha.
        image: const DecorationImage(
          image: AssetImage('assets/images/saberplus.png'),
          alignment: Alignment.bottomRight,
          opacity: 0.04,
          scale: 2.0, // 1024px → ~512px lógicos
        ),
      ),
      child: child,
    );
  }
}

/// Barra lateral de escritorio (WEB ONLY): NavigationRail extendida de 200px.
///
/// - Arriba: logo de la app (36px) + "SaberPlus" en bold + tagline
///   "Preparación ICFES".
/// - Luego: los MISMOS destinos que el bottom nav de GlobalScaffold
///   (mismos iconos, labels e índices). La navegación la inyecta
///   GlobalScaffold reutilizando EXACTAMENTE los mismos handlers del
///   bottom nav (_onStudentTap / _onTeacherTap).
/// - El bottom nav actual NO tiene botón de salir, así que el rail tampoco
///   lo incluye (cerrar sesión sigue estando en "Más" → Perfil, igual que
///   en móvil).
class WebDesktopRail extends StatelessWidget {
  final bool isTeacher;
  final int currentIndex;
  final bool isDark;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<int> onDestinationSelected;

  const WebDesktopRail({
    super.key,
    required this.isTeacher,
    required this.currentIndex,
    required this.isDark,
    required this.activeColor,
    required this.inactiveColor,
    required this.onDestinationSelected,
  });

  // Mismos destinos que el bottom nav de estudiantes
  // (widgets/global_scaffold.dart → _buildStudentBottomNav).
  static const List<NavigationRailDestination> _studentDestinations = [
    NavigationRailDestination(
        icon: Icon(Icons.home_rounded), label: Text('Inicio')),
    NavigationRailDestination(
        icon: Icon(Icons.school_rounded), label: Text('Retos')),
    NavigationRailDestination(
        icon: Icon(Icons.bar_chart_rounded), label: Text('Stats')),
    NavigationRailDestination(
        icon: Icon(Icons.settings_rounded), label: Text('Más')),
  ];

  // Mismos destinos que el bottom nav de profesores
  // (widgets/global_scaffold.dart → _buildTeacherBottomNav).
  static const List<NavigationRailDestination> _teacherDestinations = [
    NavigationRailDestination(
        icon: Icon(Icons.dashboard_rounded), label: Text('Dashboard')),
    NavigationRailDestination(
        icon: Icon(Icons.school_rounded), label: Text('Estudiantes')),
    NavigationRailDestination(
        icon: Icon(Icons.analytics_rounded), label: Text('Estadísticas')),
    NavigationRailDestination(
        icon: Icon(Icons.picture_as_pdf_rounded), label: Text('Informes')),
    NavigationRailDestination(
        icon: Icon(Icons.person_rounded), label: Text('Perfil')),
  ];

  @override
  Widget build(BuildContext context) {
    // 🛡️ Guard estricto: solo web.
    if (!kIsWeb) return const SizedBox.shrink();

    final nameColor =
        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final taglineColor =
        isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    return NavigationRail(
      extended: true,
      minWidth: 72,
      minExtendedWidth: kWebRailWidth,
      // Transparente: deja ver el degradado de fondo del shell.
      backgroundColor: Colors.transparent,
      selectedIndex: currentIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: isTeacher ? _teacherDestinations : _studentDestinations,
      // Logo + nombre + tagline arriba del rail.
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              'assets/images/saberplus.png',
              height: 36,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.school_rounded, size: 36),
            ),
            const SizedBox(height: 10),
            Text(
              'SaberPlus',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: nameColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Preparación ICFES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: taglineColor,
              ),
            ),
          ],
        ),
      ),
      // Indicador activo con el azul de la marca (AppColors.primary /
      // primaryLight según brillo — activeColor lo resuelve GlobalScaffold).
      indicatorColor: activeColor.withOpacity(0.15),
      selectedIconTheme: IconThemeData(color: activeColor),
      unselectedIconTheme: IconThemeData(color: inactiveColor),
      selectedLabelTextStyle: TextStyle(
        color: activeColor,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: inactiveColor,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
    );
  }
}
