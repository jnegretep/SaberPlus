import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/app_constants.dart';
import '../widgets/global_scaffold.dart';
import '../core/theme/app_colors.dart';

/// Pantalla "Quiénes somos" de SaberPlus.
///
/// v1.7.0 — Rebranding completo desde PrepSaber:
/// - Logo oficial (assets/images/saberplus.png) con fallback al ícono.
/// - Versión leída de [AppConstants.appVersion].
/// - Nueva sección "Síguenos" con las redes sociales oficiales.
class AcercaScreen extends StatelessWidget {
  const AcercaScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GlobalScaffold(
      currentIndex: 1,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Encabezado hero
            Container(
              padding: const EdgeInsets.all(24),
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
                  Container(
                    width: 80,
                    height: 80,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.shadowLg,
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/saberplus.png',
                      height: 52,
                      errorBuilder: (context, error, stackTrace) {
                        // Fallback: ícono escolar si el asset no carga
                        return const Icon(
                          Icons.school_rounded,
                          size: 40,
                          color: AppColors.primary,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'SaberPlus',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textOnPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Versión ${AppConstants.appVersion}',
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textOnPrimarySubtle,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tu compañero para dominar el ICFES Saber 11 🎯',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.surface.withOpacity(0.9),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Descripción general
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowSm,
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      Icon(
                        Icons.rocket_launch_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Nuestra Misión',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Que cada estudiante de Colombia llegue al ICFES Saber 11 con confianza '
                    'y preparación total. Combinamos un tutor con IA disponible 24/7, simulacros '
                    'realistas y gamificación con XP, retos y rankings para que estudiar se sienta '
                    'como jugar. Subir tu puntaje deja de ser una obligación y se vuelve una meta adictiva. 🚀',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textTertiary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Características principales
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowSm,
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.star_rounded,
                        color: AppColors.warning,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Características Principales',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureItem(
                    icon: Icons.auto_awesome,
                    title: 'Tutor IA 24/7',
                    description: 'Tu asistente personal para dudas del ICFES',
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem(
                    icon: Icons.assignment_turned_in_rounded,
                    title: 'Simulacros en tiempo real',
                    description: 'Evaluaciones con cronómetro y resultados inmediatos',
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem(
                    icon: Icons.emoji_events_rounded,
                    title: 'Retos y gamificación',
                    description: 'Sistema de logros, puntos y ranking competitivo',
                    color: AppColors.successDark,
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem(
                    icon: Icons.library_books_rounded,
                    title: 'Banco de preguntas actualizado',
                    description: '+5,000 preguntas con explicaciones detalladas',
                    color: AppColors.purple,
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem(
                    icon: Icons.play_circle_fill_rounded,
                    title: 'Recursos multimedia',
                    description: 'Videos, infografías y material complementario',
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem(
                    icon: Icons.analytics_rounded,
                    title: 'Estadísticas avanzadas',
                    description: 'Seguimiento detallado de progreso por áreas',
                    color: AppColors.warning,
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem(
                    icon: Icons.school_rounded,
                    title: 'Panel para colegios',
                    description: 'Seguimiento para directores y docentes',
                    color: AppColors.sky,
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem(
                    icon: Icons.sync_rounded,
                    title: 'Sincronización con Moodle',
                    description: 'Integración completa con plataforma educativa',
                    color: AppColors.primaryLight,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Equipo de desarrollo
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowSm,
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.group_rounded,
                        color: AppColors.purple,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Equipo de Desarrollo',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTeamMember(
                    role: 'Arquitectura y Desarrollo Flutter',
                    name: 'Jose Negrete',
                    description: 'Experto en desarrollo móvil multiplataforma',
                  ),
                  const SizedBox(height: 12),
                  _buildTeamMember(
                    role: 'Backend y API Integration',
                    name: 'Equipo Backend',
                    description: 'Integración Moodle y servicios en la nube',
                  ),
                  const SizedBox(height: 12),
                  _buildTeamMember(
                    role: 'Diseño UX/UI',
                    name: 'Equipo de Diseño',
                    description: 'Experiencia de usuario e interfaz visual',
                  ),
                  const SizedBox(height: 12),
                  _buildTeamMember(
                    role: 'Contenido Educativo',
                    name: 'Equipo Pedagógico',
                    description: 'Diseño curricular y validación de contenido',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Síguenos en redes
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowSm,
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.favorite_rounded,
                        color: AppColors.error,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Síguenos',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tips, retos y trucos para subir tu puntaje 🔥',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 128,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        _buildSocialCard(
                          context: context,
                          icon: Icons.photo_camera_rounded,
                          name: 'Instagram',
                          handle: '@saberplus.co',
                          url: AppConstants.instagramUrl,
                          iconDecoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFFE1306C),
                                Color(0xFF833AB4),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildSocialCard(
                          context: context,
                          icon: Icons.music_note_rounded,
                          name: 'TikTok',
                          handle: '@saberplus.co',
                          url: AppConstants.tiktokUrl,
                          iconDecoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF25F4EE).withOpacity(0.5),
                                blurRadius: 10,
                                offset: const Offset(-3, 0),
                              ),
                              BoxShadow(
                                color: const Color(0xFFFE2C55).withOpacity(0.5),
                                blurRadius: 10,
                                offset: const Offset(3, 0),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildSocialCard(
                          context: context,
                          icon: Icons.facebook_rounded,
                          name: 'Facebook',
                          handle: '@saberplus.co',
                          url: AppConstants.facebookUrl,
                          iconDecoration: const BoxDecoration(
                            color: Color(0xFF1877F2),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildSocialCard(
                          context: context,
                          icon: Icons.chat_rounded,
                          name: 'WhatsApp',
                          handle: '+57 315 279 1015',
                          url: AppConstants.whatsappUrl,
                          iconDecoration: const BoxDecoration(
                            color: Color(0xFF25D366),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Contacto y soporte
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowSm,
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.contact_support_rounded,
                        color: AppColors.successDark,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Contacto y Soporte',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildContactItem(
                    icon: Icons.email_rounded,
                    title: 'Correo electrónico',
                    value: AppConstants.supportEmail,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 12),
                  _buildContactItem(
                    icon: Icons.phone_rounded,
                    title: 'Teléfono',
                    value: AppConstants.supportPhone,
                    color: AppColors.successDark,
                  ),
                  const SizedBox(height: 12),
                  _buildContactItem(
                    icon: Icons.language_rounded,
                    title: 'Sitio web',
                    value: 'www.saberplus.app',
                    color: AppColors.purple,
                  ),
                  const SizedBox(height: 12),
                  _buildContactItem(
                    icon: Icons.schedule_rounded,
                    title: 'Horario de atención',
                    value: 'Lunes a Viernes: 8:00 AM - 6:00 PM',
                    color: AppColors.warning,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: const [
                  Text(
                    '© 2026 SaberPlus. Todos los derechos reservados.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textDisabled,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Una herramienta educativa para el éxito académico',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textDisabled,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────

  /// Abre una URL externa (red social / web) sin romper nunca la app.
  static Future<void> _launchUrl(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        _showErrorSnackBar(context, url);
      }
    } catch (_) {
      if (context.mounted) {
        _showErrorSnackBar(context, url);
      }
    }
  }

  static void _showErrorSnackBar(BuildContext context, String url) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No pudimos abrir el enlace 😅 ($url)'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.errorDark,
      ),
    );
  }

  Widget _buildSocialCard({
    required BuildContext context,
    required IconData icon,
    required String name,
    required String handle,
    required String url,
    required BoxDecoration iconDecoration,
  }) {
    return GestureDetector(
      onTap: () => _launchUrl(context, url),
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceClean,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: iconDecoration,
              child: Icon(
                icon,
                color: AppColors.textOnPrimary,
                size: 24,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              handle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: color,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTeamMember({
    required String role,
    required String name,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceClean,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AppColors.border,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              color: AppColors.textTertiary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  role,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDisabled,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceClean,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
