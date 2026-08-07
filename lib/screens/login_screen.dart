import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/notifications_api.dart';
import '../providers/notification_provider.dart';
import 'dashboard_screen.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';
import '../core/constants/app_constants.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _error;

  // Entrance animation
  late final AnimationController _entranceController;
  late final Animation<double> _logoFade;
  late final Animation<double> _formSlide;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();

    // Entrance animation
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoFade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    );
    _formSlide = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  static const _secureStorage = FlutterSecureStorage();

  Future<void> _loadSavedCredentials() async {
    final savedEmail = await _secureStorage.read(key: AppConstants.keySavedEmail);
    final remember = await _secureStorage.read(key: AppConstants.keyRememberMe);

    if (remember == 'true' && savedEmail != null) {
      // ✅ Verificar mounted antes de setState
      if (!mounted) return;
      setState(() {
        _emailCtrl.text = savedEmail;
        _rememberMe = true;
      });
    }
  }

  Future<void> _saveCredentials() async {
    if (_rememberMe) {
      // ✅ Solo guardar email (NUNCA la contraseña)
      await _secureStorage.write(key: AppConstants.keySavedEmail, value: _emailCtrl.text.trim());
      await _secureStorage.write(key: AppConstants.keyRememberMe, value: 'true');
    } else {
      // Eliminar solo las keys de credenciales, no todo el storage
      await _secureStorage.delete(key: AppConstants.keySavedEmail);
      await _secureStorage.delete(key: AppConstants.keyRememberMe);
    }
  }

  // ✅ MÉTODO _login COMPLETAMENTE CORREGIDO
  Future<void> _login(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthService>();

    // ✅ Verificar mounted antes de setState
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ok = await auth.login(
        _emailCtrl.text.trim(),
        _passCtrl.text,
      );

      // ✅ Verificar mounted antes de setState
      if (!mounted) return;
      setState(() => _loading = false);

      if (!ok) {
        if (!mounted) return;
        setState(() => _error = 'Credenciales inválidas');
        return;
      }

      await _saveCredentials();
      
      // Obtener perfil para asegurar datos completos
      final profile = await auth.fetchProfile();
      
      // ✅ Verificar mounted ANTES de cualquier navegación o setState
      if (!mounted) return;
      
      if (profile == null) {
        setState(() => _error = 'Error obteniendo perfil');
        return;
      }

      debugPrint("[LOGIN] Usuario tipo: ${auth.tipoUsuario}");
      
      // Navegar según tipo de usuario
      if (auth.isProfesor) {
        // ✅ Usar pushNamedAndRemoveUntil con mounted verificado
        if (!mounted) return;
        Nav.goTeacher(context);
      } else {
        // ✅ Usar pushNamedAndRemoveUntil con mounted verificado
        if (!mounted) return;
        Nav.goDashboard(context);
      }
      
    } catch (e) {
      // ✅ Verificar mounted antes de setState
      if (!mounted) return;
      setState(() => _loading = false);
      
      // Manejar usuario no verificado
      if (e.toString().contains('unverified') || 
          (e is Map && e['status'] == 'unverified')) {
        
        String userId = '';
        String email = _emailCtrl.text.trim();
        
        try {
          final errorData = jsonDecode(e.toString());
          userId = errorData['user_id']?.toString() ?? '';
          email = errorData['email']?.toString() ?? email;
        } catch (_) {}
        
        // ✅ Verificar mounted antes de navegar
        if (!mounted) return;
        Nav.goVerifyEmail(
          context,
          email: email,
          userId: userId.isNotEmpty ? userId : '0',
          selectedImage: null,
          selectedAvatarAsset: null,
        );
        return;
      }
      
      // ✅ Verificar mounted antes de setState
      if (!mounted) return;
      setState(() {
        _error = 'Error inesperado. Intenta nuevamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 🔹 Logo (animated entrance)
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.85, end: 1.0).animate(_logoFade),
                      child: Center(
                        child: Container(
                          width: 140,
                          height: 140,
                          margin: const EdgeInsets.only(top: 20),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
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
                          child: Center(
                            child: Image.asset(
                              'assets/images/saberplus.png',
                              height: 100,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 🔹 Card principal (slide entrance)
                  SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(_formSlide),
                    child: FadeTransition(
                      opacity: _formSlide,
                      child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.surface, AppColors.surfaceClean],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 12),
                        ),
                      ],
                      border: Border.all(
                        color: AppColors.border,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primary.withOpacity(0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.person_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Iniciar Sesión',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        const Text(
                          'Ingresa tus credenciales para continuar',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),

                        const SizedBox(height: 20),

                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInputField(
                                label: 'Correo electrónico',
                                icon: Icons.email_rounded,
                                controller: _emailCtrl,
                                hint: 'ejemplo@correo.com',
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Ingresa tu correo';
                                  }
                                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) {
                                    return 'Correo no válido';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 16),

                              _buildInputField(
                                label: 'Contraseña',
                                icon: Icons.lock_rounded,
                                controller: _passCtrl,
                                hint: '••••••••',
                                isPassword: true,
                                obscureText: _obscurePassword,
                                onToggleVisibility: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Ingresa tu contraseña';
                                  }
                                  if (v.length < 6) {
                                    return 'Mínimo 6 caracteres';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 10),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Transform.scale(
                                        scale: 0.8,
                                        child: Checkbox(
                                          value: _rememberMe,
                                          onChanged: (v) => setState(() => _rememberMe = v ?? false),
                                          activeColor: AppColors.primary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                      const Text(
                                        'Recordarme',
                                        style: TextStyle(
                                          color: AppColors.borderMedium,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  TextButton(
                                    onPressed: () => Nav.goForgotPassword(context),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text(
                                      '¿Olvidaste tu contraseña?',
                                      style: TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 6),

                              if (_error != null)
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.errorLight,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppColors.errorFg,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline_rounded,
                                        color: AppColors.errorDark,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: TextStyle(
                                            color: AppColors.errorDeepDark,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              const SizedBox(height: 20),

                              SizedBox(
                                height: 48,
                                child: Material(
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    onTap: _loading ? null : () => _login(context),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: _loading
                                            ? null
                                            : const LinearGradient(
                                                colors: [AppColors.primary, AppColors.primaryLight],
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                              ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: _loading
                                            ? null
                                            : [
                                                BoxShadow(
                                                  color: AppColors.primary
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
                                                    'INICIAR SESIÓN',
                                                    style: TextStyle(
                                                      color: AppColors.textOnPrimary,
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 14,
                                                      letterSpacing: 0.3,
                                                    ),
                                                  ),
                                                  SizedBox(width: 6),
                                                  Icon(
                                                    Icons.arrow_forward_rounded,
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

                              const SizedBox(height: 24),

                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: AppColors.border,
                                      thickness: 1,
                                    ),
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 10),
                                    child: Text(
                                      'O continuar con',
                                      style: TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: AppColors.border,
                                      thickness: 1,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              SizedBox(
                                height: 46,
                                child: OutlinedButton(
                                  onPressed: () {},
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: AppColors.surface,
                                    foregroundColor: AppColors.textSecondary,
                                    side: BorderSide(
                                      color: AppColors.border,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Image.asset(
                                        'assets/images/google.png',
                                        height: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      const Text(
                                        'Continuar con Google',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 24),

                              Center(
                                child: GestureDetector(
                                  onTap: () =>
                                      Nav.goRegisterStep1(context),
                                  child: RichText(
                                    text: const TextSpan(
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textTertiary,
                                      ),
                                      children: [
                                        TextSpan(text: '¿Aún no tienes cuenta? '),
                                        TextSpan(
                                          text: 'Regístrate',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  Text(
                    'PrepSaber © 2024',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textDisabled,
                      fontSize: 11,
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
    TextInputType keyboardType = TextInputType.text,
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
            color: AppColors.surfaceClean,
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
                  icon,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  validator: validator,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: AppColors.textDisabled,
                      fontSize: 15,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    isDense: true,
                  ),
                ),
              ),
              if (isPassword && onToggleVisibility != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: IconButton(
                    onPressed: onToggleVisibility,
                    icon: Icon(
                      obscureText
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
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
}