// lib/core/animations/page_transitions.dart
// Premium page transition animations for Saber+ Phase 4
// SharedAxis transitions, slide-in, fade+scale wrappers
// Also includes haptic feedback utilities

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_animations.dart';

// ── Page Transition Wrappers ──

/// Wraps a page's content with a fade + slide-up entrance animation.
/// Use as the body of any screen for a consistent premium feel.
class AnimatedPageWrapper extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Offset slideOffset;

  const AnimatedPageWrapper({
    super.key,
    required this.child,
    this.duration = AppAnimations.slow,
    this.slideOffset = const Offset(0, 0.04),
  });

  @override
  State<AnimatedPageWrapper> createState() => _AnimatedPageWrapperState();
}

class _AnimatedPageWrapperState extends State<AnimatedPageWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppAnimations.enterCurve,
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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final t = _animation.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: widget.slideOffset * (1 - t) * 100,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Wraps a widget with a scale-up + fade entrance animation.
/// Ideal for cards and modal content.
class AnimatedScaleEntrance extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double beginScale;

  const AnimatedScaleEntrance({
    super.key,
    required this.child,
    this.duration = AppAnimations.normal,
    this.beginScale = 0.94,
  });

  @override
  State<AnimatedScaleEntrance> createState() => _AnimatedScaleEntranceState();
}

class _AnimatedScaleEntranceState extends State<AnimatedScaleEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppAnimations.enterCurve,
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
    return ScaleTransition(
      scale: Tween(begin: widget.beginScale, end: 1.0).animate(_animation),
      child: FadeTransition(
        opacity: _animation,
        child: widget.child,
      ),
    );
  }
}

/// Custom PageTransitionsBuilder with shared axis (horizontal slide)
/// for GoRouter / MaterialApp.pageTransitionsTheme
class SharedAxisPageTransitionsBuilder extends PageTransitionsBuilder {
  const SharedAxisPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Enter: slide from right + fade
    final enterSlide = Tween(
      begin: const Offset(0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: AppAnimations.enterCurve,
    ));

    final enterFade = CurvedAnimation(
      parent: animation,
      curve: AppAnimations.enterCurve,
    );

    // Exit: slide to left + fade
    final exitSlide = Tween(
      begin: Offset.zero,
      end: const Offset(-0.08, 0),
    ).animate(CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppAnimations.exitCurve,
    ));

    final exitFade = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppAnimations.exitCurve,
    );

    return SlideTransition(
      position: exitSlide,
      child: FadeTransition(
        opacity: exitFade,
        child: SlideTransition(
          position: enterSlide,
          child: FadeTransition(
            opacity: enterFade,
            child: child,
          ),
        ),
      ),
    );
  }
}

// ── Haptic Feedback Utilities ──

/// Premium haptic feedback for Saber+ interactions
class AppHaptics {
  AppHaptics._();

  /// Light impact — for button presses, toggles
  static void lightImpact() {
    HapticFeedback.lightImpact();
  }

  /// Medium impact — for card presses, navigation changes
  static void mediumImpact() {
    HapticFeedback.mediumImpact();
  }

  /// Heavy impact — for significant actions (submit, delete)
  static void heavyImpact() {
    HapticFeedback.heavyImpact();
  }

  /// Selection click — for scrolling through options, picker changes
  static void selectionClick() {
    HapticFeedback.selectionClick();
  }

  /// Success feedback — light + slight delay
  static Future<void> success() async {
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    HapticFeedback.lightImpact();
  }

  /// Error feedback — heavy + medium
  static Future<void> error() async {
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.mediumImpact();
  }
}

// ── Animated Counter ──

/// Animates a number counting up/down with formatting
class AnimatedCounter extends StatefulWidget {
  final int value;
  final Duration duration;
  final TextStyle? style;
  final String Function(int)? formatter;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.duration = AppAnimations.slow,
    this.style,
    this.formatter,
  });

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  int _previousValue = 0;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.value;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppAnimations.defaultCurve,
    );
    // Start fully shown if initial value
    if (widget.value != 0) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _previousValue = oldWidget.value;
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final current = (_previousValue + (widget.value - _previousValue) * _animation.value).round();
        final formatted = widget.formatter?.call(current) ?? current.toString();
        return Text(formatted, style: widget.style);
      },
    );
  }
}
