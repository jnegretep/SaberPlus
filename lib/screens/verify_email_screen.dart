// lib/screens/verify_email_screen.dart
// Saber+ - Pantalla de verificacion de email (enlace magico)
//
// Esta pantalla se muestra despues del registro. Le dice al usuario que
// revise su correo y haga clic en el enlace de confirmacion.
// Ya NO pide codigo de 6 digitos.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/env.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';
import '../core/animations/app_animations.dart';
import 'set_password_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final int userId; // Ahora es int
  final dynamic selectedImage;
  final String? selectedAvatarAsset;

  const VerifyEmailScreen({
    Key? key,
    required this.email,
    required this.userId,
    this.selectedImage,
    this.selectedAvatarAsset,
  }) : super(key: key);

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    );
    _scale = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.2, 1.0, curve: Curves.elasticOut),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  // ✅ Verificar si el correo ya fue verificado
  Future<void> _checkVerification() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${Env.apiBaseUrl}/check_verification.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'user_id': widget.userId}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['verified'] == true) {
          // ✅ Verificado: ir a crear contraseña
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => SetPasswordScreen(
                userId: widget.userId,
                email: widget.email,
                selectedImage: widget.selectedImage,
                selectedAvatarAsset: widget.selectedAvatarAsset,
              ),
            ),
          );
          return;
        }
      }
      // Si no verificado o error
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aún no has verificado tu correo. Revisa tu bandeja de entrada.'),
          backgroundColor: AppColors.errorDark,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al verificar: $e'),
          backgroundColor: AppColors.errorDark,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icono animado
                  FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: Container(
                        width: 100,
                        height: 100,
                        margin: const EdgeInsets.only(bottom: 32),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.mark_email_read_outlined,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ),
                  ),

                  // Titulo
                  FadeTransition(
                    opacity: _fade,
                    child: Text(
                      'Revisa tu correo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Descripcion
                  FadeTransition(
                    opacity: _fade,
                    child: Text(
                      'Hemos enviado un enlace de confirmacion a:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textTertiary,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Email destacado
                  FadeTransition(
                    opacity: _fade,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.2),
                        ),
                      ),
                      child: Text(
                        widget.email,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Card de instrucciones
                  FadeTransition(
                    opacity: _fade,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : AppColors.border,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.shadowSm,
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildInstructionStep(
                            icon: Icons.inbox_rounded,
                            text: 'Abre tu aplicacion de correo',
                            color: AppColors.primary,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 12),
                          _buildInstructionStep(
                            icon: Icons.mail_rounded,
                            text: 'Busca el correo de Saber+',
                            color: AppColors.accent,
                            isDark: isDark,
                          ),
                          const SizedBox(height: 12),
                          _buildInstructionStep(
                            icon: Icons.touch_app_rounded,
                            text: 'Haz clic en "Confirmar mi correo"',
                            color: AppColors.success,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Boton "Ya verifique mi correo" (con verificación)
                  FadeTransition(
                    opacity: _fade,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _checkVerification,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Ya verifique mi correo',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Boton volver
                  FadeTransition(
                    opacity: _fade,
                    child: TextButton(
                      onPressed: () => Nav.goLogin(context),
                      child: Text(
                        'Volver a inicio de sesion',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ),

                  // Nota
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _fade,
                    child: Text(
                      'El enlace expira en 24 horas.\n'
                      'Revisa tambien tu carpeta de spam.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textDisabled,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionStep({
    required IconData icon,
    required String text,
    required Color color,
    required bool isDark,
  }) {
    return Row(
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
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}