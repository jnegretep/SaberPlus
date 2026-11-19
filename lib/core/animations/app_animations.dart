// lib/core/animations/app_animations.dart
// Centralized animation system for Saber+ Premium UI
// All durations, curves, and reusable animation patterns live here.

import 'package:flutter/material.dart';

class AppAnimations {
  AppAnimations._();

  // ── Durations ──
  static const Duration instant = Duration(milliseconds: 50);
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration slower = Duration(milliseconds: 600);
  static const Duration pageTransition = Duration(milliseconds: 300);

  // ── Curves ──
  static const Curve defaultCurve = Curves.easeOutCubic;
  static const Curve enterCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;
  static const Curve bounceCurve = Curves.elasticOut;
  static const Curve smoothCurve = Curves.easeInOutCubic;
  static const Curve decelerateCurve = Curves.decelerate;

  // ── Staggered Animation Helper ──
  /// Returns the interval for a staggered animation.
  /// [index] is the item index, [total] is total items,
  /// [beginOffset] is the fraction of the total duration before the first item starts.
  static Interval staggerInterval(int index, int total, {double beginOffset = 0.0}) {
    final itemDuration = (1.0 - beginOffset) / total;
    final start = beginOffset + (index * itemDuration);
    final end = start + itemDuration;
    return Interval(start.clamp(0.0, 1.0), end.clamp(0.0, 1.0));
  }

  // ── Fade + Slide Transition ──
  static Widget fadeSlide({
    required Animation<double> animation,
    required Widget child,
    Offset beginOffset = const Offset(0, 0.08),
    bool fade = true,
  }) {
    final curved = CurvedAnimation(parent: animation, curve: enterCurve);

    Widget result = child;
    if (fade) {
      result = FadeTransition(opacity: curved, child: result);
    }
    result = SlideTransition(
      position: Tween(begin: beginOffset, end: Offset.zero).animate(curved),
      child: result,
    );
    return result;
  }

  // ── Scale + Fade Transition ──
  static Widget scaleFade({
    required Animation<double> animation,
    required Widget child,
    double beginScale = 0.92,
  }) {
    final curved = CurvedAnimation(parent: animation, curve: enterCurve);
    return ScaleTransition(
      scale: Tween(begin: beginScale, end: 1.0).animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    );
  }
}

// ── Staggered Grid/List Animation ──
/// Wraps children to appear one by one with a stagger delay.
class StaggeredChildren extends StatefulWidget {
  final List<Widget> children;
  final Duration itemDelay;
  final Duration itemDuration;
  final Curve curve;
  final Offset slideOffset;
  final bool fade;

  const StaggeredChildren({
    super.key,
    required this.children,
    this.itemDelay = const Duration(milliseconds: 60),
    this.itemDuration = const Duration(milliseconds: 300),
    this.curve = Curves.easeOutCubic,
    this.slideOffset = const Offset(0, 0.06),
    this.fade = true,
  });

  @override
  State<StaggeredChildren> createState() => _StaggeredChildrenState();
}

class _StaggeredChildrenState extends State<StaggeredChildren>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _controllers = List.generate(widget.children.length, (i) {
      return AnimationController(
        vsync: this,
        duration: widget.itemDuration,
      );
    });
    _animations = _controllers
        .map((c) => c.drive(CurveTween(curve: widget.curve)))
        .toList();

    // Stagger the start
    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(widget.itemDelay * i, () {
        if (mounted) _controllers[i].forward();
      });
    }
  }

  @override
  void didUpdateWidget(covariant StaggeredChildren oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.children.length != widget.children.length) {
      for (final c in _controllers) {
        c.dispose();
      }
      _initAnimations();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(widget.children.length, (i) {
        return AnimatedBuilder(
          animation: _animations[i],
          builder: (context, child) {
            final t = _animations[i].value;
            return Opacity(
              opacity: widget.fade ? t : 1.0,
              child: Transform.translate(
                offset: widget.slideOffset * (1 - t),
                child: child,
              ),
            );
          },
          child: widget.children[i],
        );
      }),
    );
  }
}

// ── Shimmer Loading Placeholder ──
/// A premium shimmer effect for loading states.
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const ShimmerBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final highlightColor =
        isDark ? const Color(0xFF475569) : const Color(0xFFF1F5F9);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * _controller.value, 0),
              end: Alignment(1.0 + 2.0 * _controller.value, 0),
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

// ── Premium Press Scale Effect ──
/// Wraps any widget to add a press-scale micro-interaction.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final Duration duration;

  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.duration = const Duration(milliseconds: 120),
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      lowerBound: widget.pressedScale,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _controller.drive(CurveTween(curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTapDown(TapDownDetails _) async {
    await _controller.reverse();
  }

  Future<void> _handleTapUp(TapUpDetails _) async {
    await _controller.forward();
    widget.onTap?.call();
  }

  Future<void> _handleTapCancel() async {
    await _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null ? _handleTapDown : null,
      onTapUp: widget.onTap != null ? _handleTapUp : null,
      onTapCancel: widget.onTap != null ? _handleTapCancel : null,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

// ── Animated Score Circle (Premium) ──
/// Animates the circular progress indicator with counting number.
class AnimatedScoreCircle extends StatefulWidget {
  final double score;
  final double maxScore;
  final Color color;
  final double size;
  final double strokeWidth;

  const AnimatedScoreCircle({
    super.key,
    required this.score,
    this.maxScore = 500,
    this.color = const Color(0xFF1E4ED8),
    this.size = 85,
    this.strokeWidth = 12,
  });

  @override
  State<AnimatedScoreCircle> createState() => _AnimatedScoreCircleState();
}

class _AnimatedScoreCircleState extends State<AnimatedScoreCircle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.slow,
    );
    _animation =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedScoreCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.score != widget.score) {
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
    final percent =
        (widget.score.clamp(0, widget.maxScore)) / widget.maxScore;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
    final textColor = isDark ? const Color(0xFFF1F5F9) : widget.color;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final currentPercent = percent * _animation.value;
          final currentScore = widget.score * _animation.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: CircularProgressIndicator(
                  value: currentPercent,
                  strokeWidth: widget.strokeWidth,
                  backgroundColor: bgColor,
                  valueColor: AlwaysStoppedAnimation(widget.color),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentScore.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: widget.size * 0.42,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'de ${widget.maxScore.toInt()}',
                    style: TextStyle(
                      fontSize: widget.size * 0.16,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
