// lib/screens/verify_email_screen.dart
// Saber+ - Pantalla de verificacion de email (codigo de 6 digitos)
// ✅ FASE 2: Volvio a codigos de 6 digitos (no enlace magico)
// ✅ FASE 2.4: Navega a set_password (no login) tras verificar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../config/env.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;


class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final String userId;
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

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final TextEditingController _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _resending = false;
  int _resendCooldown = 0;
  int _attempts = 0;
  static const int _maxAttempts = 5;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 60);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _resendCooldown > 0) {
        setState(() => _resendCooldown--);
        if (_resendCooldown > 0) _startCooldown();
      }
    });
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      _showSnack("Ingresa el codigo de verificacion", isError: true);
      return;
    }
    if (code.length != 6) {
      _showSnack("El codigo debe tener 6 digitos", isError: true);
      return;
    }
    if (_attempts >= _maxAttempts) {
      _showSnack("Demasiados intentos. Solicita un nuevo codigo.", isError: true);
      return;
    }

    setState(() => _loading = true);
    _attempts++;

    try {
      final url = Uri.parse('${Env.apiBaseUrl}/verify_email.php?token=$code');
      final response = await http.get(url);

      if (response.body.trim().isEmpty) {
        _showSnack("Respuesta vacia del servidor", isError: true);
        return;
      }

      final data = jsonDecode(response.body);
      if (data['status'] == 'ok') {
        if (!mounted) return;
        _showSnack("Correo verificado!", isError: false);

        // ✅ FIX FASE 2.4: navegar a set_password en vez de login.
        // ANTES: Nav.goLogin(context) → usuario sin contraseña, no puede entrar.
        // AHORA: pushReplacement a /register/set-password con todos los datos
        // (userId, email, avatar) para que set_password_screen complete el
        // paso 3 del registro (crear contraseña + sincronizar con Moodle).
        //
        // Si el backend informa hasPassword=true (verificación repetida de
        // un usuario que ya tenía contraseña), no lo forzamos a re-crearla:
        // va directo a login.
        final hasPassword = data['hasPassword'] == true;

        // userId puede venir como int (JSON estándar) o String. Convertir
        // con defensa antes de pasar al router.
        final rawUid = data['userId'] ?? widget.userId;
        final uid = rawUid is int ? rawUid : int.tryParse(rawUid.toString());

        if (uid == null || uid <= 0) {
          // Fallback defensivo: nunca debería pasar (backend siempre lo envía),
          // pero si pasa, mejor login que crash.
          Nav.goLogin(context);
          return;
        }

        if (hasPassword) {
          // Ya tenía contraseña → login.
          Nav.goLogin(context);
          return;
        }

        // Flujo normal: crear contraseña (paso 3 del registro).
        context.pushReplacement('/register/set-password', extra: {
          'userId': uid,                       // int — coincide con SetPasswordScreen.userId
          'email': widget.email,
          'selectedImage': widget.selectedImage,
          'selectedAvatarAsset': widget.selectedAvatarAsset,
        });
      } else {
        _showSnack(data['msg'] ?? 'Codigo invalido', isError: true);
      }
    } catch (e) {
      _showSnack("Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _resending) return;

    setState(() => _resending = true);

    try {
      final url = Uri.parse('${Env.apiBaseUrl}/resend_verification.php');
      final response = await http.post(url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': widget.userId.toString(),  // backend acepta int o String, .toString() evita type drift
          'email': widget.email,
        }),
      );

      if (response.body.trim().isNotEmpty) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'ok') {
          _showSnack("Nuevo codigo enviado", isError: false);
          _startCooldown();
          _attempts = 0;
        } else {
          _showSnack(data['msg'] ?? 'Error al reenviar', isError: true);
        }
      }
    } catch (e) {
      _showSnack("Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Nav.goLogin(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // Icono
              Container(
                width: 80, height: 80,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))],
                ),
                child: const Icon(Icons.mark_email_read_outlined, color: Colors.white, size: 40),
              ),
              // Titulo
              const Text('Verifica tu correo', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              // Email
              Text('Enviamos un codigo de 6 digitos a:', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textTertiary)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Text(widget.email, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
              const SizedBox(height: 32),
              // Input de codigo
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 12),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '000000',
                  hintStyle: TextStyle(fontSize: 28, letterSpacing: 12, color: AppColors.textDisabled),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                ),
              ),
              const SizedBox(height: 8),
              // Intentos restantes
              if (_attempts > 0)
                Text('${_maxAttempts - _attempts} intentos restantes', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: _attempts >= 3 ? AppColors.error : AppColors.textTertiary)),
              const SizedBox(height: 24),
              // Boton verificar
              ElevatedButton(
                onPressed: _loading ? null : _verify,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0,
                ),
                child: _loading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Verificar codigo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 16),
              // Reenviar
              TextButton(
                onPressed: _resendCooldown > 0 || _resending ? null : _resend,
                child: _resending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_resendCooldown > 0 ? 'Reenviar en ${_resendCooldown}s' : 'Reenviar codigo',
                      style: TextStyle(fontSize: 14, color: _resendCooldown > 0 ? AppColors.textDisabled : AppColors.primary, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 24),
              // Info
              Text('El codigo expira en 1 hora.\nRevisa tu carpeta de spam.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textDisabled, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}