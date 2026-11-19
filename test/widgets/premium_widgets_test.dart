// test/widgets/premium_widgets_test.dart
// Widget tests for PremiumEmptyState and other core widgets

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saberplus_app/core/widgets/empty_state.dart';
import 'package:saberplus_app/core/widgets/theme_toggle.dart';
import 'package:saberplus_app/core/theme/app_colors.dart';

void main() {
  group('PremiumEmptyState', () {
    testWidgets('renders title and subtitle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PremiumEmptyState(
              icon: Icons.inbox_outlined,
              title: 'Sin contenido',
              subtitle: 'Aún no hay nada aquí',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle(); // Wait for animation
      expect(find.text('Sin contenido'), findsOneWidget);
      expect(find.text('Aún no hay nada aquí'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });

    testWidgets('renders CTA button when provided', (tester) async {
      bool ctaPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PremiumEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Error',
              subtitle: 'Sin conexión',
              ctaLabel: 'Reintentar',
              onCta: () => ctaPressed = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      expect(ctaPressed, isTrue);
    });

    testWidgets('does not render CTA when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PremiumEmptyState(
              icon: Icons.inbox_outlined,
              title: 'Vacío',
              subtitle: 'Nada que mostrar',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('uses custom accent color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PremiumEmptyState(
              icon: Icons.star,
              title: 'Premium',
              subtitle: 'Mejora tu plan',
              accentColor: AppColors.accent,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(PremiumEmptyState), findsOneWidget);
    });

    testWidgets('adapts to dark mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: PremiumEmptyState(
              icon: Icons.inbox_outlined,
              title: 'Dark Mode',
              subtitle: 'Modo oscuro',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Dark Mode'), findsOneWidget);
    });
  });

  group('ThemeToggle', () {
    testWidgets('renders all three theme options', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThemeToggle(
              currentMode: ThemeMode.system,
              onModeChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Claro'), findsOneWidget);
      expect(find.text('Oscuro'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
    });

    testWidgets('calls onModeChanged when tapping option', (tester) async {
      ThemeMode? selectedMode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThemeToggle(
              currentMode: ThemeMode.light,
              onModeChanged: (mode) => selectedMode = mode,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Oscuro'));
      expect(selectedMode, equals(ThemeMode.dark));
    });
  });
}
