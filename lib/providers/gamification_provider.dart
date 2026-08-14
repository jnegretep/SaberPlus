// lib/providers/gamification_provider.dart
// Saber+ — Provider de gamificación (XP, niveles, rachas, badges)
//
// Se registra en main.dart como ChangeNotifierProvider.
// Carga el estado al iniciar y lo actualiza cuando se gana XP.
// Cachea en memoria para acceso rápido desde cualquier pantalla.

import 'package:flutter/material.dart';
import '../services/gamification_service.dart';
import '../models/gamification_state.dart';
import '../models/ranking_entry.dart';
import '../core/utils/app_logger.dart';

class GamificationProvider extends ChangeNotifier {
  final GamificationService _service = GamificationService();

  // ── Estado ──
  GamificationState _state = GamificationState.empty();
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _error;

  // ── Getters ──
  GamificationState get state => _state;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get error => _error;

  // Atajos para acceso rápido desde la UI
  int get totalXp => _state.xp.total;
  int get level => _state.xp.level;
  int get currentStreak => _state.streak.current;
  int get maxStreak => _state.streak.max;
  double get levelProgressPct => _state.xp.progressPct;
  int get xpToNextLevel => _state.xp.xpToNextLevel;
  int get unlockedBadgesCount => _state.badges.unlockedCount;
  int get totalBadgesCount => _state.badges.totalCount;
  int get todayXp => _state.today.xpEarned;
  int get todaySimulacros => _state.today.simulacros;

  /// Carga el estado inicial. Llamar al iniciar la app o al hacer login.
  Future<void> loadStatus() async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final status = await _service.getStatus();
      if (status != null) {
        _state = status;
        AppLogger.i('GamificationProvider: estado cargado - '
            'XP=${status.xp.total}, nivel=${status.xp.level}, '
            'racha=${status.streak.current}, badges=${status.badges.unlockedCount}');
      } else {
        _error = 'No se pudo cargar la información de gamificación';
      }
    } catch (e) {
      AppLogger.e('GamificationProvider.loadStatus error', e);
      _error = 'Error cargando gamificación: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresca el estado en background (sin mostrar loading).
  Future<void> refresh() async {
    if (_isRefreshing) return;

    _isRefreshing = true;
    notifyListeners();

    try {
      final status = await _service.getStatus();
      if (status != null) {
        _state = status;
        _error = null;
      }
    } catch (e) {
      AppLogger.e('GamificationProvider.refresh error', e);
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  /// Otorga XP al usuario por una acción y actualiza el estado local.
  ///
  /// Retorna [AwardXpResult] con info sobre si subió de nivel o desbloqueó
  /// badges nuevos (para que la UI pueda mostrar celebraciones).
  Future<AwardXpResult?> awardXp({
    required String reason,
    int? xpAmount,
    int? referenceId,
    String? description,
  }) async {
    try {
      final result = await _service.awardXp(
        reason: reason,
        xpAmount: xpAmount,
        referenceId: referenceId,
        description: description,
      );

      if (result != null) {
        // Actualizar estado local inmediatamente con los datos del resultado
        // (sin necesidad de hacer un getStatus completo)
        _applyAwardResult(result);

        // Refrescar el estado completo en background para sincronizar badges
        // y actividad diaria (que pueden no venir completos en awardXp)
        refresh();

        AppLogger.i('GamificationProvider: XP otorgada - '
            '+${result.xpAwarded} XP (${reason}), '
            'total=${result.totalXp}, nivel=${result.level}, '
            'subió=${result.leveledUp}, nuevos badges=${result.newBadges.length}');

        return result;
      }
      return null;
    } catch (e) {
      AppLogger.e('GamificationProvider.awardXp error', e);
      return null;
    }
  }

  /// Aplica el resultado de awardXp al estado local.
  void _applyAwardResult(AwardXpResult result) {
    final newXp = XpInfo(
      total: result.totalXp,
      level: result.level,
      currentLevelXp: _xpForLevel(result.level),
      nextLevelXp: _xpForLevel(result.level + 1),
      progressPct: _calculateProgressPct(result.totalXp, result.level),
      xpToNextLevel: _xpForLevel(result.level + 1) - result.totalXp,
    );

    final newStreak = StreakInfo(
      current: result.currentStreak,
      max: _state.streak.max > result.currentStreak
          ? _state.streak.max
          : result.currentStreak,
      freezeAvailable: _state.streak.freezeAvailable,
      lastActivity: _state.streak.lastActivity,
    );

    // Mover badges recién desbloqueados de "locked" a "unlocked"
    final newUnlocked = [..._state.badges.unlocked, ...result.newBadges];
    final unlockedCodes = result.newBadges.map((b) => b.code).toSet();
    final newLocked = _state.badges.locked
        .where((b) => !unlockedCodes.contains(b.code))
        .toList();

    final newBadges = BadgesInfo(
      unlocked: newUnlocked,
      locked: newLocked,
      totalCount: _state.badges.totalCount,
      unlockedCount: newUnlocked.length,
    );

    _state = GamificationState(
      xp: newXp,
      streak: newStreak,
      badges: newBadges,
      today: _state.today,
    );

    notifyListeners();
  }

  /// Limpia el estado (al cerrar sesión).
  void clear() {
    _state = GamificationState.empty();
    _error = null;
    notifyListeners();
  }

  // ── Helpers para cálculo de nivel (misma fórmula que el backend) ──

  /// XP necesaria para alcanzar un nivel.
  /// Fórmula: (nivel - 1)^2 * 100
  static int _xpForLevel(int level) {
    if (level < 1) return 0;
    return (level - 1) * (level - 1) * 100;
  }

  /// Calcula el progreso (0-100) hacia el siguiente nivel.
  static double _calculateProgressPct(int totalXp, int level) {
    final currentLevelXp = _xpForLevel(level);
    final nextLevelXp = _xpForLevel(level + 1);
    if (nextLevelXp <= currentLevelXp) return 100;
    final pct = (totalXp - currentLevelXp) / (nextLevelXp - currentLevelXp) * 100;
    return pct.clamp(0, 100).toDouble();
  }
}
