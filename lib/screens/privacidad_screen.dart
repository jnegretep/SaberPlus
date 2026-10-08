import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../widgets/global_scaffold.dart';
import '../core/theme/app_colors.dart';

/// Política de Privacidad de SaberPlus.
///
/// v1.7.0 — Reescritura alineada con el formulario de Data Safety de
/// Google Play (tipos de datos recopilados, compartidos y terceros).
/// La vigencia es fija (septiembre de 2026), no la fecha del dispositivo.
class PrivacidadScreen extends StatelessWidget {
  const PrivacidadScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GlobalScaffold(
      currentIndex: 1,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Encabezado destacado
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.surface.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.security_rounded,
                          color: AppColors.textOnPrimary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Políticas de Privacidad',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textOnPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tu privacidad es nuestra prioridad',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.surface.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.update_rounded,
                          size: 18,
                          color: AppColors.textOnPrimarySubtle,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Vigencia: septiembre de 2026',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textOnPrimarySubtle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 1. Información general
            _buildPolicySection(
              icon: Icons.info_outline_rounded,
              title: '1. Información general',
              content:
                  'SaberPlus es una aplicación colombiana de preparación para las pruebas ICFES '
                  'Saber 11, y es la responsable del tratamiento de tus datos personales. '
                  'Esta política explica, en lenguaje claro, qué información recopilamos, para qué '
                  'la usamos, con quién la compartimos y cómo puedes ejercer tus derechos. '
                  'Al crear una cuenta aceptas estas condiciones, y puedes consultarlas en cualquier '
                  'momento desde esta pantalla. Para cualquier duda puedes escribirnos a '
                  '${AppConstants.supportEmail}.',
            ),

            const SizedBox(height: 16),

            // 2. Datos que recopilamos
            _buildPolicySection(
              icon: Icons.data_usage_rounded,
              title: '2. Datos que recopilamos',
              content:
                  'Recopilamos únicamente la información necesaria para que entrenes, midas tu '
                  'progreso y compitas sanamente. Estos son los tres grupos de datos que maneja la app:',
              children: [
                _buildBulletPoint(
                  'Cuenta: nombre, correo electrónico, teléfono, departamento, ciudad, colegio, '
                  'grado escolar y foto de perfil.',
                ),
                _buildBulletPoint(
                  'Uso de la app: resultados de simulacros, respuestas, XP acumulado, rachas de '
                  'estudio, logros e insignias, y tus participaciones en retos contra otros estudiantes.',
                ),
                _buildBulletPoint(
                  'Técnicos: registro de errores y fallas (crashes), eventos de analítica de uso '
                  'y el token de notificaciones de tu dispositivo.',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 3. Cómo usamos tus datos
            _buildPolicySection(
              icon: Icons.verified_user_rounded,
              title: '3. Cómo usamos tus datos',
              content:
                  'Usamos tu información para que SaberPlus funcione de verdad y se sienta tuyo. '
                  'Con tus resultados armamos tus estadísticas personales, tu puntaje estimado y tus '
                  'áreas fuertes y débiles. Tu XP y tus retos alimentan los rankings de estudiantes, '
                  'colegios y departamentos. También usamos el token de notificaciones para avisarte '
                  'de nuevos retos, simulacros y recordatorios de estudio. Finalmente, los eventos '
                  'agregados y anónimos nos ayudan a mejorar la app para toda la comunidad.',
              children: [
                _buildBulletPoint(
                  'Brindarte el servicio: tu cuenta, tus cursos, simulacros y retos.',
                ),
                _buildBulletPoint(
                  'Calcularte estadísticas personales, puntaje estimado y recomendaciones de estudio.',
                ),
                _buildBulletPoint(
                  'Ubicarte en los rankings y mostrarte logros comparados con otros estudiantes.',
                ),
                _buildBulletPoint(
                  'Enviarte notificaciones de retos, resultados y novedades (puedes desactivarlas).',
                ),
                _buildBulletPoint(
                  'Mejorar la app con analítica agregada y reportes de errores.',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 4. Servicios de terceros
            _buildPolicySection(
              icon: Icons.hub_rounded,
              title: '4. Servicios de terceros',
              content:
                  'Para operar SaberPlus usamos proveedores que también protegen tus datos según '
                  'sus propias políticas. Estos son los tres que intervienen directamente:',
              children: [
                _buildBulletPoint(
                  'Firebase (Google LLC): analítica de uso (Analytics), reporte de fallas '
                  '(Crashlytics) y envío de notificaciones (Cloud Messaging).',
                ),
                _buildBulletPoint(
                  'DeepSeek (tutor con IA): para responder tus dudas académicas enviamos tu '
                  'pregunta y tu contexto académico (grado y áreas). Nunca enviamos tus datos de '
                  'contacto ni tu contraseña.',
                ),
                _buildBulletPoint(
                  'Wompi y Google Play (pagos): procesan tus compras de forma segura. Nosotros '
                  'NO almacenamos datos de tarjetas de crédito o débito.',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 5. Compartimos datos
            _buildPolicySection(
              icon: Icons.share_rounded,
              title: '5. Compartimos datos',
              content:
                  'No vendemos, alquilamos ni comercializamos tus datos personales. Jamás. '
                  'Solo compartimos la información estrictamente necesaria en procesos internos '
                  'de operación (como los proveedores descritos en la sección anterior) y cuando '
                  'exista una exigencia legal o judicial válida, en cumplimiento de la Ley 1581 '
                  'de 2012 (Régimen General de Protección de Datos Personales de Colombia) y '
                  'demás normas aplicables.',
            ),

            const SizedBox(height: 16),

            // 6. Menores de edad
            _buildPolicySection(
              icon: Icons.family_restroom_rounded,
              title: '6. Menores de edad',
              content:
                  'SaberPlus está dirigida a estudiantes de 13 años en adelante, porque las '
                  'pruebas Saber 11 se presentan al final del bachillerato. Si eres menor de edad, '
                  'debes usar la app con la supervisión y el consentimiento de tus padres o acudientes; '
                  'ellos pueden contactarnos en cualquier momento para ejercer tus derechos. '
                  'La app no está dirigida a menores de 13 años y no recopilamos de forma intencional '
                  'sus datos; si detectamos una cuenta de un menor de 13 años, la eliminaremos.',
            ),

            const SizedBox(height: 16),

            // 7. Tus derechos
            _buildPolicySection(
              icon: Icons.gavel_rounded,
              title: '7. Tus derechos',
              content:
                  'Tienes derecho a conocer, actualizar, corregir y ELIMINAR tus datos personales '
                  'cuando quieras. Eliminar tu cuenta es rápido y lo controlas tú mismo: ve a '
                  'Perfil → Configuración → Eliminar cuenta, y borraremos los datos de la app '
                  'asociados a tu perfil. Conservamos tu información únicamente mientras tu cuenta '
                  'exista o mientras debamos hacerlo por ley; al eliminar la cuenta, dejamos de '
                  'tratarla. Para solicitudes especiales escríbenos y responderemos a la brevedad.',
              children: [
                _buildBulletPoint(
                  'Acceder a la información personal que tenemos sobre ti.',
                ),
                _buildBulletPoint(
                  'Actualizar y corregir tus datos desde tu perfil o escribiéndonos.',
                ),
                _buildBulletPoint(
                  'Eliminar tu cuenta y sus datos: Perfil → Configuración → Eliminar cuenta.',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 8. Seguridad
            _buildPolicySection(
              icon: Icons.lock_rounded,
              title: '8. Seguridad',
              content:
                  'Protegemos tu información con medidas técnicas apropiadas. Todas las '
                  'comunicaciones entre la app y nuestros servidores viajan cifradas mediante '
                  'HTTPS/TLS, y tus contraseñas se almacenan hasheadas, es decir, nunca guardamos '
                  'tu contraseña en texto plano ni podemos leerla. Además, el acceso a los datos '
                  'está restringido solo al personal que lo necesita para operar el servicio.',
            ),

            const SizedBox(height: 16),

            // 9. Cambios y contacto
            _buildPolicySection(
              icon: Icons.update_rounded,
              title: '9. Cambios y contacto',
              content:
                  'Esta política puede actualizarse para reflejar mejoras en la app o cambios '
                  'legales; la fecha de vigencia siempre aparecerá al inicio. Si hicimos un cambio '
                  'importante, te avisaremos dentro de la app o por notificación antes de que aplique. '
                  'Si tienes preguntas sobre tu privacidad o quieres ejercer tus derechos, contáctanos:',
              children: [
                _buildContactInfo(
                  icon: Icons.email_rounded,
                  title: 'Correo electrónico',
                  value: AppConstants.supportEmail,
                ),
                const SizedBox(height: 12),
                _buildContactInfo(
                  icon: Icons.phone_rounded,
                  title: 'Teléfono / WhatsApp',
                  value: AppConstants.supportPhone,
                ),
                const SizedBox(height: 12),
                _buildContactInfo(
                  icon: Icons.language_rounded,
                  title: 'Sitio web',
                  value: 'www.saberplus.app',
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Aceptación
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warning),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.warning,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Aceptación de términos',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warningDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Al usar SaberPlus aceptas los términos de esta Política de Privacidad. '
                    'Si no estás de acuerdo con alguno de ellos, por favor no utilices la aplicación. '
                    'Estudiar es tu superpoder: cuidar tus datos es el nuestro.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.warningDark,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicySection({
    required IconData icon,
    required String title,
    required String content,
    List<Widget>? children,
  }) {
    return Container(
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
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
              height: 1.5,
            ),
          ),
          if (children != null) ...[
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 12),
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textTertiary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactInfo({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceClean,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: AppColors.textTertiary,
            size: 20,
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
