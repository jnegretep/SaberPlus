import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class PrimaryCTA extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const PrimaryCTA({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  State<PrimaryCTA> createState() => _PrimaryCTAState();
}

class _PrimaryCTAState extends State<PrimaryCTA>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.96,
      upperBound: 1.0,
    )..value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    await _controller.reverse();
    await _controller.forward();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _controller,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: _onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            elevation: 6,
            shadowColor: AppColors.primary.withOpacity(0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
