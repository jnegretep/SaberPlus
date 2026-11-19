// lib/main.dart
// Saber+ — Entry point v2.0.0
import 'dart:async'; // ✅ NUEVO: unawaited()

import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'config/env.dart';
import 'config/app_router.dart';
import 'core/theme/app_colors.dart';
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
import 'services/fcm_service.dart';
import 'services/biometric_service.dart';
import 'services/analytics_service.dart';
import 'providers/dashboard_provider.dart';
import 'providers/gamification_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/theme_provider.dart';
import 'services/notifications_api.dart';
import 'widgets/web_desktop_shell.dart';

// 🔧 FIX: Importamos el archivo generado por flutterfire configure
import 'firebase_options.dart';

// ── Firebase Background Handler ──
// Nota: corre en un isolate separado. NO usamos AppLogger aquí porque puede
// depender de bindings/servicios que no están garantizados en background.
// `debugPrint` (de flutter/foundation) es seguro y NO dispara avoid_print.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    debugPrint('🔥🔥🔥 BG HANDLER: inicializando Firebase...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('🔥🔥🔥 BG HANDLER: ✅ Firebase OK. msgId=${message.messageId}');
  } catch (e, st) {
    debugPrint('🔥🔥🔥 BG HANDLER: ❌ FALLÓ al inicializar Firebase');
    debugPrint('🔥🔥🔥 BG HANDLER ERROR: $e');
    debugPrint('🔥🔥🔥 BG HANDLER STACK: $st');
  }
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
  // Diagnóstico de Firebase. Usamos AppLogger (respeta kDebugMode, no
  // ensucia logs de release) en vez de print() para cumplir avoid_print.
  AppLogger.d(
      '🔥🔥🔥 FIREBASE INIT: plataforma=${defaultTargetPlatform.name}, kIsWeb=$kIsWeb');
  try {
    AppLogger.d('🔥🔥🔥 FIREBASE INIT: intentando con DefaultFirebaseOptions...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    AppLogger.d('🔥🔥🔥 FIREBASE INIT: ✅✅✅ OK con DefaultFirebaseOptions ✅✅✅');
  } catch (e, st) {
    AppLogger.e('🔥🔥🔥 FIREBASE INIT: ❌❌❌ FALLÓ con DefaultFirebaseOptions ❌❌❌');
    AppLogger.e('🔥🔥🔥 FIREBASE INIT ERROR: $e');
    AppLogger.d('🔥🔥🔥 FIREBASE INIT STACK: $st');

    // Fallback: intentar sin opciones (en Android lee google-services.json)
    try {
      AppLogger.d('🔥🔥🔥 FIREBASE INIT: intentando FALLBACK (sin options)...');
      await Firebase.initializeApp();
      AppLogger.d('🔥🔥🔥 FIREBASE INIT: ✅✅✅ OK con FALLBACK ✅✅✅');
    } catch (e2, st2) {
      AppLogger.e('🔥🔥🔥 FIREBASE INIT: ❌❌❌ FALLBACK TAMBIÉN FALLÓ ❌❌❌');
      AppLogger.e('🔥🔥🔥 FIREBASE INIT ERROR2: $e2');
      AppLogger.d('🔥🔥🔥 FIREBASE INIT STACK2: $st2');
    }
  }

  // ── Localización ──
  await initializeDateFormatting('es_ES', null);

  // ── Notificaciones en background (solo móvil; en web no aplica) ──
  if (!kIsWeb) {
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      AppLogger.e('FCM onBackgroundMessage falló (no bloqueante)', e);
    }
  }

  // ── SharedPreferences ──
  final prefs = await SharedPreferences.getInstance();
  final isFirstTime = prefs.getBool(AppConstants.keyFirstTime) ?? true;
  if (isFirstTime) {
    await prefs.setBool(AppConstants.keyFirstTime, false);
  }

  // ✅ Caches
  await CacheService.init();
  await CourseCacheService.init();

  // ✅ v1.6.0 WEB: flutter_downloader NO tiene soporte web
  if (!kIsWeb) {
    await FlutterDownloader.initialize(debug: kDebugMode);
    await VideoDownloadService.init();
    FlutterDownloader.registerCallback(_videoDownloadCallback);
  }
  await PdfCacheService.init();

  // ── AuthService precarga ──
  final authService = AuthService();
  await authService.loadFromStorage();

  // ✅ v1.6.0: token/usuario para el espejo de analítica del backend
  await AnalyticsService.initialize();
  AnalyticsService.authToken = authService.token;
  if (authService.userId != null) {
    await AnalyticsService.setUserId(authService.userId);
  }

  // ✅ Callback de sesión expirada
  DioClient.onSessionExpired = () async {
    AppLogger.w('Sesión expirada (DioClient callback) — forzando logout');
    await authService.logout();
  };

  // ✅ v1.7.1: cuando el interceptor refresque los tokens automáticamente,
  // persistirlos y sincronizar AuthService
  DioClient.onTokensRefreshed = (newToken, newRefresh) async {
    await authService.persistRefreshedTokens(newToken, newRefresh);
  };

  // 🔧 FCM FIX: configurar el servicio FCM.
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
        // ✅ v2.0 (limpieza): PlanService y AccessWrapper eran código muerto
        // (fetchPlanStatus era TODO, updatePremiumStatus sin llamadas, el
        // paywall real vive en course_list_screen + upgrade_screen) — se
        // eliminaron del árbol de providers.
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
  // ✅ FIX: constructor arriba de los campos (sort_constructors_first) y
  // required antes de super.key (always_put_required_named_parameters_first).
  const MyApp({required this.isFirstTime, super.key});

  final bool isFirstTime;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _fcmInitialized = false;
  bool _gamifLoaded = false;
  bool _wasLoggedIn = false;

  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // ✅ v2.0: observador de ciclo de vida para el bloqueo biométrico
    // (al volver de segundo plano con sesión activa + bloqueo activado).
    WidgetsBinding.instance.addObserver(this);

    // ✅ FIX: unawaited() en llamadas Future desde un método síncrono
    // (initState no puede ser async).
    unawaited(_initFCM());
    _initRouter();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthService>();
      auth.addListener(_onAuthChanged);

      _wasLoggedIn = auth.token != null && auth.userId != null;
      if (_wasLoggedIn) {
        unawaited(FcmService.syncTokenWithBackend());
      }

      _maybeLoadGamification();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      final auth = context.read<AuthService>();
      auth.removeListener(_onAuthChanged);
    } catch (_) {}
    super.dispose();
  }

  // ✅ v2.0 (bloqueo biométrico): al volver a primer plano, si hay sesión
  // activa y el bloqueo está activado, se vuelve a pedir la huella.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_maybeLock());
  }

  /// Redirige a /lock si corresponde (sesión activa + bloqueo activado +
  /// dispositivo con biometría + no estamos ya bloqueados). Nunca bloquea
  /// en web (local_auth no tiene soporte web).
  Future<void> _maybeLock() async {
    if (kIsWeb) return;
    try {
      final auth = context.read<AuthService>();
      if (auth.token == null || auth.userId == null) return;
      if (!await auth.isAppLockEnabled()) return;

      final support = await BiometricService.checkSupport();
      if (support != BiometricSupport.ready) return;

      final location = _router.routerDelegate.currentConfiguration.uri.path;
      if (location == '/lock' || location == '/login') return;

      _router.go('/lock');
    } catch (e) {
      AppLogger.w('AppLock: no se pudo evaluar el bloqueo ($e)');
    }
  }

  void _onAuthChanged() {
    _maybeLoadGamification();

    try {
      final auth = context.read<AuthService>();

      AnalyticsService.authToken = auth.token;
      unawaited(AnalyticsService.setUserId(auth.userId));

      final isLoggedIn = auth.token != null && auth.userId != null;
      if (isLoggedIn && !_wasLoggedIn) {
        AppLogger.i('FcmService: login detectado, sincronizando token...');
        unawaited(FcmService.syncTokenWithBackend());
      }
      _wasLoggedIn = isLoggedIn;
    } catch (_) {}
  }

  void _maybeLoadGamification() {
    try {
      final auth = context.read<AuthService>();
      final gamif = context.read<GamificationProvider>();

      if (auth.token != null && auth.userId != null && !_gamifLoaded) {
        _gamifLoaded = true;
        unawaited(gamif.loadStatus());
      } else if (auth.token == null && _gamifLoaded) {
        _gamifLoaded = false;
        gamif.clear();
      }
    } catch (_) {}
  }

  // ✅ v2.0: la ruta inicial se decide de forma asíncrona para poder consultar
  // el flag del bloqueo biométrico local antes de mostrar cualquier pantalla.
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

    // ✅ v2.0: con sesión activa + bloqueo biométrico activado, la PRIMERA
    // pantalla visible es el bloqueo (no el dashboard).
    if (initialLocation == '/dashboard' || initialLocation == '/teacher') {
      unawaited(_maybeLock());
    }
  }

  Future<void> _initFCM() async {
    if (_fcmInitialized) return;

    // ✅ v2.0 (FCM): la web YA puede recibir push — antes se saltaba TODO el
    // flujo (sin permisos, sin listeners, sin token). Ahora solo se omite si
    // falta la VAPID key en .env (imprescindible para getToken en web).
    // El service worker web/firebase-messaging-sw.js hace el trabajo en
    // background; en foreground se muestra el banner inteligente.
    if (kIsWeb) {
      final vapid = Env.firebaseVapidKey;
      if (vapid.isEmpty) {
        AppLogger.w(
            'FCM web deshabilitado: falta FIREBASE_VAPID_KEY en .env '
            '(ver GUIA_ACTIVACION_NOTIFICACIONES_SABERPLUS.md)');
        _fcmInitialized = true;
        return;
      }
    }

    try {
      AppLogger.d('🔥🔥🔥 FCM INIT: solicitando permisos...');
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      AppLogger.d('🔥🔥🔥 FCM INIT: permisos=${settings.authorizationStatus}');

      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          await messaging.setForegroundNotificationPresentationOptions(
            alert: true, badge: true, sound: true,
          );
        } catch (_) {}
      }

      FcmService.registerTokenRefreshListener();
      await FcmService.syncTokenWithBackend();

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        AppLogger.i('FCM onMessage: ${message.notification?.title}');
        _handleSmartNotification(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        AppLogger.i('FCM onMessageOpenedApp: ${message.data}');
        _handleNotificationTap(message.data);
      });

      messaging.getInitialMessage().then((message) {
        if (message != null) {
          AppLogger.i('FCM initialMessage: ${message.data}');
          _handleNotificationTap(message.data);
        }
      });

      _fcmInitialized = true;
      AppLogger.d('🔥🔥🔥 FCM INIT: ✅ listeners registrados');
    } catch (e, st) {
      AppLogger.e('🔥🔥🔥 FCM INIT: ❌ FALLÓ');
      AppLogger.e('🔥🔥🔥 FCM INIT ERROR: $e');
      AppLogger.d('🔥🔥🔥 FCM INIT STACK: $st');
      AppLogger.e('FCM no inicializó (la app sigue sin notificaciones push)', e);
    }
  }

  void _handleSmartNotification(RemoteMessage message) {
    // ✅ FIX CRÍTICO: `message.data['x']` es `dynamic`, y `dynamic ?? ''` NO
    // se convierte en String estático. Castear con `as String?` en el origen
    // elimina los errores:
    //   - non_bool_condition (title.isEmpty / body.isNotEmpty / action.isNotEmpty)
    //   - argument_type_not_assignable (Text(title), Text(body))
    final String title =
        message.notification?.title ??
        (message.data['title'] as String?) ??
        '';
    final String body =
        message.notification?.body ??
        (message.data['body'] as String?) ??
        '';
    final String action = (message.data['action'] as String?) ?? '';

    if (title.isEmpty) return;

    final ctx = _router.routerDelegate.navigatorKey.currentContext;
    if (ctx == null) return;

    final scaffoldMessenger = ScaffoldMessenger.of(ctx);
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
    // ✅ FIX: `data['action']` es dynamic. Castear antes del `??`.
    final String action = (data['action'] as String?) ?? '';
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
      // ✅ FASE 2.3: localización completa.
      // Sin esto, showDatePicker/showTimePicker/diálogos de Material
      // crashean cuando reciben `locale` explícito o cuando el dispositivo
      // está en un locale no soportado. Fuerza es_CO en toda la app.
      locale: const Locale('es', 'CO'),
      supportedLocales: const [
        Locale('es', 'CO'),
        Locale('es'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => _webFrame(context, child),
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

  Widget _webFrame(BuildContext context, Widget? child) {
    if (child == null) return const SizedBox.shrink();
    if (!kIsWeb) return child;

    final mq = MediaQuery.of(context);
    final windowWidth = mq.size.width;
    if (windowWidth <= 700) return child;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (windowWidth > kWebDesktopBreakpoint) {
      return WebDesktopBackground(isDark: isDark, child: child);
    }

    const frameWidth = 620.0;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1220), Color(0xFF16233F)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.0, -0.2),
                radius: 1.2,
                colors: [
                  // ✅ FIX: withOpacity() deprecado desde Flutter 3.27.
                  // withValues(alpha:) es el reemplazo oficial.
                  AppColors.primaryLight.withValues(alpha: 0.20),
                  AppColors.primaryLight.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: frameWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF111827) : const Color(0xFFF4F6FA),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 48,
                    spreadRadius: 12,
                  ),
                ],
              ),
              child: MediaQuery(
                data: mq.copyWith(size: Size(frameWidth, mq.size.height)),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}