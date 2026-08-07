import '../config/env.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';

class VerifyResetPasswordScreen extends StatefulWidget {
  final String email;
  
  const VerifyResetPasswordScreen({
    Key? key, 
    required this.email
  }) : super(key: key);

  @override
  State<VerifyResetPasswordScreen> createState() => _VerifyResetPasswordScreenState();
}

class _VerifyResetPasswordScreenState extends State<VerifyResetPasswordScreen> {
  final TextEditingController _tokenCtrl = TextEditingController();
  bool _loading = false;
  bool _verifying = false;
  String? _errorMessage;
  
  // Temporizador para reenvío
  int _resendCooldown = 0;
  bool _canResend = true;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _startCooldownTimer();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _startCooldownTimer() {
    _resendCooldown = 60; // 60 segundos de cooldown
    _canResend = false;
    
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
        setState(() => _canResend = true);
      }
    });
  }

  Future<void> _verify() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      _showSnack("Ingresa el código de verificación", isError: true);
      return;
    }

    if (token.length != 6) {
      _showSnack("El código debe tener 6 dígitos", isError: true);
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final url = Uri.parse('${Env.apiBaseUrl}/verify_reset_code.php?token=$token');
      
      final response = await http.get(url);

      final raw = response.body.trim();
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

      if (data['status'] == 'ok' && data['userId'] != null) {
        if (!mounted) return;
        
        _showSnack("Código verificado exitosamente", isError: false);
        
        // Navegar a la pantalla de restablecimiento
        Future.delayed(const Duration(milliseconds: 500), () {
          Nav.goResetPassword(
            context,
            userId: data['userId'] as int,
            email: widget.email,
            resetToken: token,
          );
        });
      } else {
        final errorMsg = data['msg']?.toString() ?? "Código inválido";
        setState(() => _errorMessage = errorMsg);
        _showSnack(errorMsg, isError: true);
      }
    } catch (e) {
      final errorMsg = "Error de conexión: $e";
      setState(() => _errorMessage = errorMsg);
      _showSnack(errorMsg, isError: true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resendCode() async {
    if (!_canResend || _verifying) return;
    
    setState(() => _verifying = true);
    
    try {
      final url = Uri.parse(
        "${Env.apiBaseUrl}/resend_reset_code.php",
      );
      
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'email': widget.email}),
      );

      final data = jsonDecode(response.body);
      
      if (data['status'] == 'ok') {
        _showSnack("Código reenviado exitosamente", isError: false);
        _startCooldownTimer();
      } else {
        _showSnack(data['msg'] ?? "Error al reenviar", isError: true);
      }
    } catch (e) {
      _showSnack("Error de conexión: $e", isError: true);
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
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
        backgroundColor: isError ? AppColors.errorDark : AppColors.successDark,
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
                        Icons.verified_user_rounded,
                        color: AppColors.textOnPrimary,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Verificar código',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Ingresa el código de 6 dígitos',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textOnPrimarySubtle,
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Email destino
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.surface.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.email_rounded,
                            color: AppColors.textOnPrimary,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.email,
                            style: TextStyle(
                              color: AppColors.textOnPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
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
                    // Email destino (en card)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceClean,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primaryLight.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              Icons.email_rounded,
                              color: AppColors.primaryLight,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Correo de destino',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.email,
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
                    ),

                    const SizedBox(height: 24),

                    // Campo de código
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Código de verificación',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Ingresa el código de 6 dígitos que recibiste',
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
                                  Icons.vpn_key_rounded,
                                  color: AppColors.textTertiary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _tokenCtrl,
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 6,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLength: 6,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    counterText: '',
                                    border: InputBorder.none,
                                    hintText: '000000',
                                    hintStyle: TextStyle(
                                      color: AppColors.textSubtle,
                                      fontSize: 22,
                                      letterSpacing: 6,
                                    ),
                                    contentPadding: EdgeInsets.symmetric(vertical: 14),
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

                    // Mensaje de error
                    if (_errorMessage != null)
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

                    if (_errorMessage != null) const SizedBox(height: 20),

                    // Botón de verificación
                    SizedBox(
                      height: 48,
                      child: Material(
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: _loading ? null : () {
                            if (_tokenCtrl.text.trim().isNotEmpty) {
                              _verify();
                            }
                          },
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
                                          'VERIFICAR CÓDIGO',
                                          style: TextStyle(
                                            color: AppColors.textOnPrimary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        SizedBox(width: 6),
                                        Icon(
                                          Icons.check_circle_rounded,
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

                    // Botón para reenviar código
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      children: [
                        Text(
                          '¿No recibiste el código?',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 13,
                          ),
                        ),
                        GestureDetector(
                          onTap: _canResend && !_verifying ? _resendCode : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: !_canResend || _verifying
                                  ? AppColors.border
                                  : AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: !_canResend || _verifying
                                    ? AppColors.textSubtle
                                    : AppColors.primary.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  color: !_canResend || _verifying
                                      ? AppColors.textDisabled
                                      : AppColors.primary,
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _verifying
                                      ? 'Enviando...'
                                      : !_canResend
                                          ? 'Reenviar en $_resendCooldown'
                                          : 'Reenviar código',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: !_canResend || _verifying
                                        ? AppColors.textDisabled
                                        : AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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

                    const SizedBox(height: 20),

                    // Enlace para volver
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
                              'Volver a recuperar contraseña',
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