// test/widgets/accessibility_test.dart
// Accessibility widget tests for Saber+ Phase 4
// Verifies semantic labels, tap targets, and contrast

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saberplus_app/core/accessibility/app_accessibility.dart';

void main() {
  group('MinimumTapTarget', () {
    testWidgets('enforces minimum 48x48 tap target', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MinimumTapTarget(
              onTap: () {},
              child: const Icon(Icons.add, size: 20),
            ),
          ),
        ),
      );

      final widget = tester.widget<ConstrainedBox>(find.byType(ConstrainedBox));
      final constraints = widget.constraints;
      expect(constraints.minWidth, equals(48.0));
      expect(constraints.minHeight, equals(48.0));
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MinimumTapTarget(
              onTap: () => tapped = true,
              child: const Text('Tap me'),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(MinimumTapTarget));
      expect(tapped, isTrue);
    });
  });

  group('SemanticButton', () {
    testWidgets('provides semantic label for screen readers', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SemanticButton(
              label: 'Iniciar sesión',
              hint: 'Toca para autenticarte',
              onPressed: () {},
              child: const Text('Login'),
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(SemanticButton));
      expect(semantics.label, equals('Iniciar sesión'));
      expect(semantics.hint, equals('Toca para autenticarte'));
      expect(semantics.isButton, isTrue);
    });

    testWidgets('disabled button has correct semantics', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SemanticButton(
              label: 'Submit',
              isEnabled: false,
              child: Text('Submit'),
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(SemanticButton));
      expect(semantics.isEnabled, isFalse);
    });
  });

  group('SemanticImage', () {
    testWidgets('provides semantic label for non-decorative images', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SemanticImage(
              label: 'Logo de Saber+',
              image: const Icon(Icons.school, size: 48),
            ),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.byType(SemanticImage));
      expect(semantics.label, equals('Logo de Saber+'));
    });

    testWidgets('decorative images are excluded from semantics', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SemanticImage(
              label: 'Background decoration',
              isDecorative: true,
              image: const Icon(Icons.auto_awesome, size: 48),
            ),
          ),
        ),
      );

      // Decorative images should be excluded
      expect(find.byType(ExcludeSemantics), findsOneWidget);
    });
  });

  group('LabeledSection', () {
    testWidgets('wraps content with semantic container', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LabeledSection(
              label: 'Sección de simulacros',
              child: Text('Content'),
            ),
          ),
        ),
      );

      expect(find.text('Content'), findsOneWidget);
      expect(find.byType(LabeledSection), findsOneWidget);
    });
  });

  group('AccessibilitySizes', () {
    test('defines correct minimum sizes per Material Design', () {
      expect(AccessibilitySizes.minTapTarget, equals(48.0));
      expect(AccessibilitySizes.minTouchTarget, equals(44.0));
      expect(AccessibilitySizes.minReadableFontSize, equals(12.0));
      expect(AccessibilitySizes.minBodyFontSize, equals(14.0));
      expect(AccessibilitySizes.minStrokeWidth, equals(1.5));
      expect(AccessibilitySizes.focusBorderWidth, equals(2.0));
    });
  });

  group('SemanticsLabels', () {
    test('defines all navigation labels', () {
      expect(SemanticsLabels.navHome, isNotEmpty);
      expect(SemanticsLabels.navChallenges, isNotEmpty);
      expect(SemanticsLabels.navStats, isNotEmpty);
      expect(SemanticsLabels.navProfile, isNotEmpty);
    });

    test('defines all auth labels', () {
      expect(SemanticsLabels.loginButton, isNotEmpty);
      expect(SemanticsLabels.registerButton, isNotEmpty);
      expect(SemanticsLabels.emailField, isNotEmpty);
      expect(SemanticsLabels.passwordField, isNotEmpty);
    });

    test('defines all quiz labels', () {
      expect(SemanticsLabels.submitAnswer, isNotEmpty);
      expect(SemanticsLabels.nextQuestion, isNotEmpty);
      expect(SemanticsLabels.finishQuiz, isNotEmpty);
      expect(SemanticsLabels.quizTimer, isNotEmpty);
    });
  });
}
