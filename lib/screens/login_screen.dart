import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/notifications_api.dart';
import '../services/google_auth_service.dart';
import '../services/biometric_service.dart';
import '../services/analytics_service.dart';
import '../providers/notification_provider.dart';
import 'dashboard_screen.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/app_logger.dart';

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

  // ✅ FIX #4: estado para Google Sign-In
  bool _loadingGoogle = false;

  // ✅ FIX #5: estado para login biométrico
  bool _biometricReady = false;       // si el dispositivo soporta biometría
  bool _biometricEnabled = false;     // si el usuario ya la activó previamente
  String? _biometricEmail;            // email asociado (para mostrar en UI)
  bool _loadingBiometric = false;

  // Entrance animation
  late final AnimationController _entranceController;
  late final Animation<double> _logoFade;
  late final Animation<double> _formSlide;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _checkBiometricAvailability();   // ✅ FIX #5

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

  // ✅ FIX #5: verifica si el dispositivo soporta biometría y si ya está activada
  Future<void> _checkBiometricAvailability() async {
    final auth = context.read<AuthService>();
    final support = await BiometricService.checkSupport();
    final enabled = await auth.isBiometricEnabled();
    final email = await auth.getBiometricEmail();

    if (!mounted) return;
    setState(() {
      _biometricReady = support == BiometricSupport.ready;
      _biometricEnabled = enabled && _biometricReady;
      _biometricEmail = email;
    });

    AppLogger.d('Biometría: ready=$_biometricReady, enabled=$_biometricEnabled, email=$_biometricEmail');
  }

  // ✅ FIX #4: método para iniciar sesión con Google
  Future<void> _signInWithGoogle() async {
    final auth = context.read<AuthService>();

    setState(() {
      _loadingGoogle = true;
      _error = null;
    });

    try {
      final result = await auth.loginWithGoogle();

      if (!mounted) return;
      setState(() => _loadingGoogle = false);

      // Usuario canceló el flujo de Google
      if (!result.success) {
        if (result.errorMessage == 'cancelled') return; // silencioso
        setState(() => _error = result.errorMessage ?? 'Error con Google');
        return;
      }

      // Usuario nuevo → llevar al step2 con datos precargados
      if (result.isNewUser) {
        if (!mounted) return;
        AnalyticsService.logSignUp(method: 'google');
        // Usar context.push para mantener el contexto y pasar los datos extra
        // El step2 completará el registro con departamento, ciudad, colegio, etc.
        Nav.goRegisterStep2(
          context,
          nombre: result.displayName ?? '',
          email: result.email ?? '',
          telefono: '',
          username: (result.email ?? '').split('@').first,
        );
        return;
      }

      // Usuario existente → el redirect del GoRouter lo lleva al dashboard
      AnalyticsService.logLogin(method: 'google');
      if (auth.isProfesor) {
        Nav.goTeacher(context);
      } else {
        Nav.goDashboard(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingGoogle = false;
        _error = 'Error inesperado con Google: $e';
      });
    }
  }

  // ✅ FIX #5: método para login con huella
  Future<void> _loginWithBiometric() async {
    final auth = context.read<AuthService>();

    // Si el usuario aún no ha activado la biometría, mostrar diálogo explicativo
    if (!_biometricEnabled) {
      _showBiometricSetupDialog();
      return;
    }

    setState(() {
      _loadingBiometric = true;
      _error = null;
    });

    try {
      // 1. Mostrar el prompt nativo de huella/rostro
      final biometricOk = await BiometricService.authenticate(
        reason: 'Autentícate para ingresar a Saber+ como $_biometricEmail',
      );

      if (!biometricOk) {
        if (!mounted) return;
        setState(() {
          _loadingBiometric = false;
          _error = 'Autenticación biométrica cancelada o fallida';
        });
        return;
      }

      // 2. Si la huella es válida, hacer el refresh del token
      final ok = await auth.loginWithBiometric();

      if (!mounted) return;
      setState(() => _loadingBiometric = false);

      if (!ok) {
        setState(() => _error = 'Tu sesión biométrica expiró. Inicia sesión con tus credenciales.');
        // Desactivar biometría si falla para que el usuario re-login
        await auth.disableBiometricLogin();
        if (!mounted) return;
        setState(() {
          _biometricEnabled = false;
        });
        return;
      }

      // 3. ¡Login exitoso! El redirect del router lleva al dashboard
      if (auth.isProfesor) {
        Nav.goTeacher(context);
      } else {
        Nav.goDashboard(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBiometric = false;
        _error = 'Error: $e';
      });
    }
  }

  /// ✅ FIX #5: Diálogo explicativo cuando el usuario pulsa "Configurar huella"
  /// pero aún no ha iniciado sesión. Le explica que primero debe loguearse
  /// normalmente y luego activar la biometría desde su perfil.
  void _showBiometricSetupDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.fingerprint_rounded, color: AppColors.primary, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Login por huella',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: const Text(
          'Para activar el ingreso con huella:\n\n'
          '1. Inicia sesión con tu correo y contraseña.\n'
          '2. Ve a "Más" → "Configuración".\n'
          '3. Activa la opción "Login por huella".\n\n'
          'A partir de ese momento, podrás ingresar a Saber+ usando tu huella '
          'sin escribir tu contraseña.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
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

  // ✅ MÉTODO _login — Versión simplificada y robusta
  // El redirect del GoRouter (configurado en app_router.dart con refreshListenable)
  // se encarga automáticamente de llevar al usuario al dashboard o teacher dashboard
  // cuando el estado de auth cambia. Solo necesitamos disparar el login.
  Future<void> _login(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthService>();

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

      if (!mounted) return;
      setState(() => _loading = false);

      if (!ok) {
        if (!mounted) return;
        setState(() => _error = 'Credenciales inválidas');
        AnalyticsService.logLogin(method: 'password_failed');
        return;
      }

      // ✅ v1.6.0: analítica de login exitoso
      AnalyticsService.logLogin(method: 'password');

      await _saveCredentials();

      // Obtener perfil para asegurar datos completos
      final profile = await auth.fetchProfile();

      if (!mounted) return;

      if (profile == null) {
        setState(() => _error = 'Error obteniendo perfil');
        return;
      }

      debugPrint("[LOGIN] Usuario tipo: ${auth.tipoUsuario}");

      // ✅ FIX #1: El redirect del GoRouter se encarga de la navegación
      // automáticamente cuando notifyListeners() se disparó en auth.login()
      // y auth.fetchProfile(). Solo necesitamos forzar la navegación al destino
      // correcto usando context.go() para limpiar el stack.
      if (auth.isProfesor) {
        Nav.goTeacher(context);
      } else {
        Nav.goDashboard(context);
      }
    } catch (e) {
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

                              // ✅ FIX #4: Botón de Google conectado al servicio
                              SizedBox(
                                height: 46,
                                child: OutlinedButton(
                                  onPressed: _loadingGoogle || _loading
                                      ? null
                                      : _signInWithGoogle,
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
                                  child: _loadingGoogle
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.primary,
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
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

                              // ✅ FIX #5: Botón de login por huella
                              // Se muestra SIEMPRE si el dispositivo soporta biometría.
                              // Si el usuario no la ha activado, el botón aparece
                              // como "Configurar huella" y al pulsarlo muestra un
                              // diálogo explicativo. Cuando la activa desde su
                              // perfil, este botón cambia a "Ingresar con huella".
                              if (_biometricReady) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 46,
                                  child: OutlinedButton.icon(
                                    onPressed: _loadingBiometric || _loading
                                        ? null
                                        : _loginWithBiometric,
                                    icon: _loadingBiometric
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.primary,
                                            ),
                                          )
                                        : Icon(
                                            _biometricEnabled
                                                ? Icons.fingerprint_rounded
                                                : Icons.fingerprint_outlined,
                                            color: _biometricEnabled
                                                ? AppColors.primary
                                                : AppColors.textTertiary,
                                            size: 22,
                                          ),
                                    label: Text(
                                      _biometricEnabled
                                          ? 'Ingresar con huella'
                                          : 'Configurar huella',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        color: _biometricEnabled
                                            ? AppColors.primary
                                            : AppColors.textTertiary,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: AppColors.surface,
                                      foregroundColor: AppColors.textSecondary,
                                      side: BorderSide(
                                        color: _biometricEnabled
                                            ? AppColors.primary.withOpacity(0.5)
                                            : AppColors.border,
                                        width: 1.5,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                                if (_biometricEnabled && _biometricEmail != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Center(
                                      child: Text(
                                        'Huella activada para $_biometricEmail',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textTertiary,
                                          fontStyle: FontStyle.italic,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                              ],

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
                    'SaberPlus © 2026',
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