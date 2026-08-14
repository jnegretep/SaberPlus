// lib/main.dart
// Saber+ — Entry point v1.5.1
// Cambios vs v1.5.0:
//   - ✅ FIX #1+#3: GoRouter estable — creado UNA sola vez en initState()
//     ya no se recrea en cada rebuild (causaba reset a /welcome tras login)
//   - ✅ initialLocation prioriza auth.token sobre isFirstTime
//   - ✅ Redirect también aplica a /welcome cuando el usuario ya está logueado

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'config/env.dart';
import 'config/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_logger.dart';
import 'core/constants/app_constants.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/teacher_service.dart';
import 'providers/dashboard_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/theme_provider.dart';
import 'services/notifications_api.dart';
import 'services/plan_service.dart';

// ── Firebase Background Handler ──
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  AppLogger.i('Notificación en background: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Cargar variables de entorno ──
  await dotenv.load(fileName: '.env');
  Env.ensureConfigured(); // ⚠️ Falla explícitamente si falta config crítica
  Env.debugPrintConfig();

  // ── Firebase ──
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: Env.firebaseApiKey,
        authDomain: Env.firebaseAuthDomain,
        projectId: Env.firebaseProjectId,
        storageBucket: Env.firebaseStorageBucket,
        messagingSenderId: Env.firebaseMessagingSenderId,
        appId: Env.firebaseAppId,
        measurementId: Env.firebaseMeasurementId,
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  // ── Localización ──
  await initializeDateFormatting('es_ES', null);

  // ── Notificaciones en background ──
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ── SharedPreferences ──
  final prefs = await SharedPreferences.getInstance();
  final isFirstTime = prefs.getBool(AppConstants.keyFirstTime) ?? true;
  if (isFirstTime) {
    await prefs.setBool(AppConstants.keyFirstTime, false);
  }

  // ── AuthService precarga ──
  final authService = AuthService();
  await authService.loadFromStorage();

  // ── Theme Provider ──
  final themeProvider = ThemeProvider();
  await themeProvider.loadFromPrefs();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<PlanService>(
          create: (_) => PlanService(),
        ),
        ProxyProvider<AuthService, ApiService>(
          update: (context, auth, previous) => ApiService(auth),
        ),
        ProxyProvider<AuthService, TeacherService>(
          update: (context, auth, previous) => TeacherService(authService: auth),
        ),
        ChangeNotifierProxyProvider<ApiService, DashboardProvider>(
          create: (context) => DashboardProvider(context.read<ApiService>()),
          update: (context, api, dashboard) => dashboard ?? DashboardProvider(api),
        ),
      ],
      child: MyApp(isFirstTime: isFirstTime),
    ),
  );
}

// ── App Root ──
class MyApp extends StatefulWidget {
  final bool isFirstTime;

  const MyApp({super.key, required this.isFirstTime});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _fcmInitialized = false;

  // ✅ FIX: Router creado UNA sola vez — ya no se recrea en cada rebuild
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _initFCM();
    _initRouter();
  }

  void _initRouter() {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();

    // ✅ FIX #1: Priorizar auth sobre isFirstTime
    // Si el usuario ya tiene token válido → dashboard
    // Si no, pero ya vio el onboarding → login
    // Si es primera vez → welcome (onboarding)
    final String initialLocation;
    if (auth.token != null && auth.userId != null) {
      initialLocation = auth.isProfesor ? '/teacher' : '/dashboard';
    } else if (widget.isFirstTime) {
      initialLocation = '/welcome';
    } else {
      initialLocation = '/login';
    }

    _router = buildAppRouter(
      auth: auth,
      api: api,
      initialLocation: initialLocation,
    );

    AppLogger.d('Router inicializado en: $initialLocation '
        '(token=${auth.token != null}, userId=${auth.userId}, '
        'isFirstTime=${widget.isFirstTime})');
  }

  Future<void> _initFCM() async {
    if (_fcmInitialized) return;

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      AppLogger.i('FCM permisos: ${settings.authorizationStatus}');

      final token = await messaging.getToken();
      AppLogger.i('FCM token: ${token?.substring(0, 20)}...');

      _fcmInitialized = true;
    } catch (e) {
      AppLogger.e('Error inicializando FCM', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final themeProvider = context.watch<ThemeProvider>();

    Widget app = MaterialApp.router(
      title: AppConstants.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
    );

    // NotificationProvider solo si el usuario está autenticado
    if (auth.userId != null && auth.token != null) {
      final notificationsApi = NotificationsApi(
        baseUrl: ApiService.baseUrl,
        token: auth.token,
      );
      app = ChangeNotifierProvider(
        create: (_) => NotificationProvider(
          api: notificationsApi,
          userId: auth.userId!,
        )..refresh(),
        child: app,
      );
    }

    return app;
  }
}
