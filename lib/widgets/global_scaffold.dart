// lib/widgets/global_scaffold.dart
// Premium Scaffold global with animated bottom nav indicator,
// dark mode support, and adaptive layout for tablets

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';

class GlobalScaffold extends StatelessWidget {
  final Widget body;
  final int currentIndex;

  const GlobalScaffold({
    super.key,
    required this.body,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final isTeacher = auth.isProfesor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark ? AppColors.primaryLight : AppColors.primary;
    final inactiveColor = isDark ? AppColors.darkTextTertiary : AppColors.textDisabled;
    final navBgColor = isDark ? AppColors.darkSurface : AppColors.surface;

    // Check if tablet (width > 600)
    final width = MediaQuery.of(context).size.width;
    final isTablet = width > 600;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      body: SafeArea(
        bottom: false,
        child: body,
      ),
      bottomNavigationBar: isTablet
          ? _buildAdaptiveNavRail(context, currentIndex, activeColor, inactiveColor, isTeacher)
          : isTeacher
              ? _buildTeacherBottomNav(context, currentIndex, navBgColor, activeColor, inactiveColor)
              : _buildStudentBottomNav(context, currentIndex, navBgColor, activeColor, inactiveColor),
    );
  }

  // ── Navigation Rail for Tablets ──
  Widget _buildAdaptiveNavRail(
    BuildContext context,
    int currentIndex,
    Color activeColor,
    Color inactiveColor,
    bool isTeacher,
  ) {
    final destinations = isTeacher
        ? [
            const NavigationRailDestination(icon: Icon(Icons.dashboard_rounded), label: Text('Dashboard')),
            const NavigationRailDestination(icon: Icon(Icons.school_rounded), label: Text('Estudiantes')),
            const NavigationRailDestination(icon: Icon(Icons.analytics_rounded), label: Text('Estadísticas')),
            const NavigationRailDestination(icon: Icon(Icons.picture_as_pdf_rounded), label: Text('Informes')),
            const NavigationRailDestination(icon: Icon(Icons.person_rounded), label: Text('Perfil')),
          ]
        : [
            const NavigationRailDestination(icon: Icon(Icons.home_rounded), label: Text('Inicio')),
            const NavigationRailDestination(icon: Icon(Icons.school_rounded), label: Text('Retos')),
            const NavigationRailDestination(icon: Icon(Icons.bar_chart_rounded), label: Text('Stats')),
            const NavigationRailDestination(icon: Icon(Icons.settings_rounded), label: Text('Más')),
          ];

    return NavigationRail(
      selectedIndex: currentIndex,
      onDestinationSelected: (i) {
        if (isTeacher) {
          _onTeacherTap(context, i, currentIndex);
        } else {
          _onStudentTap(context, i, currentIndex);
        }
      },
      destinations: destinations,
      leading: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Image.asset(
          'assets/images/saberplus.png',
          height: 32,
          errorBuilder: (_, __, ___) => const Icon(Icons.school, size: 32),
        ),
      ),
      indicatorColor: activeColor.withOpacity(0.12),
      selectedIconTheme: IconThemeData(color: activeColor),
      unselectedIconTheme: IconThemeData(color: inactiveColor),
      selectedLabelTextStyle: MaterialStateTextStyle.resolveWith(
        (states) => TextStyle(color: activeColor, fontWeight: FontWeight.w600, fontSize: 11),
      ),
      unselectedLabelTextStyle: TextStyle(color: inactiveColor, fontSize: 11),
    );
  }

  // ── Bottom Nav Estudiantes (Premium) ──
  Widget _buildStudentBottomNav(
    BuildContext context,
    int currentIndex,
    Color bgColor,
    Color activeColor,
    Color inactiveColor,
  ) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.only(left: 18, right: 18, top: 10, bottom: 12 + bottomInset),
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _PremiumNavItem(
            icon: Icons.home_rounded,
            label: 'Inicio',
            index: 0,
            currentIndex: currentIndex,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            onTap: (i) => _onStudentTap(context, i, currentIndex),
          ),
          _PremiumNavItem(
            icon: Icons.school_rounded,
            label: 'Retos',
            index: 1,
            currentIndex: currentIndex,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            onTap: (i) => _onStudentTap(context, i, currentIndex),
          ),
          _PremiumNavItem(
            icon: Icons.bar_chart_rounded,
            label: 'Stats',
            index: 2,
            currentIndex: currentIndex,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            onTap: (i) => _onStudentTap(context, i, currentIndex),
          ),
          _PremiumNavItem(
            icon: Icons.settings_rounded,
            label: 'Más',
            index: 3,
            currentIndex: currentIndex,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            onTap: (i) => _onStudentTap(context, i, currentIndex),
          ),
        ],
      ),
    );
  }

  // ── Bottom Nav Profesores ──
  Widget _buildTeacherBottomNav(
    BuildContext context,
    int currentIndex,
    Color bgColor,
    Color activeColor,
    Color inactiveColor,
  ) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 12 + bottomInset),
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _PremiumNavItem(icon: Icons.dashboard_rounded, label: 'Dashboard', index: 0, currentIndex: currentIndex, activeColor: activeColor, inactiveColor: inactiveColor, onTap: (i) => _onTeacherTap(context, i, currentIndex), width: 56),
          _PremiumNavItem(icon: Icons.school_rounded, label: 'Estudiantes', index: 1, currentIndex: currentIndex, activeColor: activeColor, inactiveColor: inactiveColor, onTap: (i) => _onTeacherTap(context, i, currentIndex), width: 56, fontSize: 10),
          _PremiumNavItem(icon: Icons.analytics_rounded, label: 'Estadísticas', index: 2, currentIndex: currentIndex, activeColor: activeColor, inactiveColor: inactiveColor, onTap: (i) => _onTeacherTap(context, i, currentIndex), width: 56, fontSize: 10),
          _PremiumNavItem(icon: Icons.picture_as_pdf_rounded, label: 'Informes', index: 3, currentIndex: currentIndex, activeColor: activeColor, inactiveColor: inactiveColor, onTap: (i) => _onTeacherTap(context, i, currentIndex), width: 56, fontSize: 10),
          _PremiumNavItem(icon: Icons.person_rounded, label: 'Perfil', index: 4, currentIndex: currentIndex, activeColor: activeColor, inactiveColor: inactiveColor, onTap: (i) => _onTeacherTap(context, i, currentIndex), width: 56, fontSize: 10),
        ],
      ),
    );
  }

  // ── Navigation Handlers ──
  void _onStudentTap(BuildContext context, int index, int currentIndex) {
    if (index == currentIndex) return;
    switch (index) {
      case 0: Nav.goDashboard(context); break;
      case 1: Nav.goChallenges(context); break;
      case 2: Nav.goEstadisticas(context); break;
      case 3: Nav.goPerfilHub(context); break;
    }
  }

  void _onTeacherTap(BuildContext context, int index, int currentIndex) {
    if (index == currentIndex) return;
    switch (index) {
      case 0: Nav.goTeacher(context); break;
      case 1: Nav.goTeacherStudents(context); break;
      case 2: Nav.goTeacherStats(context); break;
      case 3: Nav.goTeacherReports(context); break;
      case 4: Nav.goPerfilHub(context); break;
    }
  }
}

// ── Premium Nav Item with animated indicator ──
class _PremiumNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<int> onTap;
  final double width;
  final double fontSize;

  const _PremiumNavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
    this.width = 64,
    this.fontSize = 11,
  });

  @override
  State<_PremiumNavItem> createState() => _PremiumNavItemState();
}

class _PremiumNavItemState extends State<_PremiumNavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: widget.index == widget.currentIndex ? 1.0 : 0.0,
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    if (widget.index == widget.currentIndex) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _PremiumNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isActive = widget.index == widget.currentIndex;
    if (isActive && !_controller.isCompleted) {
      _controller.forward();
    } else if (!isActive && !_controller.isDismissed) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.index == widget.currentIndex;

    return GestureDetector(
      onTap: () => widget.onTap(widget.index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: widget.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Active indicator pill
            AnimatedBuilder(
              animation: _scale,
              builder: (context, child) {
                return Container(
                  width: 28 * _scale.value,
                  height: 3,
                  decoration: BoxDecoration(
                    color: widget.activeColor.withOpacity(_scale.value),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              },
            ),
            const SizedBox(height: 6),
            // Icon
            Icon(
              widget.icon,
              size: widget.width < 60 ? 22 : 24,
              color: isActive ? widget.activeColor : widget.inactiveColor,
            ),
            const SizedBox(height: 4),
            // Label
            Text(
              widget.label,
              style: TextStyle(
                fontSize: widget.fontSize,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? widget.activeColor : widget.inactiveColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
