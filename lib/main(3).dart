// lib/main.dart
// Saber+ — Entry point v1.5.1
// Cambios vs v1.5.0:
//   - ✅ FIX #1+#3: GoRouter estable — creado UNA sola vez en initState()
//     ya no se recrea en cada rebuild (causaba reset a /welcome tras login)
//   - ✅ initialLocation prioriza auth.token sobre isFirstTime
//   - ✅ Redirect también aplica a /welcome cuando el usuario ya está logueado

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode; // <-- CAMBIO AQUÍ
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'config/env.dart';
import 'config/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_logger.dart';
import 'core/constants/app_constants.dart';
import 'core/services/cache_service.dart';
import 'core/services/course_cache_service.dart';
import 'core/services/dio_client.dart';
import 'core/services/video_download_service.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/teacher_service.dart';
import 'providers/dashboard_provider.dart';
import 'providers/gamification_provider.dart';
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

// ── Flutter Downloader Callback (FASE 4.3) ──
@pragma('vm:entry-point')
void _videoDownloadCallback(
  String id,
  int status,
  int progress,
) {
  VideoDownloadService.downloadCallback(id, status, progress);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Cargar variables de entorno ──
  await dotenv.load(fileName: '.env');
  Env.ensureConfigured();
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

  // ✅ Inicializar caché (usa SharedPreferences internamente)
  await CacheService.init();
  // ✅ FASE 4: Inicializar caché de cursos (offline-first)
  await CourseCacheService.init();
  // ✅ FASE 4.3: Inicializar servicio de descarga de videos (offline)
  await FlutterDownloader.initialize(debug: kDebugMode);
  await VideoDownloadService.init();
  // Registrar callback de progreso de descargas
  FlutterDownloader.registerCallback(_videoDownloadCallback);

  // ── AuthService precarga ──
  final authService = AuthService();
  await authService.loadFromStorage();

  // ✅ FASE 1.3: Configurar callback de sesión expirada para DioClient
  DioClient.onSessionExpired = () async {
    AppLogger.w('Sesión expirada (DioClient callback) — forzando logout');
    await authService.logout();
  };

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
        // ✅ FASE 3: GamificationProvider (XP, niveles, rachas, badges)
        ChangeNotifierProvider<GamificationProvider>(
          create: (_) => GamificationProvider(),
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
  bool _gamifLoaded = false;

  // ✅ FIX: Router creado UNA sola vez — ya no se recrea en cada rebuild
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _initFCM();
    _initRouter();

    // ✅ FASE 3: Escuchar cambios de auth para cargar gamificación al hacer login
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthService>();
      auth.addListener(_onAuthChanged);
      // Cargar gamificación si ya hay sesión al iniciar
      _maybeLoadGamification();
    });
  }

  @override
  void dispose() {
    // Limpiar listener para evitar memory leaks
    try {
      final auth = context.read<AuthService>();
      auth.removeListener(_onAuthChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onAuthChanged() {
    _maybeLoadGamification();
  }

  /// ✅ FASE 3: Carga el estado de gamificación cuando hay sesión activa.
  void _maybeLoadGamification() {
    try {
      final auth = context.read<AuthService>();
      final gamif = context.read<GamificationProvider>();

      if (auth.token != null && auth.userId != null && !_gamifLoaded) {
        _gamifLoaded = true;
        gamif.loadStatus();
      } else if (auth.token == null && _gamifLoaded) {
        // Sesión cerrada: resetear
        _gamifLoaded = false;
        gamif.clear();
      }
    } catch (_) {
      // provider puede no estar disponible si el árbol cambió
    }
  }

  void _initRouter() {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();

    // ✅ FIX #1: Priorizar auth sobre isFirstTime
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