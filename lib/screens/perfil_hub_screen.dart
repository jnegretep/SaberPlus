// lib/screens/perfil_hub_screen.dart
// Saber+ — Premium Profile Hub with animated hero, quick stats, dark mode

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'perfil_screen.dart';
import '../widgets/global_scaffold.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';
import '../core/animations/app_animations.dart';
import '../core/animations/shimmer_loading.dart';
import '../core/widgets/theme_toggle.dart';
import '../providers/theme_provider.dart';
import '../core/animations/page_transitions.dart';

class PerfilHubScreen extends StatefulWidget {
  const PerfilHubScreen({Key? key}) : super(key: key);

  @override
  State<PerfilHubScreen> createState() => _PerfilHubScreenState();
}

class _PerfilHubScreenState extends State<PerfilHubScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? user;
  bool _loading = true;

  // Entrance animation
  late final AnimationController _entranceController;
  late final Animation<double> _heroFade;
  late final Animation<double> _contentSlide;

  @override
  void initState() {
    super.initState();
    _loadProfile();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _heroFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    );
    _contentSlide = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final profile = await auth.fetchProfile();
      if (mounted) {
        setState(() {
          user = profile;
          _loading = false;
        });
        _entranceController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _entranceController.forward();
      }
    }
  }

  Future<void> _refreshProfile() async {
    setState(() => _loading = true);
    await _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GlobalScaffold(
      currentIndex: 3,
      body: _loading
          ? const ProfileShimmer()
          : RefreshIndicator(
              onRefresh: _refreshProfile,
              color: AppColors.primary,
              backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Hero con animación
                    FadeTransition(
                      opacity: _heroFade,
                      child: ScaleTransition(
                        scale: Tween(begin: 0.95, end: 1.0).animate(_heroFade),
                        child: _buildProfileHeader(auth, isDark),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Quick Stats
                    SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.05),
                        end: Offset.zero,
                      ).animate(_contentSlide),
                      child: FadeTransition(
                        opacity: _contentSlide,
                        child: _buildQuickStats(auth, isDark),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Settings & Support
                    SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.08),
                        end: Offset.zero,
                      ).animate(_contentSlide),
                      child: FadeTransition(
                        opacity: _contentSlide,
                        child: Column(
                          children: [
                            _buildSettingsSection(isDark),
                            const SizedBox(height: 24),
                            _buildSupportSection(isDark),
                            const SizedBox(height: 24),
                            _buildLogoutButton(auth, isDark),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildProfileHeader(AuthService auth, bool isDark) {
    final String nombre = auth.nombre ?? 'Usuario';
    final String? avatarUrl = auth.avatarUrl;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primaryLight,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.textOnPrimary, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 34,
                      backgroundColor: surfaceColor,
                      backgroundImage:
                          (avatarUrl != null && avatarUrl.isNotEmpty)
                              ? NetworkImage(avatarUrl) as ImageProvider
                              : const AssetImage('assets/avatars/default.png')
                                  as ImageProvider,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PerfilScreen()),
                        );
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.shadowLg,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.edit_rounded,
                          size: 14,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textOnPrimary,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (auth.username?.isNotEmpty == true)
                      Text(
                        '@${auth.username!}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textOnPrimarySubtle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Verified badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 14,
                  color: AppColors.textOnPrimary.withOpacity(0.8),
                ),
                const SizedBox(width: 6),
                Text(
                  auth.tipoUsuario == 'profesor' ? 'Profesor verificado' : 'Cuenta verificada',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textOnPrimary.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick Stats Cards ──
  Widget _buildQuickStats(AuthService auth, bool isDark) {
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    return Row(
      children: [
        _buildStatCard(
          icon: Icons.school_rounded,
          label: 'Grado',
          value: auth.grado ?? '—',
          color: AppColors.primary,
          surfaceColor: surfaceColor,
          textColor: textPrimary,
          subColor: textTertiary,
          isDark: isDark,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          icon: Icons.location_city_rounded,
          label: 'Ciudad',
          value: auth.ciudad ?? '—',
          color: AppColors.accent,
          surfaceColor: surfaceColor,
          textColor: textPrimary,
          subColor: textTertiary,
          isDark: isDark,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          icon: Icons.verified_rounded,
          label: 'Estado',
          value: auth.user?['email_verificado'] == true ? 'Verificado' : 'Pendiente',
          color: auth.user?['email_verificado'] == true ? AppColors.success : AppColors.warning,
          surfaceColor: surfaceColor,
          textColor: textPrimary,
          subColor: textTertiary,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color surfaceColor,
    required Color textColor,
    required Color subColor,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: subColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection(bool isDark) {
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 12),
          child: Text(
            'Configuración y más',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textSecondary,
            ),
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildSettingCard(
              icon: Icons.person_rounded,
              title: 'Perfil completo',
              subtitle: 'Ver y editar perfil',
              color: AppColors.primary,
              isDark: isDark,
              surfaceColor: surfaceColor,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PerfilScreen()),
                );
              },
            ),
            _buildSettingCard(
              icon: Icons.bar_chart_rounded,
              title: 'Estadísticas',
              subtitle: 'Avanzadas',
              color: AppColors.successDark,
              isDark: isDark,
              surfaceColor: surfaceColor,
              onTap: () => Nav.goEstadisticas(context),
            ),
            _buildSettingCard(
              icon: Icons.notifications_active_rounded,
              title: 'Notificaciones',
              subtitle: 'Preferencias',
              color: AppColors.warning,
              isDark: isDark,
              surfaceColor: surfaceColor,
              onTap: () {},
            ),
            _buildSettingCard(
              icon: Icons.security_rounded,
              title: 'Privacidad',
              subtitle: 'Seguridad',
              color: AppColors.purple,
              isDark: isDark,
              surfaceColor: surfaceColor,
              onTap: () => Nav.goPrivacidad(context),
            ),
            _buildSettingCard(
              icon: Icons.palette_rounded,
              title: 'Tema',
              subtitle: isDark ? 'Oscuro' : 'Claro',
              color: AppColors.sky,
              isDark: isDark,
              surfaceColor: surfaceColor,
              onTap: () => _showThemeSheet(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
    required Color surfaceColor,
    required VoidCallback onTap,
  }) {
    final borderColor = isDark ? AppColors.darkBorder : AppColors.border;
    final textColor = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    return PressScale(
      onTap: onTap,
      child: Container(
        width: (MediaQuery.of(context).size.width - 56) / 2,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowMd,
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 11, color: textColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportSection(bool isDark) {
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.textSecondary;
    final subColor = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 12),
          child: Text(
            'Información y soporte',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadowSm,
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildSupportItem(
                icon: Icons.help_outline_rounded,
                title: 'Centro de ayuda',
                subtitle: 'Preguntas frecuentes',
                textColor: textColor,
                subColor: subColor,
                onTap: () {},
              ),
              Divider(height: 16, color: AppColors.surfaceVariant),
              _buildSupportItem(
                icon: Icons.info_outline_rounded,
                title: 'Acerca de la app',
                subtitle: 'Versión y detalles',
                textColor: textColor,
                subColor: subColor,
                onTap: () => Nav.goAcerca(context),
              ),
              Divider(height: 16, color: AppColors.surfaceVariant),
              _buildSupportItem(
                icon: Icons.star_rate_rounded,
                title: 'Calificar app',
                subtitle: 'En Play Store',
                textColor: textColor,
                subColor: subColor,
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSupportItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color textColor,
    required Color subColor,
    required VoidCallback onTap,
  }) {
    return PressScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: subColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: subColor)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textDisabled, size: 20),
          ],
        ),
      ),
    );
  }

  // ── Theme Bottom Sheet ──
  void _showThemeSheet() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    AppHaptics.lightImpact();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tema de la app',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkTextPrimary
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Elige cómo se ve Saber+ para ti',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkTextTertiary
                    : AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ThemeToggle(
                currentMode: themeProvider.themeMode,
                onModeChanged: (mode) {
                  AppHaptics.lightImpact();
                  themeProvider.setThemeMode(mode);
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton(AuthService auth, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: PressScale(
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('¿Cerrar sesión?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              content: const Text(
                  'Se cerrará tu sesión actual y deberás ingresar nuevamente.'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    auth.logout();
                    Nav.goToLoginAndClearStack(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          );
        },
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.error.withOpacity(0.3), width: 1.5),
            color: isDark ? AppColors.darkSurface : AppColors.surface,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, size: 20, color: AppColors.error),
              const SizedBox(width: 10),
              Text('Cerrar sesión',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.error)),
            ],
          ),
        ),
      ),
    );
  }
}
