// lib/screens/upgrade_screen.dart
// Saber+ - Pantalla de Upgrade Premium (Redisenio Profesional)
//
// Caracteristicas:
// - Diseno premium con gradientes y animaciones
// - Comparativa de planes lado a lado
// - Lista de beneficios con iconos
// - Integracion con Wompi
// - Periodo de prueba (trial)
// - FAQ expandible
// - Mensaje de plan actual si ya es premium

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../models/plan.dart';
import '../core/theme/app_colors.dart';
import '../core/animations/app_animations.dart';
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

    _loadData();
  }

  @override
  void dispose() {
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

  Future<void> _handleUpgrade() async {
    if (_selectedPlanIndex == null || _plans.isEmpty) {
      _showError('Por favor selecciona un plan');
      return;
    }

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

      final data = await api.createWompiPayment(planId: selectedPlan.id);
      final String checkoutUrl = data['checkout_url'];

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

  Future<bool> _showConfirmationDialog(Plan plan) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.payment_rounded, color: AppColors.primary),
                SizedBox(width: 10),
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
                  plan.formattedPrice + ' ' + plan.period,
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
                      Icon(Icons.security_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Pago seguro via Wompi. Seras redirigido a la pagina de pago.',
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

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                                // Hero
                                _buildHeroSection(),
                                const SizedBox(height: 32),

                                // Beneficios
                                _buildBenefitsSection(isDark),
                                const SizedBox(height: 32),

                                // Planes
                                if (_plans.isNotEmpty) ...[
                                  _buildPlansSection(isDark),
                                  const SizedBox(height: 32),
                                ],

                                // Comparativa
                                _buildComparisonSection(isDark),
                                const SizedBox(height: 32),

                                // FAQ
                                _buildFaqSection(isDark),
                                const SizedBox(height: 32),

                                // Boton de upgrade
                                if (!_isPremium) _buildUpgradeButton(),
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
                Text(
                  plan.formattedPrice,
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
      {'q': 'Como funciona el pago?', 'a': 'Usamos Wompi, una plataforma de pago segura. Aceptamos tarjetas de credito, debito, PSE y Nequi. El pago es 100% seguro.'},
      {'q': 'Hay periodo de prueba?', 'a': 'Si! Ofrecemos un periodo de prueba gratis de 7 dias para que pruebes todas las funciones premium sin compromiso.'},
      {'q': 'Puedo cambiar de plan?', 'a': 'Si, puedes cambiar entre el plan mensual y anual cuando quieras. El cambio se aplica al final del periodo actual.'},
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SafeArea(
        child: ElevatedButton(
          onPressed: _processing ? null : _handleUpgrade,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
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
                          ? 'Suscribirme - ${_plans[_selectedPlanIndex!].formattedPrice}'
                          : 'Suscribirme ahora',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
