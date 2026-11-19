// lib/screens/upgrade_screen.dart
// Saber+ - Pantalla de Upgrade Premium (Rediseño PAGO ÚNICO)
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

  late final bool _usePlayBilling;
  bool _billingChecked = false;
  bool _billingReady = false;
  StreamSubscription<BillingEvent>? _purchaseSub;
  final Set<String> _handledTokens = {};
  bool _restoring = false;

  Map<String, dynamic>? _promoBanner;
  int _promoSegundos = 0;
  Timer? _promoTimer;

  final TextEditingController _promoCodeController = TextEditingController();
  final TextEditingController _redeemController = TextEditingController();
  bool _redeeming = false;
  String? _redeemError;
  String? _redeemSuccess;

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
    _redeemController.dispose();
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
            _selectedPlanIndex = 0;
          }
          _loading = false;
        });
        _entranceController.forward();
        AnalyticsService.logPaywallViewed();
      }
    } catch (e) {
      AppLogger.e('UpgradeScreen: error cargando planes', e);
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

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
        _promoBanner = null;
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

  Future<void> _initBilling() async {
    try {
      final ok = await BillingService.instance.init();
      if (!ok) {
        if (mounted) setState(() => _billingChecked = true);
        return;
      }

      _purchaseSub ??= BillingService.instance.purchaseStream.listen(
        _onPurchaseEvent,
        onError: (Object e) => AppLogger.e('UpgradeScreen: error stream', e),
      );

      final products = await BillingService.instance.loadProducts();
      if (!mounted) return;

      setState(() {
        _billingChecked = true;
        _billingReady = products.isNotEmpty;
      });

      if (products.isEmpty) {
        AppLogger.w('UpgradeScreen: Play no devolvió productos.');
      }
    } catch (e) {
      AppLogger.e('UpgradeScreen: error iniciando Play Billing', e);
      if (mounted) setState(() => _billingChecked = true);
    }
  }

  /// ✅ Mapea el code del plan de la BD al productId de Play Console.
  String? _productIdFor(Plan plan) {
    final code = plan.code.toLowerCase();
    if (code.contains('lifetime')) return BillingProductIds.lifetime;
    if (code.contains('monthly')) return BillingProductIds.monthly;
    if (code.contains('annual')) return BillingProductIds.annual;
    return null;
  }

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

      final data = await api!.verifyPlayPurchase(
        productId: event.productId ?? '',
        purchaseToken: token,
        orderId: event.orderId,
      );

      if (data['status'] == 'ok') {
        try {
          await auth!.fetchProfile();
        } catch (_) {}

        if (!mounted) return;
        setState(() {
          _isPremium = true;
          _processing = false;
        });

        AnalyticsService.logPurchaseCompleted(plan: event.productId);
        await _showSuccessDialog(planName: event.productId ?? 'Premium');
      } else {
        if (mounted) setState(() => _processing = false);
      }
    } catch (e) {
      AppLogger.e('UpgradeScreen: error verificando compra', e);
      if (mounted) {
        setState(() => _processing = false);
        _showError(
          'Tu pago se realizó, pero no pudimos confirmarlo con el servidor. '
          'Toca "Restaurar compras" en unos minutos.',
        );
      }
    } finally {
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
        _showInfo('Buscando tus compras anteriores en Google Play...');
      }
    } catch (e) {
      if (mounted) {
        _showError('No se pudieron restaurar las compras: ${_cleanError(e)}');
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _handleUpgrade() async {
    if (_selectedPlanIndex == null || _plans.isEmpty) {
      _showError('Por favor selecciona un plan');
      return;
    }

    if (_usePlayBilling) {
      await _handleUpgradePlay();
      return;
    }

    setState(() => _processing = true);

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final selectedPlan = _plans[_selectedPlanIndex!];

      final confirmed = await _showConfirmationDialog(selectedPlan);
      if (!confirmed) {
        setState(() => _processing = false);
        return;
      }

      final data = await api.createWompiPayment(
        planId: selectedPlan.id,
        promoCode: _promoCodeController.text,
      );
      final String checkoutUrl = data['checkout_url'];

      final descuento = data['descuento'] as Map<String, dynamic>?;
      if (descuento != null && mounted) {
        final base = descuento['precio_base'];
        final fin = descuento['precio_final'];
        _showError('🎉 ${descuento['titulo'] ?? 'Promoción'} aplicada: \$$base → \$$fin COP');
      } else if (data['promo_code_invalido'] == true && mounted) {
        _showError(data['promo_code_msg'] as String? ?? 'Código no válido');
      }

      AnalyticsService.logPurchaseStarted(
        plan: selectedPlan.code,
        priceCop: selectedPlan.price,
      );

      final uri = Uri.parse(checkoutUrl);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!opened) throw Exception('No se pudo abrir Wompi');
    } catch (e) {
      _showError('No se pudo iniciar el pago: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _handleUpgradePlay() async {
    final selectedPlan = _plans[_selectedPlanIndex!];
    final productId = _productIdFor(selectedPlan);

    if (productId == null ||
        !BillingService.instance.products.containsKey(productId)) {
      _showError('Este plan no está disponible para pago móvil.');
      return;
    }

    setState(() => _processing = true);

    try {
      final confirmed = await _showConfirmationDialog(selectedPlan);
      if (!confirmed) {
        setState(() => _processing = false);
        return;
      }

      AnalyticsService.logPurchaseStarted(
        plan: selectedPlan.code,
        priceCop: selectedPlan.price,
      );

      await BillingService.instance.buyProduct(productId);
    } catch (e) {
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
                Icon(isPlay ? Icons.shop_rounded : Icons.payment_rounded, color: AppColors.primary),
                const SizedBox(width: 10),
                const Text('Confirmar compra'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Estás a punto de comprar:'),
                const SizedBox(height: 8),
                Text(
                  plan.name,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pago único: $priceText',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.successDark),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isPlay
                              ? 'Pago seguro vía Google Play. Sin cobros automáticos.'
                              : 'Pago seguro vía Wompi. Sin cobros automáticos.',
                          style: const TextStyle(fontSize: 12, color: AppColors.successDark, fontWeight: FontWeight.w600),
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
                child: const Text('Continuar'),
              ),
            ],
          ),
        ) ??
        false;
  }

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
      SnackBar(content: Text(msg), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating),
    );
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.primaryDark, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ✅ v2.2: En Android, solo mostramos planes que existan en Play.
    final displayPlans = _usePlayBilling && _billingReady
        ? _plans.where((plan) {
            final pid = _productIdFor(plan);
            return pid != null && BillingService.instance.products.containsKey(pid);
          }).toList()
        : _plans;

    final showPlansAndButton = !_usePlayBilling || _billingReady;
    final showBillingUnavailableCard = _usePlayBilling && _billingChecked && !_billingReady;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : CustomScrollView(
                slivers: [
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
                              if (_isPremium) ...[
                                _buildAlreadyPremiumCard(isDark),
                                const SizedBox(height: 32),
                              ] else ...[
                                // ✅ BANNER GIGANTE "PAGO ÚNICO"
                                _buildOneTimePaymentBanner(isDark),
                                const SizedBox(height: 20),

                                if (_promoBanner != null) ...[
                                  _buildPromoBanner(isDark),
                                  const SizedBox(height: 20),
                                ],

                                _buildHeroSection(),
                                const SizedBox(height: 24),

                                // ✅ COMPARATIVA
                                _buildOneTimeVsSubscriptionCard(isDark),
                                const SizedBox(height: 32),

                                _buildBenefitsSection(isDark),
                                const SizedBox(height: 32),

                                if (showBillingUnavailableCard) ...[
                                  _buildBillingUnavailableCard(isDark),
                                  const SizedBox(height: 32),
                                ] else if (displayPlans.isNotEmpty && showPlansAndButton) ...[
                                  _buildPlansSection(displayPlans, isDark),
                                  const SizedBox(height: 32),
                                ],

                                _buildComparisonSection(isDark),
                                const SizedBox(height: 32),
                                _buildFaqSection(isDark),
                                const SizedBox(height: 32),

                                if (showPlansAndButton && !_usePlayBilling) ...[
                                  _buildPromoCodeField(isDark),
                                  const SizedBox(height: 16),
                                ],

                                _buildRedeemCodeSection(isDark),
                                const SizedBox(height: 16),

                                if (showPlansAndButton) _buildUpgradeButton(),

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

  Widget _buildOneTimePaymentBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10B981), Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.45),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), shape: BoxShape.circle),
                child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              const Flexible(
                child: Text(
                  'PAGO ÚNICO',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
            ),
            child: const Text(
              'NO es una suscripción mensual',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Pagas UNA SOLA VEZ\nAcceso completo PARA SIEMPRE\nSin cobros automáticos · Sin renovación',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.7, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.98)),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildOneTimePill('✅ Pagas 1 vez'),
              const SizedBox(width: 8),
              _buildOneTimePill('✅ De por vida'),
              const SizedBox(width: 8),
              _buildOneTimePill('✅ Sin renovar'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOneTimePill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF047857)),
      ),
    );
  }

  Widget _buildOneTimeVsSubscriptionCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.success.withOpacity(0.4), width: 1.5),
        boxShadow: [BoxShadow(color: AppColors.shadowSm, blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Lo que estás comprando', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.error.withOpacity(0.3), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cancel_rounded, color: AppColors.error, size: 20),
                          const SizedBox(width: 6),
                          const Flexible(child: Text('NO es', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.error))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildComparisonLine('Suscripción mensual', false),
                      _buildComparisonLine('Cobro automático', false),
                      _buildComparisonLine('Renovación anual', false),
                      _buildComparisonLine('Cargo sorpresa', false),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.success.withOpacity(0.3), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                          const SizedBox(width: 6),
                          const Flexible(child: Text('SÍ es', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.success))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildComparisonLine('Pago único', true),
                      _buildComparisonLine('Acceso de por vida', true),
                      _buildComparisonLine('Sin renovación', true),
                      _buildComparisonLine('Sin cobros ocultos', true),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.verified_user_rounded, color: AppColors.successDark, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Transparencia total: pagas UNA vez y disfrutas PARA SIEMPRE. Nunca se cobra solo.',
                    style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w600, color: AppColors.successDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonLine(String text, bool isPositive) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isPositive ? Icons.check_rounded : Icons.close_rounded, size: 16, color: isPositive ? AppColors.successDark : AppColors.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, height: 1.3, color: isPositive ? AppColors.successDark : AppColors.errorDark, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlreadyPremiumCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.success, AppColors.successDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AppColors.success.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          const Icon(Icons.verified_rounded, color: Colors.white, size: 64),
          const SizedBox(height: 16),
          const Text('¡Ya eres Premium!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.successDark, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('Continuar disfrutando', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoBanner(bool isDark) {
    final promo = _promoBanner!;
    final titulo = (promo['titulo'] as String?) ?? 'Promoción especial';
    final descripcion = (promo['descripcion'] as String?) ?? '';
    final dtoTipo = promo['descuento_tipo'] as String? ?? 'porcentaje';
    final dtoValor = promo['descuento_valor'];
    final hayDescuento = (dtoValor is num && dtoValor > 0) || (dtoValor is String && dtoValor.isNotEmpty && dtoValor != '0');
    final planId = promo['plan_id'] as int?;

    final dtoTexto = !hayDescuento ? null : dtoTipo == 'porcentaje' ? '-${_limpiaNum(dtoValor)}% desc.' : '-\$${_formateaCop(dtoValor)} COP desc.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFEC4899)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_offer_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(titulo, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white))),
            ],
          ),
          if (descripcion.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(descripcion, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.92), height: 1.4)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (dtoTexto != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Text(dtoTexto, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF7C3AED))),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(_formatearCuentaRegresiva(_promoSegundos), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
          if (planId != null) const SizedBox(height: 8),
          if (planId != null)
            Text('Aplica al plan seleccionado · descuento automático en la web', style: TextStyle(fontSize: 10.5, color: Colors.white.withOpacity(0.75), height: 1.3)),
        ],
      ),
    );
  }

  String _limpiaNum(dynamic v) => v is num ? (v == v.roundToDouble() ? v.toInt().toString() : v.toString()) : v?.toString() ?? '0';

  String _formateaCop(dynamic v) {
    final n = v is num ? v : double.tryParse(v?.toString() ?? '0') ?? 0;
    return n.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }

  Future<void> _redeemCode() async {
    final code = _redeemController.text.trim();
    if (code.isEmpty || _redeeming) return;

    setState(() {
      _redeeming = true;
      _redeemError = null;
      _redeemSuccess = null;
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final data = await api.redeemPromoCode(code);
      final auth = Provider.of<AuthService>(context, listen: false);
      await auth.fetchProfile();

      if (!mounted) return;
      setState(() {
        _redeeming = false;
        _isPremium = auth.user?['access_level'] == 'premium' || auth.user?['access_level'] == 'early_bird';
        _redeemSuccess = (data['message'] as String?) ?? '¡Código canjeado! Ahora tienes acceso Premium';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _redeeming = false;
        _redeemError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _buildRedeemCodeSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (_redeemSuccess != null) ? AppColors.success.withOpacity(0.6) : (_redeemError != null) ? AppColors.error.withOpacity(0.6) : (isDark ? AppColors.darkBorder : AppColors.border),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.redeem_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              const Expanded(child: Text('Tengo un código promocional', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 4),
          Text('Si recibiste un código de Saber+, canjéalo aquí.', style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary, height: 1.4)),
          const SizedBox(height: 12),
          if (_isPremium && _redeemSuccess != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.successDark, size: 24),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_redeemSuccess!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.successDark))),
                ],
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _redeemController,
                    enabled: !_redeeming,
                    textCapitalization: TextCapitalization.characters,
                    style: TextStyle(color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1.2),
                    decoration: InputDecoration(
                      hintText: 'Ingresa tu código',
                      hintStyle: TextStyle(color: AppColors.textDisabled, fontSize: 13, fontWeight: FontWeight.w500),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _redeemCode(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _redeeming ? null : _redeemCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: _redeeming ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Canjear', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (_redeemError != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_redeemError!, style: TextStyle(fontSize: 12, color: AppColors.error, height: 1.3))),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPromoCodeField(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.redeem_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _promoCodeController,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 1.2),
              decoration: InputDecoration(
                hintText: '¿Tienes un código promocional?',
                hintStyle: TextStyle(color: AppColors.textDisabled, fontSize: 13, fontWeight: FontWeight.w500),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 16),
          const Text('Desbloquea tu potencial', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Acceso ilimitado a simulacros, retos diarios, predicción ICFES, análisis de errores y mucho más.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.9), height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitsSection(bool isDark) {
    final benefits = [
      {'icon': Icons.assignment_rounded, 'title': 'Simulacros ilimitados', 'desc': 'Practica sin restricciones'},
      {'icon': Icons.flash_on_rounded, 'title': 'Retos diarios', 'desc': 'Gana XP todos los días'},
      {'icon': Icons.insights_rounded, 'title': 'Predicción ICFES', 'desc': 'Conoce tu puntaje estimado'},
      {'icon': Icons.analytics_rounded, 'title': 'Análisis de errores', 'desc': 'Descubre en qué fallas'},
      {'icon': Icons.emoji_events_rounded, 'title': 'Gamificación completa', 'desc': 'Badges, ranking y más'},
      {'icon': Icons.block_rounded, 'title': 'Sin anuncios', 'desc': 'Estudia sin interrupciones'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Qué incluye Premium', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
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

  Widget _buildBillingUnavailableCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border, width: 1),
        boxShadow: [BoxShadow(color: AppColors.shadowSm, blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.12), shape: BoxShape.circle),
            child: const Icon(Icons.hourglass_top_rounded, color: AppColors.warningDark, size: 28),
          ),
          const SizedBox(height: 16),
          const Text('Pago móvil disponible próximamente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Mientras tanto puedes seguir estudiando gratis: simulacros de diagnóstico, retos, ranking y los cursos básicos siguen disponibles para ti.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.5, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildPlansSection(List<Plan> displayPlans, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Elige tu plan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        ...displayPlans.map((plan) {
          final index = _plans.indexOf(plan);
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
          border: Border.all(color: isSelected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.border), width: isSelected ? 2.5 : 1),
          boxShadow: isSelected ? [BoxShadow(color: AppColors.primary.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 6))] : [BoxShadow(color: AppColors.shadowSm, blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(plan.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary))),
                if (isPopular)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(20)),
                    child: const Text('RECOMENDADO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(plan.description, style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_displayPrice(plan), style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: AppColors.primary)),
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
                Icon(isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: isSelected ? AppColors.primary : (isDark ? AppColors.darkTextTertiary : AppColors.textTertiary), size: 22),
                const SizedBox(width: 8),
                Text(isSelected ? 'Plan seleccionado' : 'Tocar para seleccionar', style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: isSelected ? AppColors.primary : (isDark ? AppColors.darkTextTertiary : AppColors.textTertiary))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonSection(bool isDark) {
    final features = [
      {'feature': 'Simulacros ICFES', 'free': '3 simulacros', 'premium': 'Ilimitados'},
      {'feature': 'Cursos de repaso', 'free': '3 cursos', 'premium': 'Todos'},
      {'feature': 'Retos diarios', 'free': 'No', 'premium': 'Sí'},
      {'feature': 'Predicción ICFES', 'free': 'No', 'premium': 'Sí'},
      {'feature': 'Análisis de errores', 'free': 'No', 'premium': 'Sí'},
      {'feature': 'Sin anuncios', 'free': 'No', 'premium': 'Sí'},
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
          Row(
            children: [
              const Expanded(flex: 2, child: Text('Característica', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey))),
              const Expanded(child: Text('Free', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textTertiary))),
              const Expanded(child: Text('Premium', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary))),
            ],
          ),
          const Divider(height: 20),
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

  Widget _buildFaqSection(bool isDark) {
    final faqs = [
      {
        'q': '¿Es una suscripción? ¿Me cobrarán cada mes?',
        'a': 'NO. Es un PAGO ÚNICO DE POR VIDA. Pagas una sola vez y obtienes acceso Premium completo para siempre. No hay cobros automáticos, no hay renovación, no hay cargos sorpresa.'
      },
      {
        'q': '¿Qué métodos de pago aceptan?',
        'a': _usePlayBilling
            ? 'El pago se procesa de forma segura con Google Play. Puedes usar cualquier método asociado a tu cuenta de Google.'
            : 'Usamos Wompi: tarjetas de crédito, débito, PSE, Nequi y Bancolombia.'
      },
      {
        'q': '¿Qué incluye el plan gratuito?',
        'a': 'El plan de prueba (Trial) incluye 3 simulacros y 3 cursos de repaso, con acceso limitado. Es ideal para conocer la plataforma.'
      },
      {
        'q': 'Cambio de teléfono o reinstalé la app, ¿pierdo mi Premium?',
        'a': 'No. Tu Premium está asociado a tu cuenta de Saber+: inicia sesión con el mismo correo y lo recuperarás. Si compraste con Google Play, también puedes usar el botón "Restaurar compras".'
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
        Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(answer, style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary, height: 1.5))),
      ],
    );
  }

  Widget _buildUpgradeButton() {
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
                          ? 'Comprar acceso de por vida · ${_displayPrice(_plans[_selectedPlanIndex!])}'
                          : 'Comprar acceso de por vida',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildRestoreButton() {
    return Center(
      child: TextButton.icon(
        onPressed: _restoring ? null : _handleRestore,
        icon: _restoring ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.restore_rounded, size: 18),
        label: const Text('Restaurar compras'),
        style: TextButton.styleFrom(foregroundColor: AppColors.primary, textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _PremiumSuccessDialog extends StatefulWidget {
  const _PremiumSuccessDialog({required this.planName});
  final String planName;
  @override
  State<_PremiumSuccessDialog> createState() => _PremiumSuccessDialogState();
}

class _PremiumSuccessDialogState extends State<_PremiumSuccessDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _scale = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
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
                  gradient: LinearGradient(colors: [AppColors.success, AppColors.successDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
              ),
            ),
            const SizedBox(height: 20),
            const Text('¡Ahora eres Premium!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Tu PAGO ÚNICO fue verificado con éxito. Saber+ Premium está activo PARA SIEMPRE.\n\nNo hay cobros automáticos, ni renovaciones. El acceso es tuyo definitivamente.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.6, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(20)),
              child: Text(widget.planName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.successDark)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('¡A estudiar!', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}