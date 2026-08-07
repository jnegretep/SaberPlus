// lib/screens/welcome_screen.dart
// Saber+ — Premium Welcome/Onboarding Screen
// Animated pages with smooth transitions

import 'package:flutter/material.dart';
import '../config/navigation.dart';
import '../core/theme/app_colors.dart';
import '../core/animations/app_animations.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Entrance animation
  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (!mounted) return;

    if (_currentPage < 1) {
      try {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => _currentPage = 1);
      }
    } else {
      if (!mounted) return;
      Nav.goLogin(context);
    }
  }

  void _goToLogin() {
    if (!mounted) return;
    Nav.goLogin(context);
  }

  Widget _buildIndicator(bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? AppColors.primary : AppColors.stepInactive,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ───────── LOGO (animated entrance) ─────────
            FadeTransition(
              opacity: _entranceFade,
              child: ScaleTransition(
                scale: Tween(begin: 0.85, end: 1.0).animate(_entranceFade),
                child: Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Image.asset(
                    'assets/images/saberplus.png',
                    height: 170,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const SizedBox(
                        height: 170,
                        child: Center(
                          child:
                              Icon(Icons.school, size: 80, color: AppColors.primary),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

            // ───────── PAGES ─────────
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) {
                  if (!mounted) return;
                  setState(() => _currentPage = i);
                },
                children: const [
                  _WelcomePage(
                    imagePath: 'assets/images/welcome1.png',
                    title: 'Prepárate para las Pruebas Saber 11',
                    subtitle:
                        'Mejora tus competencias, realiza simulacros y reta tus habilidades.',
                    imageHeightFactor: 0.90,
                    textTopOverlap: 22,
                    imageLiftFactor: 0.08,
                    textLiftFactor: 0.14,
                  ),
                  _WelcomePage(
                    imagePath: 'assets/images/welcome2.png',
                    title: 'Aprende, practica y supera tus metas',
                    subtitle:
                        'Cursos, simulacros y retos diseñados para llevarte al siguiente nivel.',
                    imageHeightFactor: 0.60,
                    textTopOverlap: 8,
                    imageLiftFactor: 0.00,
                    textLiftFactor: 0.00,
                  ),
                ],
              ),
            ),

            // ───────── INDICATORS ─────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildIndicator(_currentPage == 0),
                _buildIndicator(_currentPage == 1),
              ],
            ),

            const SizedBox(height: 20),

            // ───────── BUTTON ─────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _nextPage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                    shadowColor: AppColors.primary.withOpacity(0.3),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _currentPage == 0 ? 'Siguiente' : 'Comenzar',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textOnPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _currentPage == 0
                            ? Icons.arrow_forward_rounded
                            : Icons.rocket_launch_rounded,
                        color: AppColors.textOnPrimary,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ───────── PAGE WIDGET ─────────
class _WelcomePage extends StatelessWidget {
  final String imagePath;
  final String title;
  final String subtitle;

  final double imageHeightFactor;
  final double textTopOverlap;
  final double imageLiftFactor;
  final double textLiftFactor;

  const _WelcomePage({
    required this.imagePath,
    required this.title,
    required this.subtitle,
    this.imageHeightFactor = 0.42,
    this.textTopOverlap = 12,
    this.imageLiftFactor = 0.00,
    this.textLiftFactor = 0.00,
  });

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.of(context).size;
    final availableHeight = viewport.height;

    final contentHeight = availableHeight
        - 170 // logo
        - 20 // espacio
        - 54 // botón
        - 68; // indicadores + padding

    final safeContentHeight = contentHeight < 200 ? 200.0 : contentHeight;
    final imageHeight = safeContentHeight * imageHeightFactor;
    final imageLift = availableHeight * imageLiftFactor;
    final textLift = availableHeight * textLiftFactor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        height: safeContentHeight,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: -imageLift,
              left: 0,
              right: 0,
              child: SizedBox(
                height: imageHeight,
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return SizedBox(
                      height: imageHeight,
                      child: const Center(
                        child: Icon(Icons.image,
                            size: 80, color: AppColors.textDisabled),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: imageHeight - (24 + textTopOverlap) - textLift,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: AppColors.subjectMath,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
