import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../widgets/global_scaffold.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';
import '../core/animations/shimmer_loading.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({Key? key}) : super(key: key);

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    final auth = Provider.of<AuthService>(context, listen: false);
    try {
      await auth.fetchProfile();
    } catch (e) {
      debugPrint('Error cargando perfil: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _buildFormField({
    required String label,
    required IconData icon,
    required String value,
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceClean,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.border,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                margin: const EdgeInsets.only(right: 12, left: 16),
                width: 48,
                child: Icon(
                  icon,
                  color: AppColors.textDisabled,
                  size: 20,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    value.isNotEmpty ? value : (hintText ?? 'No definido'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: value.isNotEmpty
                          ? AppColors.textSecondary
                          : AppColors.textDisabled,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final size = MediaQuery.of(context).size;

    return GlobalScaffold(
      currentIndex: 1,
      body: _loading
          ? _buildLoadingState()
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Encabezado
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryLight],
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
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
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
                            radius: 30,
                            backgroundColor: AppColors.surface,
                            backgroundImage: auth.avatarUrl != null
                                ? NetworkImage(auth.avatarUrl!)
                                : const AssetImage('assets/avatars/default.png')
                                    as ImageProvider,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Mi perfil',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textOnPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Consulta tu información personal',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textOnPrimary.withOpacity(0.8),
                                ),
                              ),
                              // Badge de rol
                              if (auth.tipoUsuario == 'profesor')
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.successDark.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: AppColors.successDark),
                                  ),
                                  child: Text(
                                    'PROFESOR',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.successDark,
                                      letterSpacing: 0.5,
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

                  // Información personal
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
                        const Text(
                          'Información personal',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Datos básicos de tu cuenta',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Column(
                          children: [
                            _buildFormField(
                              label: 'Nombre completo',
                              icon: Icons.person_outline_rounded,
                              value: auth.nombre ?? '',
                              hintText: 'No definido',
                            ),
                            const SizedBox(height: 16),
                            _buildFormField(
                              label: 'Teléfono',
                              icon: Icons.phone_rounded,
                              value: auth.user?['telefono'] ?? '',
                              hintText: 'No definido',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Información de ubicación
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
                        const Text(
                          'Ubicación',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Información de tu localización',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Column(
                          children: [
                            _buildFormField(
                              label: 'Departamento',
                              icon: Icons.map_rounded,
                              value: auth.departamento ?? '',
                              hintText: 'No definido',
                            ),
                            const SizedBox(height: 16),
                            _buildFormField(
                              label: 'Ciudad',
                              icon: Icons.location_city_rounded,
                              value: auth.ciudad ?? '',
                              hintText: 'No definido',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Información académica
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
                        const Text(
                          'Información académica',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Datos de tu institución educativa',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Column(
                          children: [
                            _buildFormField(
                              label: 'Colegio',
                              icon: Icons.school_rounded,
                              value: auth.colegio ?? '',
                              hintText: 'No definido',
                            ),
                            const SizedBox(height: 16),
                            _buildFormField(
                              label: 'Grado',
                              icon: Icons.grade_rounded,
                              value: auth.grado ?? '',
                              hintText: 'No definido',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 🔴 NUEVA SECCIÓN: Información de rol
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
                        const Text(
                          'Información de rol',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Datos de acceso y permisos en la plataforma',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Column(
                          children: [
                            _buildFormField(
                              label: 'Tipo de usuario',
                              icon: Icons.person_rounded,
                              value: auth.tipoUsuario?.toUpperCase() ?? 'ESTUDIANTE',
                              hintText: 'No definido',
                            ),
                            const SizedBox(height: 16),
                            _buildFormField(
                              label: 'Nivel de acceso',
                              icon: Icons.security_rounded,
                              value: auth.user?['access_level'] == 'premium'
                                  ? 'Premium'
                                  : (auth.user?['access_level'] == 'free'
                                      ? 'Gratuito'
                                      : 'Prueba'),
                              hintText: 'No disponible',
                            ),
                            const SizedBox(height: 16),
                            _buildFormField(
                              label: 'Usuario verificado',
                              icon: Icons.verified_rounded,
                              value: (auth.user?['email_verificado'] == true)
                                  ? 'Sí'
                                  : 'No (pendiente)',
                              hintText: 'No disponible',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Información de cuenta (no editable)
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
                        const Text(
                          'Información de cuenta',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Datos que no se pueden modificar',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Column(
                          children: [
                            _buildFormField(
                              label: 'Usuario',
                              icon: Icons.alternate_email_rounded,
                              value: auth.username ?? '',
                              hintText: 'No disponible',
                            ),
                            const SizedBox(height: 16),
                            _buildFormField(
                              label: 'Correo electrónico',
                              icon: Icons.email_rounded,
                              value: auth.user?['email'] ?? '',
                              hintText: 'No disponible',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Botones de acción
                  Column(
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          Nav.goEditProfile(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textOnPrimary,
                          minimumSize: Size(size.width, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                          shadowColor: Colors.transparent,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_rounded, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'Editar perfil completo',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          Nav.goChangePassword(context);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textTertiary,
                          minimumSize: Size(size.width, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_reset_rounded, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Cambiar contraseña',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Text(
            'Cargando perfil...',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}