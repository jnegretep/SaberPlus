// set_password_screen.dart - Rediseñado con estilo consistente
import '../config/env.dart'; // ✅ Import necesario
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/constants/app_constants.dart';
import '../widgets/profile_avatar_widget.dart';
import 'dart:io';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';

class SetPasswordScreen extends StatefulWidget {
  final int userId;
  final String email;
  final File? selectedImage;
  final String? selectedAvatarAsset;
  final String? resetToken;

  const SetPasswordScreen({
    Key? key,
    required this.userId,
    required this.email,
    this.selectedImage,
    this.selectedAvatarAsset,
    this.resetToken,
  }) : super(key: key);

  @override
  State<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<SetPasswordScreen> {
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  bool _loading = false;

  // 👇 Estados para mostrar/ocultar contraseña
  bool _showPass = false;
  bool _showConfirm = false;

  // 👇 Estado para coincidencia en tiempo real
  String? _matchMessage;
  bool _passwordsMatch = false;
  String? resetToken;

  // 👇 Estado para fortaleza de contraseña
  double _passwordStrength = 0.0;
  String _strengthMessage = '';
  Color _strengthColor = AppColors.textDisabled;

  @override
  void initState() {
    super.initState();
    resetToken = widget.resetToken;

    _confirmCtrl.addListener(_checkPasswordsMatch);
    _passCtrl.addListener(() {
      _checkPasswordsMatch();
      _checkPasswordStrength();
    });
  }

  void _checkPasswordsMatch() {
    final pass = _passCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    if (confirm.isEmpty) {
      setState(() {
        _matchMessage = null;
        _passwordsMatch = false;
      });
      return;
    }
    if (pass == confirm) {
      setState(() {
        _matchMessage = "Las contraseñas coinciden";
        _passwordsMatch = true;
      });
    } else {
      setState(() {
        _matchMessage = "Las contraseñas no coinciden";
        _passwordsMatch = false;
      });
    }
  }

  void _checkPasswordStrength() {
    final password = _passCtrl.text;
    double strength = 0.0;
    String message = '';
    Color color = AppColors.textDisabled;

    if (password.isEmpty) {
      setState(() {
        _passwordStrength = 0.0;
        _strengthMessage = '';
        _strengthColor = color;
      });
      return;
    }

    // Verificar longitud
    if (password.length >= 8) strength += 0.25;

    // Verificar letras mayúsculas y minúsculas
    if (password.contains(RegExp(r'[A-Z]')) && password.contains(RegExp(r'[a-z]'))) {
      strength += 0.25;
    }

    // Verificar números
    if (password.contains(RegExp(r'[0-9]'))) strength += 0.25;

    // Verificar caracteres especiales
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) strength += 0.25;

    // Determinar mensaje y color
    if (strength < 0.5) {
      message = 'Débil';
      color = AppColors.error;
    } else if (strength < 0.75) {
      message = 'Media';
      color = AppColors.warning;
    } else {
      message = 'Fuerte';
      color = AppColors.successDark;
    }

    setState(() {
      _passwordStrength = strength;
      _strengthMessage = message;
      _strengthColor = color;
    });
  }

  Future<void> _setPassword() async {
    final pass = _passCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (pass.isEmpty || confirm.isEmpty) {
      _showSnack("Complete todos los campos", isError: true);
      return;
    }

    if (pass.length < 8) {
      _showSnack("La contraseña debe tener al menos 8 caracteres", isError: true);
      return;
    }

    if (pass != confirm) {
      _showSnack("Las contraseñas no coinciden", isError: true);
      return;
    }

    setState(() => _loading = true);

    try {
      // ✅ FIX: usar `${Env.apiBaseUrl}` en lugar de "Env.apiBaseUrl"
      final url = Uri.parse("${Env.apiBaseUrl}/set_password.php");

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'user_id': widget.userId,
          'email': widget.email,
          'password': pass,
          'reset_token': resetToken,
        }),
      );

      if (response.statusCode == 200 && response.body.trim().isEmpty) {
        const secureStorage = FlutterSecureStorage();
        await secureStorage.delete(key: AppConstants.keyJwt);
        await secureStorage.delete(key: AppConstants.keyRefreshToken);
        await secureStorage.delete(key: AppConstants.keyUser);
        _showSnack("Contraseña establecida con éxito", isError: false);
        Nav.goToLoginAndClearStack(context);
        return;
      }

      if (response.body.trim().isEmpty) {
        _showSnack("Respuesta vacía del servidor", isError: true);
        return;
      }

      final data = jsonDecode(response.body);
      if (data['status'] == 'ok') {
        const secureStorage = FlutterSecureStorage();
        await secureStorage.delete(key: AppConstants.keyJwt);
        await secureStorage.delete(key: AppConstants.keyRefreshToken);
        await secureStorage.delete(key: AppConstants.keyUser);
        _showSnack("Contraseña establecida con éxito", isError: false);
        Nav.goToLoginAndClearStack(context);
      } else {
        _showSnack(data['msg'] ?? 'Error al establecer la contraseña', isError: true);
      }
    } catch (e) {
      _showSnack("Error de conexión: $e", isError: true);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showSnack(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: AppColors.textOnPrimary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AppColors.errorDark : AppColors.successDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required bool showPassword,
    required VoidCallback onToggleVisibility,
    String? hintText,
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
                child: TextField(
                  controller: controller,
                  obscureText: !showPassword,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: hintText,
                    hintStyle: TextStyle(
                      color: AppColors.textDisabled,
                      fontSize: 15,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    isDense: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton(
                  onPressed: onToggleVisibility,
                  icon: Icon(
                    showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: AppColors.textTertiary,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              // 🔹 Header con gradiente y progreso
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
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Icono de candado
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.surface.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.lock_rounded,
                        color: AppColors.textOnPrimary,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Título
                    const Text(
                      'Establece tu contraseña',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Último paso para completar tu registro',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.textOnPrimarySubtle,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Progreso
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildProgressStep(number: 1, label: 'Datos', isActive: false),
                        Container(
                          width: 40,
                          height: 2,
                          color: AppColors.surface.withOpacity(0.5),
                        ),
                        _buildProgressStep(number: 2, label: 'Institucionales', isActive: false),
                        Container(
                          width: 40,
                          height: 2,
                          color: AppColors.surface.withOpacity(0.5),
                        ),
                        _buildProgressStep(number: 3, label: 'Contraseña', isActive: true),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // 🔹 Información de cuenta
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowSm,
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.border,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.border,
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: widget.selectedImage != null
                            ? Image.file(
                                widget.selectedImage!,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                              )
                            : widget.selectedAvatarAsset != null
                                ? Image.asset(
                                    widget.selectedAvatarAsset!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: AppColors.surfaceClean,
                                    child: Icon(
                                      Icons.person_rounded,
                                      size: 28,
                                      color: AppColors.textDisabled,
                                    ),
                                  ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Creando cuenta para',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.email,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Usuario: ${widget.userId}',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // 🔹 Formulario de contraseña
              Container(
                padding: const EdgeInsets.all(24),
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
                  children: [
                    // Nueva contraseña
                    _buildPasswordField(
                      label: 'Nueva contraseña',
                      controller: _passCtrl,
                      showPassword: _showPass,
                      onToggleVisibility: () {
                        setState(() => _showPass = !_showPass);
                      },
                      hintText: 'Mínimo 8 caracteres',
                    ),

                    const SizedBox(height: 20),

                    // Confirmar contraseña
                    _buildPasswordField(
                      label: 'Confirmar contraseña',
                      controller: _confirmCtrl,
                      showPassword: _showConfirm,
                      onToggleVisibility: () {
                        setState(() => _showConfirm = !_showConfirm);
                      },
                      hintText: 'Repite tu contraseña',
                    ),

                    // Indicador de fortaleza de contraseña
                    if (_passCtrl.text.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Seguridad de contraseña',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              Text(
                                _strengthMessage,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _strengthColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _passwordStrength,
                            backgroundColor: AppColors.border,
                            color: _strengthColor,
                            borderRadius: BorderRadius.circular(4),
                            minHeight: 6,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Incluye mayúsculas, números y caracteres especiales para mayor seguridad',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textDisabled,
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Mensaje de coincidencia
                    if (_matchMessage != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _passwordsMatch
                              ? AppColors.successLight
                              : AppColors.errorLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _passwordsMatch
                                ? AppColors.successDark
                                : AppColors.errorFg,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _passwordsMatch
                                  ? Icons.check_circle_rounded
                                  : Icons.error_outline_rounded,
                              color: _passwordsMatch
                                  ? AppColors.successDark
                                  : AppColors.errorDark,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _matchMessage!,
                                style: TextStyle(
                                  color: _passwordsMatch
                                      ? AppColors.successDeep
                                      : AppColors.errorDeep,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // Botón para establecer contraseña
                    SizedBox(
                      height: 52,
                      child: Material(
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: _loading || !_passwordsMatch ? null : _setPassword,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: _loading || !_passwordsMatch
                                  ? null
                                  : const LinearGradient(
                                      colors: [
                                        AppColors.successDark,
                                        AppColors.successFg
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: _loading || !_passwordsMatch
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: AppColors.successDark
                                            .withOpacity(0.3),
                                        blurRadius: 12,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                              color: _loading || !_passwordsMatch
                                  ? AppColors.textDisabled
                                  : null,
                            ),
                            child: Center(
                              child: _loading
                                  ? const CircularProgressIndicator(
                                      color: AppColors.textOnPrimary,
                                      strokeWidth: 2,
                                    )
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'COMPLETAR REGISTRO',
                                          style: TextStyle(
                                            color: _passwordsMatch
                                                ? AppColors.textOnPrimary
                                                : AppColors.textSubtle,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          Icons.check_circle_rounded,
                                          color: _passwordsMatch
                                              ? AppColors.textOnPrimary
                                              : AppColors.textSubtle,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Información de seguridad
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.warningBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.warningBorder,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.security_rounded,
                            color: AppColors.warningText,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Consejo de seguridad',
                                  style: TextStyle(
                                    color: AppColors.warningDark,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Usa una contraseña única que no hayas utilizado en otros servicios. Considera usar una combinación de letras, números y símbolos.',
                                  style: TextStyle(
                                    color: AppColors.warningText,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Footer
              Column(
                children: [
                  Text(
                    '¡Último paso completado!',
                    style: TextStyle(
                      color: AppColors.successDark,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'PrepSaber © 2024',
                    style: TextStyle(
                      color: AppColors.textDisabled,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressStep({
    required int number,
    required String label,
    required bool isActive,
  }) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? AppColors.textOnPrimary : AppColors.surface.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number.toString(),
              style: TextStyle(
                color: isActive ? AppColors.primary : AppColors.textOnPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textOnPrimary,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}