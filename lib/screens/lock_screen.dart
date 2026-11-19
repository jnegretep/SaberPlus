// lib/screens/lock_screen.dart
// Saber+ v2.0 — Bloqueo biométrico local (app lock).
//
// Se muestra al abrir la app (o volver de segundo plano) cuando existe una
// sesión activa Y el usuario activó el desbloqueo biométrico en Perfil.
//
// Modelo de seguridad:
//   - La sesión del servidor la siguen gestionando el JWT + refresh normales.
//   - La biometría SOLO protege el acceso local a la interfaz; no es un
//     mecanismo de login ni guarda credenciales.
//   - Si la huella falla o se cancela: reintentar o cerrar sesión e ir al
//     login con contraseña.
//   - Si la sesión expiró mientras la app estuvo bloqueada, los
//     interceptores de DioClient existentes redirigen al login tras el
//     desbloqueo (la biometría nunca sustituye credenciales inexistentes).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/navigation.dart';
import '../core/theme/app_colors.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({Key? key}) : super(key: key);

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with SingleTickerProviderStateMixin {
  bool _authenticating = false;
  bool _failed = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    // Prompt automático al entrar a la pantalla.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _tryUnlock() async {
    if (_authenticating || !mounted) return;
    setState(() {
      _authenticating = true;
      _failed = false;
    });

    final ok = await BiometricService.authenticate(
      reason: 'Usa tu huella para desbloquear Saber+',
    );

    if (!mounted) return;
    if (ok) {
      // Desbloqueado: continuar hacia la app (reemplaza /lock del historial).
      // Profesor → panel docente; estudiante → dashboard.
      final auth = authServiceOf(context);
      if (auth.isProfesor) {
        Nav.goTeacher(context);
      } else {
        Nav.goDashboard(context);
      }
    } else {
      setState(() {
        _authenticating = false;
        _failed = true;
      });
    }
  }

  Future<void> _logoutToLogin() async {
    if (!mounted) return;
    final auth = authServiceOf(context);
    await auth.logout();
    if (!mounted) return;
    // Nav.goToLoginAndClearStack limpia el historial y va a /login.
    Nav.goToLoginAndClearStack(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.background;

    return PopScope(
      // No se puede "atrás" desde el bloqueo: la app está protegida.
      canPop: false,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Icono biométrico con pulso ──
                  ScaleTransition(
                    scale: Tween<double>(begin: 1.0, end: 1.12)
                        .animate(CurvedAnimation(
                      parent: _pulseController,
                      curve: Curves.easeInOut,
                    )),
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.4),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.fingerprint_rounded,
                        size: 58,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Saber+ está bloqueado',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Usa tu huella o reconocimiento facial\npara continuar',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  if (_failed && !_authenticating)
                    Text(
                      'No se pudo verificar tu identidad.\nInténtalo de nuevo o usa tu contraseña.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: AppColors.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 32),

                  // ── Botón reintentar ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _authenticating ? null : () => _tryUnlock(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      icon: _authenticating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.fingerprint_rounded),
                      label: Text(
                        _authenticating
                            ? 'Verificando...'
                            : 'Desbloquear con huella',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── Usar contraseña (cierra sesión y va al login) ──
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _authenticating ? null : () => _logoutToLogin(),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: const Icon(Icons.lock_outline_rounded, size: 20),
                      label: const Text(
                        'Usar mi contraseña',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
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
}

/// Obtiene el AuthService del contexto de forma segura.
AuthService authServiceOf(BuildContext context) => context.read<AuthService>();
