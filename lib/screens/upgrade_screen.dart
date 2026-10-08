// lib/screens/upgrade_screen.dart
// Saber+ - Pantalla de Upgrade Premium (Redisenio Profesional)
//
// Caracteristicas:
// - Diseno premium con gradientes y animaciones
// - Comparativa de planes lado a lado
// - Lista de beneficios con iconos
// - v1.7.0 PAGOS POR PLATAFORMA:
//     * WEB    → Wompi (checkout externo, la web no esta sujeta a Play Store)
//     * ANDROID→ Google Play Billing (in_app_purchase). Colombia no participa
//                en el programa de billing alternativo de Google Play, asi que
//                las compras de productos digitales dentro del APK DEBEN ir
//                por Play Billing. Sin links de pago externos in-app.
// - Verificacion server-side: cada compra de Play se valida contra el backend
//   (verify_play_purchase.php), que consulta la Google Play Developer API.
// - Restaurar compras (reinstalaciones)
// - Periodo de prueba (trial)
// - FAQ expandible
// - Mensaje de plan actual si ya es premium

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../services/billing_service.dart';
import '../models/plan.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/app_logger.dart';

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen>
    with TickerProviderStateMixin {
  bool _loading = true;
  bool _processing = false;
  List<Plan> _plans = [];
  int? _selectedPlanIndex;
  bool _isPremium = false;
  String? _currentPlanName;

  // ── Google Play Billing (solo Android nativo) ──
  /// true en Android nativo: la compra va por Google Play Billing.
  /// En web (kIsWeb) y en iOS/desktop se mantiene el flujo Wompi/informativo.
  late final bool _usePlayBilling;

  /// init() + loadProducts() de Play ya terminaron (exitoso o no).
  bool _billingChecked = false;

  /// Play Billing disponible Y con al menos un producto cargado de Play
  /// Console. Si es false en Android, se muestra la tarjeta informativa
  /// "pago movil disponible proximamente" (sin links de pago externos:
  /// politica de Google Play).
  bool _billingReady = false;

  /// Subscripcion a los eventos de compra de Play.
  StreamSubscription<BillingEvent>? _purchaseSub;

  /// Tokens de compra ya verificados en esta sesion (evita dialogs duplicados
  /// si Android re-entrega la misma compra).
  final Set<String> _handledTokens = {};

  /// Estado del boton "Restaurar compras".
  bool _restoring = false;

  // ── Promociones (v1.7.0) ──
  /// Promo vigente (banner con o sin descuento) para mostrar arriba.
  Map<String, dynamic>? _promoBanner;

  /// Segundos restantes de la promo (cuenta regresiva en vivo).
  int _promoSegundos = 0;

  /// Tick cada segundo para la cuenta regresiva del banner.
  Timer? _promoTimer;

  /// Código promocional escrito por el usuario (solo web/Wompi).
  final TextEditingController _promoCodeController = TextEditingController();

  late final AnimationController _entranceController;
  late final Animation<double> _fade;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    );
    _slide = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    );

    // WEB → Wompi | ANDROID nativo → Google Play Billing
    _usePlayBilling = !kIsWeb && BillingService.isAndroidNativePlatform;

    _loadData();

    if (_usePlayBilling) {
      _initBilling();
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    _promoTimer?.cancel();
    _promoCodeController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final auth = Provider.of<AuthService>(context, listen: false);

      _isPremium = auth.user?['access_level'] == 'premium' ||
          auth.user?['access_level'] == 'early_bird';
      _currentPlanName = auth.user?['access_level'] ?? 'free';

      final plans = await api.getActivePlans();

      // ✅ v1.7.0: promociones vigentes (banner + descuento). Lo que el
      // admin crea en /admin aparece aquí al instante, sin actualizar la app.
      try {
        final promos = await api.getActivePromos();
        if (promos.isNotEmpty) {
          _promoBanner = promos.first;
          _promoSegundos = (promos.first['segundos_restantes'] as int?) ?? 0;
          _iniciarCuentaRegresiva();
        }
      } catch (e) {
        AppLogger.w('UpgradeScreen: sin promos disponibles ($e)');
      }

      if (mounted) {
        setState(() {
          _plans = plans;
          if (plans.isNotEmpty) {
            // Seleccionar el plan mensual por defecto
            _selectedPlanIndex = 0;
          }
          _loading = false;
        });
        _entranceController.forward();

        // ✅ v1.6.0: analítica de paywall visto
        AnalyticsService.logPaywallViewed();
      }
    } catch (e) {
      AppLogger.e('UpgradeScreen: error cargando planes', e);
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Cuenta regresiva en vivo del banner promocional (d/h/m/s).
  void _iniciarCuentaRegresiva() {
    _promoTimer?.cancel();
    if (_promoSegundos <= 0) return;
    _promoTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _promoTimer?.cancel();
        return;
      }
      setState(() => _promoSegundos--);
      if (_promoSegundos <= 0) {
        _promoTimer?.cancel();
        _promoBanner = null; // la promo venció frente a los ojos del usuario
      }
    });
  }

  String _formatearCuentaRegresiva(int segundos) {
    if (segundos <= 0) return '¡Última oportunidad!';
    final d = segundos ~/ 86400;
    final h = (segundos % 86400) ~/ 3600;
    final m = (segundos % 3600) ~/ 60;
    final s = segundos % 60;
    if (d > 0) return '$d día${d > 1 ? 's' : ''} $h h';
    if (h > 0) return '$h h $m min';
    return '$m min $s s';
  }

  // ─────────────────────────────────────────────
  // Google Play Billing (Android)
  // ─────────────────────────────────────────────

  Future<void> _initBilling() async {
    try {
      final ok = await BillingService.instance.init();
      if (!ok) {
        // Play Billing no disponible en este dispositivo.
        if (mounted) setState(() => _billingChecked = true);
        return;
      }

      // Escuchar ANTES de cargar productos: Android puede entregar compras
      // pendientes de confirmar (acknowledge) apenas se conecta el cliente.
      _purchaseSub ??= BillingService.instance.purchaseStream.listen(
        _onPurchaseEvent,
        onError: (Object e) {
          AppLogger.e('UpgradeScreen: error en stream de compras', e);
        },
      );

      final products = await BillingService.instance.loadProducts();
      if (!mounted) return;

      setState(() {
        _billingChecked = true;
        _billingReady = products.isNotEmpty;
      });

      if (products.isEmpty) {
        AppLogger.w(
          'UpgradeScreen: Play no devolvió productos '
          '(¿aún no configurados en Play Console?)',
        );
      }
    } catch (e) {
      AppLogger.e('UpgradeScreen: error iniciando Play Billing', e);
      if (mounted) setState(() => _billingChecked = true);
    }
  }

  /// Mapea el code del plan de la BD (get_all_active_plans) al productId
  /// de Google Play Console.
  String? _productIdFor(Plan plan) {
    final code = plan.code.toLowerCase();
    if (code.contains('lifetime')) return BillingProductIds.lifetime;
    if (code.contains('monthly')) return BillingProductIds.monthly;
    if (code.contains('annual')) return BillingProductIds.annual;
    return null;
  }

  /// Precio a mostrar en la card del plan. En Android con Play listo se usa
  /// el PRECIO REAL de Play (ProductDetails.price, con moneda local); el
  /// precio de la BD solo es fallback si Play no cargó el producto.
  String _displayPrice(Plan plan) {
    if (_usePlayBilling && _billingReady) {
      final productId = _productIdFor(plan);
      final playProduct = productId == null
          ? null
          : BillingService.instance.products[productId];
      if (playProduct != null) return playProduct.price;
    }
    return plan.formattedPrice;
  }

  void _onPurchaseEvent(BillingEvent event) {
    if (!mounted) return;

    switch (event.type) {
      case BillingEventType.purchased:
      case BillingEventType.restored:
        // Idempotencia local: una misma compra puede re-entregarse.
        final token = event.purchaseToken ?? '';
        if (token.isEmpty || !_handledTokens.add(token)) return;
        _verifyPlayPurchase(event);
        break;

      case BillingEventType.error:
        setState(() => _processing = false);
        _showError(event.message);
        break;

      case BillingEventType.pending:
        setState(() => _processing = false);
        _showInfo(event.message);
        break;

      case BillingEventType.canceled:
        // El usuario cerró la ventana de pago: sin castigo, sin ruido.
        setState(() => _processing = false);
        break;
    }
  }

  Future<void> _verifyPlayPurchase(BillingEvent event) async {
    final purchase = event.purchase;
    final token = event.purchaseToken ?? '';

    ApiService? api;
    AuthService? auth;
    try {
      api = Provider.of<ApiService>(context, listen: false);
      auth = Provider.of<AuthService>(context, listen: false);
    } catch (_) {}

    try {
      if (mounted) setState(() => _processing = true);

      // 1. Verificar server-side (NUNCA confiar en el cliente).
      final data = await api!.verifyPlayPurchase(
        productId: event.productId ?? '',
        purchaseToken: token,
        orderId: event.orderId,
      );

      if (data['status'] == 'ok') {
        // 2. Refrescar el perfil: fetchProfile() actualiza user en memoria,
        //    lo persiste en storage y notifica listeners (access_level nuevo).
        //    Es best-effort: el backend YA activó premium; si el refresh
        //    falla por red, no debe ocultar el éxito de la compra.
        try {
          await auth!.fetchProfile();
        } catch (_) {}

        if (!mounted) return;
        setState(() {
          _isPremium = true;
          _processing = false;
        });

        // ✅ v1.7.0: analítica de compra completada
        AnalyticsService.logPurchaseCompleted(plan: event.productId);

        await _showSuccessDialog(planName: event.productId ?? 'Premium');
      } else {
        // Defensa: la API ya lanza si status != 'ok', pero por si cambia.
        if (mounted) setState(() => _processing = false);
      }
    } catch (e) {
      AppLogger.e('UpgradeScreen: error verificando compra de Play', e);
      if (mounted) {
        setState(() => _processing = false);
        _showError(
          'Tu pago se realizó, pero no pudimos confirmarlo con el servidor '
          '(${_cleanError(e)}). Toca "Restaurar compras" en unos minutos '
          'para activar tu Premium.',
        );
      }
    } finally {
      // ⚠️ SIEMPRE confirmar la compra a Google (acknowledge), incluso si la
      // verificación con el backend falló por red: si no se confirma en 3
      // días, Google reembolsa. La verificación puede reintentarse luego.
      if (purchase != null) {
        await BillingService.instance.completePurchase(purchase);
      }
    }
  }

  Future<void> _handleRestore() async {
    if (_restoring) return;
    setState(() => _restoring = true);

    try {
      await BillingService.instance.restorePurchases();
      if (mounted) {
        _showInfo(
          'Buscando tus compras anteriores en Google Play. '
          'Si encontramos alguna, tu Premium se activará automáticamente.',
        );
      }
    } catch (e) {
      AppLogger.e('UpgradeScreen: error restaurando compras', e);
      if (mounted) {
        _showError('No se pudieron restaurar las compras: ${_cleanError(e)}');
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  // ─────────────────────────────────────────────
  // Flujo de compra
  // ─────────────────────────────────────────────

  Future<void> _handleUpgrade() async {
    if (_selectedPlanIndex == null || _plans.isEmpty) {
      _showError('Por favor selecciona un plan');
      return;
    }

    if (_usePlayBilling) {
      await _handleUpgradePlay();
      return;
    }

    // ── WEB: flujo Wompi (la web no está sujeta a Play Store) ──
    setState(() => _processing = true);

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final selectedPlan = _plans[_selectedPlanIndex!];

      // Mostrar dialogo de confirmacion antes de proceder
      final confirmed = await _showConfirmationDialog(selectedPlan);
      if (!confirmed) {
        setState(() => _processing = false);
        return;
      }

      final data = await api.createWompiPayment(
        planId: selectedPlan.id,
        promoCode: _promoCodeController.text, // ✅ v1.7.0
      );
      final String checkoutUrl = data['checkout_url'];

      // ✅ v1.7.0: feedback del descuento aplicado (banner o código)
      final descuento = data['descuento'] as Map<String, dynamic>?;
      if (descuento != null && mounted) {
        final base = descuento['precio_base'];
        final fin = descuento['precio_final'];
        _showError('🎉 ${descuento['titulo'] ?? 'Promoción'} aplicada: '
            '\$$base → \$$fin COP');
      } else if (data['promo_code_invalido'] == true && mounted) {
        _showError(data['promo_code_msg'] as String? ?? 'Código no válido');
      }

      AppLogger.d('Wompi URL: $checkoutUrl');

      // ✅ v1.6.0: analítica de inicio de compra
      AnalyticsService.logPurchaseStarted(
        plan: selectedPlan.code,
        priceCop: selectedPlan.price,
      );

      final uri = Uri.parse(checkoutUrl);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!opened) {
        throw Exception('No se pudo abrir Wompi');
      }
    } catch (e) {
      _showError('No se pudo iniciar el pago: $e');
      AppLogger.e('Error en upgrade', e);
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  /// ── ANDROID: flujo Google Play Billing ──
  Future<void> _handleUpgradePlay() async {
    final selectedPlan = _plans[_selectedPlanIndex!];
    final productId = _productIdFor(selectedPlan);

    if (productId == null ||
        !BillingService.instance.products.containsKey(productId)) {
      _showError(
        'Este plan aún no está disponible para pago móvil. '
        'Podrás comprarlo aquí muy pronto.',
      );
      return;
    }

    setState(() => _processing = true);

    try {
      // Confirmación antes de abrir la ventana de pago de Play.
      final confirmed = await _showConfirmationDialog(selectedPlan);
      if (!confirmed) {
        setState(() => _processing = false);
        return;
      }

      // ✅ v1.7.0: analítica de inicio de compra (mismo evento en ambos canales)
      AnalyticsService.logPurchaseStarted(
        plan: selectedPlan.code,
        priceCop: selectedPlan.price,
      );

      // Abre la ventana de pago de Google Play. El resultado NO llega aquí:
      // llega por purchaseStream (evento purchased/error/canceled/pending).
      await BillingService.instance.buyProduct(productId);
    } catch (e) {
      AppLogger.e('UpgradeScreen: error iniciando compra de Play', e);
      if (mounted) {
        setState(() => _processing = false);
        _showError(_cleanError(e));
      }
    }
  }

  Future<bool> _showConfirmationDialog(Plan plan) async {
    final priceText = _displayPrice(plan);
    final isPlay = _usePlayBilling && _billingReady;

    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(
                  isPlay ? Icons.shop_rounded : Icons.payment_rounded,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Text('Confirmar pago'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Estas a punto de suscribirte a:'),
                const SizedBox(height: 8),
                Text(
                  plan.name,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary),
                ),
                const SizedBox(height: 4),
                Text(
                  '$priceText ${plan.period}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isPlay ? Icons.verified_user_rounded : Icons.security_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isPlay
                              ? 'Pago seguro a través de Google Play. Se abrirá la ventana de pago de Google Play para confirmar.'
                              : 'Pago seguro via Wompi. Seras redirigido a la pagina de pago.',
                          style: TextStyle(fontSize: 12, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Continuar al pago'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Dialogo de exito con check animado (compra Play verificada).
  Future<void> _showSuccessDialog({required String planName}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PremiumSuccessDialog(planName: planName),
    );
  }

  String _cleanError(Object e) {
    final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    return msg.length > 160 ? '${msg.substring(0, 157)}...' : msg;
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.primaryDark,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // En Android: ¿ya terminamos de revisar Play Billing? ¿Está listo?
    final showPlansAndButton = !_usePlayBilling || _billingReady;
    final showBillingUnavailableCard = _usePlayBilling && _billingChecked && !_billingReady;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : CustomScrollView(
                slivers: [
                  // App Bar
                  SliverAppBar(
                    backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
                    foregroundColor: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                    pinned: true,
                    expandedHeight: 0,
                    leading: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                    title: const Text('Saber+ Premium', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),

                  // Contenido
                  SliverToBoxAdapter(
                    child: FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(_slide),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 24),

                              // Si ya es premium, mostrar mensaje
                              if (_isPremium) ...[
                                _buildAlreadyPremiumCard(isDark),
                                const SizedBox(height: 32),
                              ] else ...[
                                // ✅ v1.7.0: Banner promocional (si hay promo vigente)
                                if (_promoBanner != null) ...[
                                  _buildPromoBanner(isDark),
                                  const SizedBox(height: 20),
                                ],

                                // Hero
                                _buildHeroSection(),
                                const SizedBox(height: 32),

                                // Beneficios
                                _buildBenefitsSection(isDark),
                                const SizedBox(height: 32),

                                // Planes / estado del pago móvil
                                if (showBillingUnavailableCard) ...[
                                  _buildBillingUnavailableCard(isDark),
                                  const SizedBox(height: 32),
                                ] else if (_plans.isNotEmpty && showPlansAndButton) ...[
                                  _buildPlansSection(isDark),
                                  const SizedBox(height: 32),
                                ],

                                // Comparativa
                                _buildComparisonSection(isDark),
                                const SizedBox(height: 32),

                                // FAQ
                                _buildFaqSection(isDark),
                                const SizedBox(height: 32),

                                // ✅ v1.7.0: código promocional (solo web/Wompi)
                                if (showPlansAndButton && !_usePlayBilling) ...[
                                  _buildPromoCodeField(isDark),
                                  const SizedBox(height: 16),
                                ],

                                // Boton de upgrade (web Wompi / Android Play)
                                if (showPlansAndButton) _buildUpgradeButton(),

                                // Restaurar compras (Android + Play Billing)
                                if (_usePlayBilling && _billingReady) ...[
                                  const SizedBox(height: 8),
                                  _buildRestoreButton(),
                                ],
                                const SizedBox(height: 40),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// Card cuando el usuario ya es premium
  Widget _buildAlreadyPremiumCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.success, AppColors.successDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.success.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.verified_rounded, color: Colors.white, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Ya eres Premium!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Disfrutas de todos los beneficios de Saber+ Premium.\nPlan actual: ${_currentPlanName?.toUpperCase()}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9), height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.successDark,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Continuar disfrutando', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ v1.7.0: Banner promocional con cuenta regresiva en vivo.
  Widget _buildPromoBanner(bool isDark) {
    final promo = _promoBanner!;
    final titulo = (promo['titulo'] as String?) ?? 'Promoción especial';
    final descripcion = (promo['descripcion'] as String?) ?? '';
    final dtoTipo = promo['descuento_tipo'] as String? ?? 'porcentaje';
    final dtoValor = promo['descuento_valor'];
    final hayDescuento =
        (dtoValor is num && dtoValor > 0) || (dtoValor is String && dtoValor.isNotEmpty && dtoValor != '0');
    final planId = promo['plan_id'] as int?;

    final dtoTexto = !hayDescuento
        ? null
        : dtoTipo == 'porcentaje'
            ? '-${_limpiaNum(dtoValor)}% de descuento'
            : '-\$${_formateaCop(dtoValor)} COP de descuento';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ),
            ],
          ),
          if (descripcion.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              descripcion,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.92),
                  height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (dtoTexto != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    dtoTexto,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF7C3AED)),
                  ),
                ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      _formatearCuentaRegresiva(_promoSegundos),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (planId != null)
            const SizedBox(height: 8),
          if (planId != null)
            Text(
              'Aplica al plan seleccionado · el descuento se aplica automáticamente al pagar en la web',
              style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.white.withOpacity(0.75),
                  height: 1.3),
            ),
        ],
      ),
    );
  }

  String _limpiaNum(dynamic v) {
    if (v is num) {
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    }
    return v?.toString() ?? '0';
  }

  String _formateaCop(dynamic v) {
    final n = v is num ? v : double.tryParse(v?.toString() ?? '0') ?? 0;
    return n.round().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  /// ✅ v1.7.0: Campo de código promocional (SOLO web — Wompi aplica el
  /// descuento al pagar; en Android los precios los fija Play Console).
  Widget _buildPromoCodeField(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.redeem_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _promoCodeController,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
              decoration: InputDecoration(
                hintText: '¿Tienes un código promocional?',
                hintStyle: TextStyle(
                    color: AppColors.textDisabled,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Seccion hero con titulo y descripcion
  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
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
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'Desbloquea tu potencial',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Acceso ilimitado a simulacros, retos diarios, prediccion ICFES,\nanalisis de errores y mucho mas.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9), height: 1.5),
          ),
        ],
      ),
    );
  }

  /// Lista de beneficios con iconos
  Widget _buildBenefitsSection(bool isDark) {
    final benefits = [
      {'icon': Icons.assignment_rounded, 'title': 'Simulacros ilimitados', 'desc': 'Practica sin restricciones'},
      {'icon': Icons.flash_on_rounded, 'title': 'Retos diarios', 'desc': 'Gana XP todos los dias'},
      {'icon': Icons.insights_rounded, 'title': 'Prediccion ICFES', 'desc': 'Conoce tu puntaje estimado'},
      {'icon': Icons.analytics_rounded, 'title': 'Analisis de errores', 'desc': 'Descubre en que fallar'},
      {'icon': Icons.emoji_events_rounded, 'title': 'Gamificacion completa', 'desc': 'Badges, ranking y mas'},
      {'icon': Icons.block_rounded, 'title': 'Sin anuncios', 'desc': 'Estudia sin interrupciones'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Que incluye Premium',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        ...benefits.map((b) => _buildBenefitItem(b['icon'] as IconData, b['title'] as String, b['desc'] as String, isDark)),
      ],
    );
  }

  Widget _buildBenefitItem(IconData icon, String title, String desc, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary)),
                Text(desc, style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary)),
              ],
            ),
          ),
          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
        ],
      ),
    );
  }

  /// Card informativa cuando Play Billing no está disponible o los productos
  /// aún no están configurados en Play Console.
  ///
  /// ⚠️ POLÍTICA GOOGLE PLAY: SIN botones/links de pago externos dentro del
  /// app Android. Un texto plano informativo ("saberplus.app") sí está
  /// permitido.
  Widget _buildBillingUnavailableCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 1,
        ),
        boxShadow: [BoxShadow(color: AppColors.shadowSm, blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_top_rounded, color: AppColors.warningDark, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            'Pago móvil disponible próximamente',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Mientras tanto puedes seguir estudiando gratis: simulacros de '
            'diagnóstico, retos, ranking y los cursos básicos siguen '
            'disponibles para ti.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Más novedades en saberplus.app',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  /// Seccion de seleccion de planes
  Widget _buildPlansSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Elige tu plan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        ..._plans.asMap().entries.map((entry) {
          final index = entry.key;
          final plan = entry.value;
          return _buildPlanCard(plan, index, isDark);
        }),
      ],
    );
  }

  Widget _buildPlanCard(Plan plan, int index, bool isDark) {
    final isSelected = _selectedPlanIndex == index;
    final isPopular = plan.isPremium;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;

    return GestureDetector(
      onTap: () => setState(() => _selectedPlanIndex = index),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.border),
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.primary.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 6))]
              : [BoxShadow(color: AppColors.shadowSm, blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    plan.name,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary),
                  ),
                ),
                if (isPopular)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('POPULAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(plan.description, style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // En Android: precio REAL de Google Play (moneda local).
                // Fallback: precio de la BD (web / Play sin cargar).
                Text(
                  _displayPrice(plan),
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppColors.primary),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(plan.period, style: TextStyle(fontSize: 14, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: isSelected ? AppColors.primary : (isDark ? AppColors.darkTextTertiary : AppColors.textTertiary),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  isSelected ? 'Plan seleccionado' : 'Tocar para seleccionar',
                  style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? AppColors.primary : (isDark ? AppColors.darkTextTertiary : AppColors.textTertiary)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Tabla comparativa Free vs Premium
  Widget _buildComparisonSection(bool isDark) {
    final features = [
      {'feature': 'Simulacros ICFES', 'free': '2 por mes', 'premium': 'Ilimitados'},
      {'feature': 'Retos diarios', 'free': 'No', 'premium': 'Si'},
      {'feature': 'Prediccion ICFES', 'free': 'No', 'premium': 'Si'},
      {'feature': 'Analisis de errores', 'free': 'No', 'premium': 'Si'},
      {'feature': 'Ranking de XP', 'free': 'Si', 'premium': 'Si'},
      {'feature': 'Cursos completos', 'free': '3 basicos', 'premium': 'Todos'},
      {'feature': 'Sin anuncios', 'free': 'No', 'premium': 'Si'},
      {'feature': 'Soporte prioritario', 'free': 'No', 'premium': 'Si'},
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.shadowSm, blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Comparativa', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          // Header
          Row(
            children: [
              const Expanded(flex: 2, child: Text('Caracteristica', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey))),
              const Expanded(child: Text('Free', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textTertiary))),
              const Expanded(child: Text('Premium', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary))),
            ],
          ),
          const Divider(height: 20),
          // Rows
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text(f['feature'] as String, style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary))),
                Expanded(child: Text(f['free'] as String, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textTertiary))),
                Expanded(child: Text(f['premium'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary))),
              ],
            ),
          )),
        ],
      ),
    );
  }

  /// FAQ expandible
  Widget _buildFaqSection(bool isDark) {
    final faqs = [
      {'q': 'Puedo cancelar cuando quiera?', 'a': 'Si, puedes cancelar tu suscripcion en cualquier momento desde tu perfil o contactandonos. Mantendras acceso premium hasta el final del periodo pagado.'},
      {
        'q': 'Como funciona el pago?',
        'a': _usePlayBilling
            ? 'El pago se procesa de forma segura con Google Play. Puedes pagar con los métodos asociados a tu cuenta de Google, y la suscripción se administra desde la propia Play Store.'
            : 'Usamos Wompi, una plataforma de pago segura. Aceptamos tarjetas de credito, debito, PSE y Nequi. El pago es 100% seguro.',
      },
      {'q': 'Hay periodo de prueba?', 'a': 'Si! Ofrecemos un periodo de prueba gratis de 7 dias para que pruebes todas las funciones premium sin compromiso.'},
      {'q': 'Puedo cambiar de plan?', 'a': 'Si, puedes cambiar entre el plan mensual y anual cuando quieras. El cambio se aplica al final del periodo actual.'},
      {
        'q': 'Cambio de teléfono o reinstalé la app, pierdo mi Premium?',
        'a': 'No. Si compraste con Google Play, tus compras están asociadas a tu cuenta de Google: usa el botón "Restaurar compras" y tu Premium volverá a activarse automáticamente.',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Preguntas frecuentes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        ...faqs.map((faq) => _buildFaqItem(faq['q'] as String, faq['a'] as String, isDark)),
      ],
    );
  }

  Widget _buildFaqItem(String question, String answer, bool isDark) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(question, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary)),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(answer, style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary, height: 1.5)),
        ),
      ],
    );
  }

  /// Boton flotante de upgrade
  Widget _buildUpgradeButton() {
    // En Android, deshabilitado mientras Play Billing termina de cargar
    // (evita comprar con precio de BD antes de conocer el precio real).
    final buttonDisabled = _processing || (_usePlayBilling && !_billingReady);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SafeArea(
        child: ElevatedButton(
          onPressed: buttonDisabled ? null : _handleUpgrade,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: _processing
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.lock_open_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _selectedPlanIndex != null && _plans.isNotEmpty
                          ? 'Suscribirme - ${_displayPrice(_plans[_selectedPlanIndex!])}'
                          : 'Suscribirme ahora',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Botón "Restaurar compras" (Google Play Billing, reinstalaciones).
  Widget _buildRestoreButton() {
    return Center(
      child: TextButton.icon(
        onPressed: _restoring ? null : _handleRestore,
        icon: _restoring
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.restore_rounded, size: 18),
        label: const Text('Restaurar compras'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Dialogo de exito con check animado (compra verificada server-side).
class _PremiumSuccessDialog extends StatefulWidget {
  const _PremiumSuccessDialog({required this.planName});

  final String planName;

  @override
  State<_PremiumSuccessDialog> createState() => _PremiumSuccessDialogState();
}

class _PremiumSuccessDialogState extends State<_PremiumSuccessDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _scale,
              child: Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.success, AppColors.successDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '¡Ahora eres Premium!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Tu compra fue verificada con éxito y todos los beneficios de '
              'Saber+ Premium ya están activados.\n'
              'Suscripción: ${widget.planName}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('¡A estudiar!', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
