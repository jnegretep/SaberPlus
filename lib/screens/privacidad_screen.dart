import 'package:flutter/material.dart';
import '../widgets/global_scaffold.dart';
import '../core/theme/app_colors.dart';

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
                        child: Icon(
                          Icons.security_rounded,
                          color: AppColors.textOnPrimary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Políticas de Privacidad',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textOnPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tu privacidad es nuestra prioridad',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.surface.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                        Icon(
                          Icons.update_rounded,
                          size: 18,
                          color: AppColors.textOnPrimarySubtle,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Última actualización: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textOnPrimarySubtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Introducción
            _buildPolicySection(
              icon: Icons.info_outline_rounded,
              title: 'Introducción',
              content:
                  'PrepSaber está comprometido con la protección de tu privacidad y datos personales. '
                  'Esta política describe cómo recopilamos, utilizamos, almacenamos y protegemos la información '
                  'que nos proporcionas cuando utilizas nuestra aplicación móvil y servicios relacionados.',
            ),

            const SizedBox(height: 16),

            // Información que recopilamos
            _buildPolicySection(
              icon: Icons.data_usage_rounded,
              title: 'Información que recopilamos',
              content:
                  'Recopilamos información personal que nos proporcionas directamente, así como información '
                  'generada automáticamente durante el uso de la aplicación.',
              children: [
                _buildBulletPoint(
                  'Información personal: Nombre completo, dirección de correo electrónico, '
                  'número de teléfono, institución educativa y grado académico.',
                ),
                _buildBulletPoint(
                  'Datos académicos: Resultados de simulacros, progreso de aprendizaje, '
                  'áreas de fortaleza y áreas por mejorar.',
                ),
                _buildBulletPoint(
                  'Datos técnicos: Dirección IP, tipo de dispositivo, sistema operativo, '
                  'versión de la aplicación y registros de uso.',
                ),
                _buildBulletPoint(
                  'Datos de ubicación: Ciudad, departamento y colegio (solo para fines estadísticos '
                  'y de personalización del contenido educativo).',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Uso de la información
            _buildPolicySection(
              icon: Icons.verified_user_rounded,
              title: 'Cómo utilizamos tu información',
              content:
                  'Utilizamos la información recopilada para los siguientes fines:',
              children: [
                _buildBulletPoint(
                  'Proporcionar y mejorar nuestros servicios educativos.',
                ),
                _buildBulletPoint(
                  'Personalizar tu experiencia de aprendizaje según tu progreso y necesidades.',
                ),
                _buildBulletPoint(
                  'Enviar actualizaciones sobre nuevos simulacros, contenido educativo y mejoras.',
                ),
                _buildBulletPoint(
                  'Realizar análisis estadísticos para mejorar la calidad de nuestros servicios.',
                ),
                _buildBulletPoint(
                  'Cumplir con obligaciones legales y regulatorias.',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Compartición de información
            _buildPolicySection(
              icon: Icons.share_rounded,
              title: 'Compartición de información',
              content:
                  'No vendemos ni alquilamos tu información personal a terceros. Compartimos información solo en los siguientes casos:',
              children: [
                _buildBulletPoint(
                  'Con proveedores de servicios que nos ayudan a operar la aplicación '
                  '(como hosting, análisis de datos y servicios de notificación).',
                ),
                _buildBulletPoint(
                  'Con tu institución educativa para fines de seguimiento académico, '
                  'cuando así lo autorices.',
                ),
                _buildBulletPoint(
                  'Cuando sea requerido por ley, orden judicial o proceso legal.',
                ),
                _buildBulletPoint(
                  'En caso de fusión, adquisición o venta de activos, previa notificación.',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Seguridad de datos
            _buildPolicySection(
              icon: Icons.lock_rounded,
              title: 'Seguridad de los datos',
              content:
                  'Implementamos medidas de seguridad técnicas y organizativas para proteger tu información:',
              children: [
                _buildBulletPoint(
                  'Encriptación de datos en tránsito usando protocolos TLS/SSL.',
                ),
                _buildBulletPoint(
                  'Almacenamiento seguro en servidores con medidas de protección física y lógica.',
                ),
                _buildBulletPoint(
                  'Acceso restringido solo a personal autorizado con necesidad de conocer.',
                ),
                _buildBulletPoint(
                  'Monitoreo continuo para detectar y prevenir accesos no autorizados.',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Tus derechos
            _buildPolicySection(
              icon: Icons.gavel_rounded,
              title: 'Tus derechos',
              content:
                  'Como usuario, tienes los siguientes derechos sobre tus datos personales:',
              children: [
                _buildBulletPoint(
                  'Acceder a la información personal que tenemos sobre ti.',
                ),
                _buildBulletPoint(
                  'Solicitar la corrección de datos inexactos o incompletos.',
                ),
                _buildBulletPoint(
                  'Solicitar la eliminación de tus datos personales (derecho al olvido).',
                ),
                _buildBulletPoint(
                  'Oponerte al procesamiento de tus datos para fines específicos.',
                ),
                _buildBulletPoint(
                  'Solicitar la portabilidad de tus datos a otro proveedor.',
                ),
                _buildBulletPoint(
                  'Retirar tu consentimiento en cualquier momento.',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Retención de datos
            _buildPolicySection(
              icon: Icons.schedule_rounded,
              title: 'Retención de datos',
              content:
                  'Conservamos tu información personal durante el tiempo necesario para cumplir con los fines descritos en esta política, a menos que la ley requiera o permita un período de retención más largo. '
                  'Los datos académicos se conservan durante 5 años para fines de seguimiento educativo.',
            ),

            const SizedBox(height: 16),

            // Contacto
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
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.successDark.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.contact_support_rounded,
                          color: AppColors.successDark,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Contacto',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Si tienes preguntas, comentarios o preocupaciones sobre esta Política de Privacidad, '
                    'o si deseas ejercer tus derechos sobre tus datos personales, puedes contactarnos a través de:',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textTertiary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildContactInfo(
                    icon: Icons.email_rounded,
                    title: 'Correo electrónico',
                    value: 'privacidad@prepsaber.com',
                  ),
                  const SizedBox(height: 12),
                  _buildContactInfo(
                    icon: Icons.phone_rounded,
                    title: 'Teléfono',
                    value: '+57 315 000 0000',
                  ),
                  const SizedBox(height: 12),
                  _buildContactInfo(
                    icon: Icons.language_rounded,
                    title: 'Sitio web',
                    value: 'www.prepsaber.com',
                  ),
                  const SizedBox(height: 12),
                  _buildContactInfo(
                    icon: Icons.location_on_rounded,
                    title: 'Dirección',
                    value: 'Calle 123 #45-67, Medellín, Colombia',
                  ),
                ],
              ),
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
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
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
                    'Al utilizar PrepSaber, aceptas los términos de esta Política de Privacidad. '
                    'Si no estás de acuerdo con alguno de estos términos, por favor no utilices nuestra aplicación.',
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
                  style: TextStyle(
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
            style: TextStyle(
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
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
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
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
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