import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_colors.dart';

/// ✅ PT6 (transformación 2026-11): Tour de bienvenida post-login.
///
/// Se muestra UNA sola vez al primer inicio de sesión tras autenticarse
/// (flag `onboarding_completed` en SharedPreferences, marcado SOLO al
/// completar o saltar — a diferencia del `first_time` del carrusel
/// pre-login que se marcaba al arrancar).
///
/// - 5 pasos con avance/retroceso y botón "Saltar" (no bloquea nada).
/// - Adaptable a móvil y web (ancho máximo centrado en escritorio).
/// - Re-lanzable desde Configuración ("Ver tour de bienvenida").
class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onFinish;

  const OnboardingScreen({super.key, this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _steps = [
    _OnboardingStep(
      icon: Icons.waving_hand_rounded,
      color: AppColors.primary,
      title: '¡Bienvenido a Saber+!',
      description:
          'Tu plataforma colombiana para prepararte para las Pruebas Saber 11 '
          'del ICFES. Estudia a tu ritmo, en móvil o web.',
    ),
    _OnboardingStep(
      icon: Icons.menu_book_rounded,
      color: AppColors.accent,
      title: 'Descubre tus cursos',
      description:
          'Explora los cursos por área: Lectura crítica, Matemáticas, '
          'Sociales, Naturales e Inglés. Cada curso tiene lecciones, '
          'videos y cuestionarios.',
    ),
    _OnboardingStep(
      icon: Icons.assignment_rounded,
      color: AppColors.purple,
      title: 'Prepárate con simulacros',
      description:
          'Realiza simulacros con el formato real del ICFES, con tiempo '
          'cronometrado, revisión de respuestas y explicaciones.',
    ),
    _OnboardingStep(
      icon: Icons.emoji_events_rounded,
      color: AppColors.success,
      title: 'Gana XP e insignias',
      description:
          'Cada simulacro y reto te da XP y alimenta tu racha diaria. '
          'Sube de nivel, desbloquea insignias y compite en el ranking.',
    ),
    _OnboardingStep(
      icon: Icons.insights_rounded,
      color: AppColors.sky,
      title: 'Consulta tu progreso',
      description:
          'Sigue tu evolución por área, compara tu puntaje con otros '
          'estudiantes y obtén tu predicción de puntaje ICFES.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    if (!mounted) return;
    if (widget.onFinish != null) {
      widget.onFinish!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLast = _currentPage == _steps.length - 1;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                // ── Barra superior: Saltar ──
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextButton(
                      onPressed: _finish,
                      child: Text(
                        'Saltar',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Páginas ──
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _steps.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (context, i) {
                      final step = _steps[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: step.color.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(step.icon,
                                  size: 56, color: step.color),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              step.title,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              step.description,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.6,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // ── Indicadores ──
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_steps.length, (i) {
                      final active = i == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 28 : 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.primary
                              : AppColors.textTertiary.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      );
                    }),
                  ),
                ),

                // ── Botones ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
                  child: Row(
                    children: [
                      if (_currentPage > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: BorderSide(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : AppColors.border),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text('Atrás'),
                          ),
                        ),
                      if (_currentPage > 0) const SizedBox(width: 12),
                      Expanded(
                        flex: _currentPage > 0 ? 2 : 1,
                        child: FilledButton(
                          onPressed: () {
                            if (isLast) {
                              _finish();
                            } else {
                              _pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                              );
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            isLast ? 'Comenzar ahora' : 'Siguiente',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
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
    );
  }
}

class _OnboardingStep {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _OnboardingStep({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });
}
