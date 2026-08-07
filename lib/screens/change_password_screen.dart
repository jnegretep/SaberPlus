import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';
import '../config/env.dart';
import '../widgets/global_scaffold.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/app_logger.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({Key? key}) : super(key: key);

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _saving = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  
  late String _baseUrl;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthService>(context, listen: false);
    _baseUrl = Env.apiBaseUrl;
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _saving = true);
    
    final auth = Provider.of<AuthService>(context, listen: false);
    
    final body = {
      "current_password": _currentPasswordController.text.trim(),
      "new_password": _newPasswordController.text.trim(),
      "confirm_password": _confirmPasswordController.text.trim(),
    };

try {
  final url = Uri.parse("$_baseUrl/change_password.php");
  final response = await http.post(
    url,
    headers: {
      "Content-Type": "application/json",
      "Authorization": "Bearer ${auth.token}"
    },
    body: jsonEncode(body),
  );

  AppLogger.d('HTTP STATUS: ${response.statusCode}');
  AppLogger.d("RAW RESPONSE: '${response.body}'");

  // ✅ CASO 1: Backend respondió 200 pero sin cuerpo (tu caso actual)
  if (response.statusCode == 200 && response.body.trim().isEmpty) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Contraseña cambiada exitosamente. Vuelve a iniciar sesión.',
          style: TextStyle(color: AppColors.textOnPrimary),
        ),
        backgroundColor: AppColors.successDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

    // 🔐 Cerrar sesión y forzar re-login
    await auth.logout();

    if (!mounted) return;

    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
    return;
  }

  // ✅ CASO 2: Backend sí devuelve JSON válido
  if (response.body.isNotEmpty) {
    final data = jsonDecode(response.body);

    if (data['status'] == 'ok') {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Contraseña cambiada exitosamente. Vuelve a iniciar sesión.',
            style: TextStyle(color: AppColors.textOnPrimary),
          ),
          backgroundColor: AppColors.successDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

      // 🔐 Cerrar sesión y forzar re-login
      await auth.logout();

      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data['msg'] ?? "Error al cambiar contraseña",
            style: TextStyle(color: AppColors.textOnPrimary),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }
} catch (e) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        "Error de conexión: $e",
        style: TextStyle(color: AppColors.textOnPrimary),
      ),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}
 finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required bool obscureText,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.borderDark,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.border,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Icon(
                  Icons.lock_rounded,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  obscureText: obscureText,
                  validator: validator,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Ingresa tu contraseña',
                    hintStyle: TextStyle(
                      color: AppColors.textDisabled,
                      fontSize: 15,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                onPressed: onToggle,
                icon: Icon(
                  obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ],
    );
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Este campo es obligatorio';
    }
    if (value.length < 6) {
      return 'Mínimo 6 caracteres';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Este campo es obligatorio';
    }
    if (value != _newPasswordController.text) {
      return 'Las contraseñas no coinciden';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return GlobalScaffold(
      currentIndex: 1,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
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
                child: Column(
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.textOnPrimary, width: 2),
                      ),
                      child: Icon(
                        Icons.lock_reset_rounded,
                        color: AppColors.textOnPrimary,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Cambiar contraseña',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Actualiza tu contraseña de acceso',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textOnPrimarySubtle,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Información de seguridad
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
                  border: Border.all(
                    color: AppColors.border,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Seguridad',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Protege tu cuenta con una nueva contraseña',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    Column(
                      children: [
                        _buildPasswordField(
                          label: 'Contraseña actual',
                          controller: _currentPasswordController,
                          obscureText: _obscureCurrent,
                          onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
                          validator: _validatePassword,
                        ),
                        const SizedBox(height: 16),
                        _buildPasswordField(
                          label: 'Nueva contraseña',
                          controller: _newPasswordController,
                          obscureText: _obscureNew,
                          onToggle: () => setState(() => _obscureNew = !_obscureNew),
                          validator: _validatePassword,
                        ),
                        const SizedBox(height: 16),
                        _buildPasswordField(
                          label: 'Confirmar nueva contraseña',
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          validator: _validateConfirmPassword,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Recomendaciones
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.infoBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.infoBorder,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.security_rounded,
                      color: AppColors.sky,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recomendaciones de seguridad',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.infoDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '• Usa al menos 6 caracteres\n• Combina letras, números y símbolos\n• No uses contraseñas obvias\n• Cambia tu contraseña regularmente',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.infoDark.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Botones de acción
              Column(
                children: [
                  _saving
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    AppColors.textOnPrimary),
                              ),
                            ),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: _changePassword,
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
                              Icon(Icons.check_circle_rounded, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'Cambiar contraseña',
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
                    onPressed: () => Navigator.pop(context),
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
                        Icon(Icons.arrow_back_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Volver al perfil',
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
      ),
    );
  }
}