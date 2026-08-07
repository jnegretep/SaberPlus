import '../config/env.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _success = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(email);
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();

    if (email.isEmpty) {
      _showSnack("Ingresa tu correo", isError: true);
      return;
    }
    if (!_isValidEmail(email)) {
      _showSnack("Correo inválido", isError: true);
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _success = false;
    });

    try {
      final url = Uri.parse(
          "Env.apiBaseUrl/forgot_password.php");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'email': email}),
      );

      final raw = response.body;

      if (raw.isEmpty) {
        _showSnack("Respuesta vacía del servidor", isError: true);
        return;
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        _showSnack("Respuesta inválida del servidor", isError: true);
        return;
      }

      if (response.statusCode == 200 && data['status'] == 'ok') {
        setState(() {
          _success = true;
          _loading = false;
        });

        // Navegar después de mostrar mensaje de éxito
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          Nav.goVerifyReset(context, email: email);
        });
      } else {
        final msg = data['msg']?.toString() ?? "Error inesperado";
        setState(() {
          _errorMessage = msg;
          _loading = false;
        });
        _showSnack(msg, isError: true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error de conexión: $e";
        _loading = false;
      });
      _showSnack("Error de conexión: $e", isError: true);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
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
                msg,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor:
            isError ? AppColors.errorDark : AppColors.successDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // 🔹 Header con gradiente - Igual que verify_email_screen
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
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
                    // Icono
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.surface.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.lock_reset_rounded,
                        color: AppColors.textOnPrimary,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Recuperar contraseña',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Te enviaremos un código a tu correo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textOnPrimarySubtle,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 🔹 Card principal - Igual que verify_email_screen
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
                child: Column(
                  children: [
                    // Campo de email
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Correo electrónico',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Ingresa el correo asociado a tu cuenta',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 14),
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
                              Padding(
                                padding: const EdgeInsets.only(left: 16),
                                child: Icon(
                                  Icons.email_rounded,
                                  color: AppColors.textTertiary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 16,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'ejemplo@correo.com',
                                    hintStyle: TextStyle(
                                      color: AppColors.textDisabled,
                                      fontSize: 16,
                                    ),
                                    contentPadding:
                                        EdgeInsets.symmetric(vertical: 14),
                                    isDense: true,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 16),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Mensaje de éxito
                    if (_success)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.successDark,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.successDark,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '¡Código enviado!',
                                    style: TextStyle(
                                      color: AppColors.successDeep,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Revisa tu correo ${_emailCtrl.text.trim()}',
                                    style: TextStyle(
                                      color: AppColors.successDeep
                                          .withOpacity(0.8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Mensaje de error
                    if (_errorMessage != null && !_success)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.errorLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.errorFg,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: AppColors.errorDark,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: AppColors.errorDeep,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (_errorMessage != null || _success)
                      const SizedBox(height: 20),

                    // Botón de enviar
                    SizedBox(
                      height: 48,
                      child: Material(
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: _loading
                              ? null
                              : _emailCtrl.text.trim().isNotEmpty &&
                                      _isValidEmail(_emailCtrl.text.trim())
                                  ? _sendCode
                                  : null,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: _loading
                                  ? null
                                  : const LinearGradient(
                                      colors: [
                                        AppColors.successDark,
                                        AppColors.successFg
                                      ],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: _loading
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: AppColors.successDark
                                            .withOpacity(0.3),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                              color: _loading
                                  ? AppColors.textDisabled
                                  : null,
                            ),
                            child: Center(
                              child: _loading
                                  ? const CircularProgressIndicator(
                                      color: AppColors.textOnPrimary,
                                      strokeWidth: 2,
                                    )
                                  : const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'ENVIAR CÓDIGO',
                                          style: TextStyle(
                                            color: AppColors.textOnPrimary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        SizedBox(width: 6),
                                        Icon(
                                          Icons.send_rounded,
                                          color: AppColors.textOnPrimary,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Información adicional
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.infoBorder,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: AppColors.sky,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Revisa tu bandeja de entrada y spam',
                                  style: TextStyle(
                                    color: AppColors.infoDark,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'El código puede tardar algunos minutos en llegar.',
                                  style: TextStyle(
                                    color: AppColors.infoDeeper,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Enlace para volver al login
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.arrow_back_rounded,
                              size: 16,
                              color: AppColors.textTertiary,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Volver al inicio de sesión',
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // Footer
              Text(
                'PrepSaber © 2024',
                style: TextStyle(
                  color: AppColors.textDisabled,
                  fontSize: 11,
                ),
              ),

              // Espacio final para evitar overflow
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}