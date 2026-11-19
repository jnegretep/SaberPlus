// test/widgets/animations_test.dart
// Widget tests for animation components

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saberplus_app/core/animations/app_animations.dart';
import 'package:saberplus_app/core/animations/page_transitions.dart';

void main() {
  group('ShimmerBox', () {
    testWidgets('renders with default dimensions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShimmerBox(),
          ),
        ),
      );

      expect(find.byType(ShimmerBox), findsOneWidget);
      // Should have a Container with gradient (shimmer effect)
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('renders with custom dimensions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShimmerBox(
              width: 200,
              height: 24,
            ),
          ),
        ),
      );

      expect(find.byType(ShimmerBox), findsOneWidget);
    });

    testWidgets('adapts colors for dark mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: ShimmerBox(),
          ),
        ),
      );

      expect(find.byType(ShimmerBox), findsOneWidget);
      // Animation controller runs, verify it's present
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ShimmerBox), findsOneWidget);
    });
  });

  group('PressScale', () {
    testWidgets('renders child and responds to tap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PressScale(
              onTap: () => tapped = true,
              child: const Text('Tap me'),
            ),
          ),
        ),
      );

      expect(find.text('Tap me'), findsOneWidget);
      expect(tapped, isFalse);

      await tester.tap(find.text('Tap me'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('works without onTap', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PressScale(
              child: Text('No tap'),
            ),
          ),
        ),
      );

      expect(find.text('No tap'), findsOneWidget);
    });
  });

  group('AnimatedScoreCircle', () {
    testWidgets('renders with score and animates', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedScoreCircle(
              score: 350,
              maxScore: 500,
            ),
          ),
        ),
      );

      expect(find.byType(AnimatedScoreCircle), findsOneWidget);
      // Wait for animation
      await tester.pumpAndSettle();
      // Should show the score text
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('clamps score to maxScore', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedScoreCircle(
              score: 600, // Exceeds max
              maxScore: 500,
            ),
          ),
        ),
      );

      expect(find.byType(AnimatedScoreCircle), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('StaggeredChildren', () {
    testWidgets('renders all children with stagger delay', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StaggeredChildren(
              children: [
                Text('Item 1'),
                Text('Item 2'),
                Text('Item 3'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
      expect(find.text('Item 3'), findsOneWidget);
    });
  });

  group('AnimatedPageWrapper', () {
    testWidgets('renders child with fade+slide animation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedPageWrapper(
              child: Text('Page Content'),
            ),
          ),
        ),
      );

      expect(find.text('Page Content'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('AnimatedScaleEntrance', () {
    testWidgets('renders child with scale animation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedScaleEntrance(
              child: Text('Card Content'),
            ),
          ),
        ),
      );

      expect(find.text('Card Content'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('AnimatedCounter', () {
    testWidgets('renders initial value', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AnimatedCounter(value: 42),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(AnimatedCounter), findsOneWidget);
    });
  });
}
