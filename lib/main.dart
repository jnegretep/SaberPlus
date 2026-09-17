// lib/main.dart
// Saber+ — Entry point v1.5.1
// Cambios vs v1.5.0:
//   - ✅ FIX #1+#3: GoRouter estable — creado UNA sola vez en initState()
//   - ✅ initialLocation prioriza auth.token sobre isFirstTime
//   - ✅ Redirect también aplica a /welcome cuando el usuario ya está logueado
//   - 🔧 FCM FIX: el token FCM ahora se sincroniza con el backend

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
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
import 'core/services/pdf_cache_service.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/teacher_service.dart';
import 'services/fcm_service.dart';           // 🔧 FCM FIX
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

  // ✅ Caches
  await CacheService.init();
  await CourseCacheService.init();
  await FlutterDownloader.initialize(debug: kDebugMode);
  await VideoDownloadService.init();
  FlutterDownloader.registerCallback(_videoDownloadCallback);
  await PdfCacheService.init();

  // ── AuthService precarga ──
  final authService = AuthService();
  await authService.loadFromStorage();

  // ✅ Callback de sesión expirada
  DioClient.onSessionExpired = () async {
    AppLogger.w('Sesión expirada (DioClient callback) — forzando logout');
    await authService.logout();
  };

  // 🔧 FCM FIX: configurar el servicio FCM.
  // ⚠️ IMPORTANTE: debe ir DESPUÉS de declarar `authService`.
  FcmService.configure(
    baseUrl: ApiService.baseUrl,
    jwtProvider: () async => authService.token,
  );

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

  // 🔧 FCM FIX: rastrea si el usuario ya estaba logueado para detectar
  // la transición "anon → logueado" y sincronizar el token en ese momento.
  bool _wasLoggedIn = false;

  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _initFCM();
    _initRouter();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthService>();
      auth.addListener(_onAuthChanged);

      // 🔧 FCM FIX: estado inicial (por si el usuario ya estaba logueado al abrir)
      _wasLoggedIn = auth.token != null && auth.userId != null;
      if (_wasLoggedIn) {
        FcmService.syncTokenWithBackend();
      }

      _maybeLoadGamification();
    });
  }

  @override
  void dispose() {
    try {
      final auth = context.read<AuthService>();
      auth.removeListener(_onAuthChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onAuthChanged() {
    _maybeLoadGamification();

    // 🔧 FCM FIX: cuando el usuario pasa de anon → logueado, sincronizar token.
    // Este es el caso "acabo de hacer login" (cubre LoginScreen y registro).
    try {
      final auth = context.read<AuthService>();
      final isLoggedIn = auth.token != null && auth.userId != null;
      if (isLoggedIn && !_wasLoggedIn) {
        AppLogger.i('FcmService: login detectado, sincronizando token...');
        FcmService.syncTokenWithBackend();
      }
      _wasLoggedIn = isLoggedIn;
    } catch (_) {}
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
        _gamifLoaded = false;
        gamif.clear();
      }
    } catch (_) {}
  }

  void _initRouter() {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();

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

      // 🔧 FCM FIX: antes esto solo logueaba el token y nunca se enviaba.
      // Ahora: (1) registramos listener de rotación, (2) sincronizamos el
      // token actual (si ya hay JWT, funciona; si no, se omite y se
      // reintentará tras el login).
      FcmService.registerTokenRefreshListener();
      await FcmService.syncTokenWithBackend();

      // Notificación en foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        AppLogger.i('FCM onMessage: ${message.notification?.title}');
        _handleSmartNotification(message);
      });

      // Tap en notificación con app en background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        AppLogger.i('FCM onMessageOpenedApp: ${message.data}');
        _handleNotificationTap(message.data);
      });

      // App abierta desde notificación (cold start)
      messaging.getInitialMessage().then((message) {
        if (message != null) {
          AppLogger.i('FCM initialMessage: ${message.data}');
          _handleNotificationTap(message.data);
        }
      });

      _fcmInitialized = true;
    } catch (e) {
      AppLogger.e('Error inicializando FCM', e);
    }
  }

  void _handleSmartNotification(RemoteMessage message) {
    final title = message.notification?.title ?? message.data['title'] ?? '';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    final action = message.data['action'] ?? '';

    if (title.isEmpty) return;

    final scaffoldMessenger = ScaffoldMessenger.of(_router.routerDelegate.navigatorKey.currentContext!);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (body.isNotEmpty)
              Text(body, style: const TextStyle(fontSize: 13)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: action.isNotEmpty
            ? SnackBarAction(
                label: 'Ver',
                onPressed: () => _navigateFromAction(action),
              )
            : null,
      ),
    );
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final action = data['action'] ?? '';
    _navigateFromAction(action);
  }

  void _navigateFromAction(String action) {
    final context = _router.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;

    switch (action) {
      case 'go_dashboard':
        context.go('/dashboard');
        break;
      case 'go_daily_challenges':
        context.push('/daily-challenges');
        break;
      case 'go_achievements':
        context.push('/achievements');
        break;
      case 'go_prediction':
        context.push('/prediction');
        break;
      case 'go_stats':
        context.push('/estadisticas');
        break;
      default:
        context.go('/dashboard');
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