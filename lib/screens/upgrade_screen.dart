// screens/upgrade_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../widgets/global_scaffold.dart';
import '../models/plan.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/app_logger.dart';

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({Key? key}) : super(key: key);

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  bool _loading = true;
  bool _processing = false;
  List<Plan> _plans = [];
  int? _selectedPlanIndex;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() => _loading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final plans = await api.getActivePlans();
      
      setState(() {
        _plans = plans;
        if (plans.isNotEmpty) {
          _selectedPlanIndex = 0; // Seleccionar el primero por defecto
        }
      });
    } catch (e) {
      _showError('Error al cargar planes: $e');
    } finally {
      setState(() => _loading = false);
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

    final data = await api.createWompiPayment(
      planId: selectedPlan.id,
    );

    final String checkoutUrl = data['checkout_url'];
    
    // DEPURACIÓN: Ver la URL
    AppLogger.d('Wompi URL: $checkoutUrl');
    
    final uri = Uri.parse(checkoutUrl);

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened) {
      throw Exception('No se pudo abrir Wompi');
    }
  } catch (e) {
    _showError('No se pudo iniciar el pago: $e');
    AppLogger.e('Error en upgrade', e); // DEPURACIÓN
  } finally {
    if (mounted) {
      setState(() => _processing = false);
    }
  }
}

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
      ),
    );
  }

  Widget _buildPlanCard(Plan plan, int index) {
    final isSelected = _selectedPlanIndex == index;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.stepInactive,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado del plan
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plan.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (plan.isPremium)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'POPULAR',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Precio
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.formattedPrice,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                Text(
                  plan.period,
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Características
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: plan.features.map((feature) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        feature.included ? Icons.check_circle : Icons.remove_circle,
                        color: feature.included ? AppColors.success : AppColors.textDisabled,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          feature.text,
                          style: TextStyle(
                            fontSize: 14,
                            color: feature.included ? Colors.black : AppColors.textMuted,
                            decoration: feature.included ? null : TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            
            const SizedBox(height: 24),
            
            // Botón de selección
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _selectedPlanIndex = index);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected ? AppColors.primary : AppColors.stepInactive,
                  foregroundColor: isSelected ? AppColors.textOnPrimary : Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isSelected ? '✓ SELECCIONADO' : 'SELECCIONAR PLAN',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlobalScaffold(
      currentIndex: 0,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Planes Disponibles',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _plans.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 60,
                                color: AppColors.textDisabled,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No hay planes disponibles',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: AppColors.textDisabled,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _loadPlans,
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Hero section
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primary.withOpacity(0.1),
                                      AppColors.purple.withOpacity(0.1),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.workspace_premium,
                                      size: 64,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Desbloquea Todo Tu Potencial',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Elige el plan que mejor se adapte a tus necesidades y prepárate para el éxito',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 32),
                              
                              // Lista de planes
                              Column(
                                children: _plans.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final plan = entry.value;
                                  return Padding(
                                    padding: EdgeInsets.only(
                                      bottom: index == _plans.length - 1 ? 0 : 16,
                                    ),
                                    child: _buildPlanCard(plan, index),
                                  );
                                }).toList(),
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // Botón de compra
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _processing || _selectedPlanIndex == null
                                      ? null
                                      : _handleUpgrade,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: AppColors.textOnPrimary,
                                    padding: const EdgeInsets.symmetric(vertical: 18),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _processing
                                      ? const SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.textOnPrimary,
                                          ),
                                        )
                                      : const Text(
                                          'CONTINUAR AL PAGO',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Texto informativo
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'Pago seguro procesado por Wompi. Podrás cancelar en cualquier momento.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textTertiary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}