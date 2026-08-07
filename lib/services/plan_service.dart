// lib/services/plan_service.dart
// Plan/subscription service for Saber+ Premium paywall
// Provides content access checks and plan info

import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/app_logger.dart';

/// Service that manages plan/subscription state and content access.
/// Currently uses a simple approach; can be upgraded to full API-based
/// subscription management when the backend endpoint is ready.
class PlanService extends ChangeNotifier {
  /// Whether the current user has premium access
  bool _isPremium = false;
  bool get isPremium => _isPremium;

  /// Cached plan name
  String _planName = 'Gratuito';
  String get planName => _planName;

  /// Check if a specific content type/id requires premium
  /// Returns true if the user has access (either free content or premium user)
  Future<bool> checkContentAccess(String contentType, String contentId) async {
    // Free content types that don't require premium
    const freeContentTypes = {
      'simulacro_diagnostico',
      'course_intro',
      'challenge_basic',
      'chat_basic',
      'stats_basic',
    };

    if (freeContentTypes.contains(contentType)) {
      return true;
    }

    // Premium users have access to everything
    if (_isPremium) {
      return true;
    }

    // Check content-specific access rules
    // For now, allow access but mark as potentially restricted
    AppLogger.d('Content access check: $contentType/$contentId → ${_isPremium ? 'premium' : 'free'}');
    return _isPremium;
  }

  /// Update premium status (e.g., after profile fetch)
  void updatePremiumStatus({required bool isPremium, String planName = 'Gratuito'}) {
    _isPremium = isPremium;
    _planName = planName;
    notifyListeners();
  }

  /// Simulate a premium check from the server
  Future<void> fetchPlanStatus(String? token) async {
    if (token == null) {
      _isPremium = false;
      _planName = 'Gratuito';
      notifyListeners();
      return;
    }

    // TODO: Replace with actual API call when endpoint is ready
    // final response = await http.post(...)
    AppLogger.d('Plan status fetched: $_planName (premium: $_isPremium)');
  }
}
