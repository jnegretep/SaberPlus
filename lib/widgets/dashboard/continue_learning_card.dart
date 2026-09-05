// lib/widgets/dashboard/continue_learning_card.dart
// Saber+ - Card "Continua donde quedaste"
//
// Muestra el ultimo curso/simulacro que el usuario estaba viendo,
// para que pueda continuar rapidamente sin buscarlo.
// Se basa en SharedPreferences para recordar el ultimo curso abierto.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/animations/app_animations.dart';
import '../../config/navigation.dart';

class ContinueLearningCard extends StatefulWidget {
  const ContinueLearningCard({super.key});

  /// ✅ Guarda el ultimo curso accedido (MÉTODO PÚBLICO ESTÁTICO)
  static Future<void> saveLastAccessed({
    required int courseId,
    required String courseName,
    required String category,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_course_name', courseName);
    await prefs.setInt('last_course_id', courseId);
    await prefs.setString('last_course_category', category);
  }

  @override
  State<ContinueLearningCard> createState() => _ContinueLearningCardState();
}

class _ContinueLearningCardState extends State<ContinueLearningCard> {
  String? _lastCourseName;
  int? _lastCourseId;
  String? _lastCategory;

  @override
  void initState() {
    super.initState();
    _loadLastAccessed();
  }

  Future<void> _loadLastAccessed() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('last_course_name');
    final id = prefs.getInt('last_course_id');
    final category = prefs.getString('last_course_category');

    if (mounted && name != null && id != null) {
      setState(() {
        _lastCourseName = name;
        _lastCourseId = id;
        _lastCategory = category;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lastCourseName == null || _lastCourseId == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final icon = _getCategoryIcon(_lastCategory);
    final color = _getCategoryColor(_lastCategory);

    return PressScale(
      onTap: () {
        if (_lastCourseId != null && _lastCourseName != null) {
          Nav.goCourseContents(
            context,
            courseId: _lastCourseId!,
            courseName: _lastCourseName!,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.08), color.withOpacity(0.03)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Continua donde quedaste',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _lastCourseName!,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String? category) {
    switch (category) {
      case 'simulacros':
        return Icons.assignment_rounded;
      case 'courses':
        return Icons.menu_book_rounded;
      case 'retos':
        return Icons.emoji_events_rounded;
      default:
        return Icons.school_rounded;
    }
  }

  Color _getCategoryColor(String? category) {
    switch (category) {
      case 'simulacros':
        return AppColors.primary;
      case 'courses':
        return AppColors.accent;
      case 'retos':
        return AppColors.success;
      default:
        return AppColors.primary;
    }
  }
}