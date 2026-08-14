// lib/models/gamification_state.dart
// Saber+ — Modelo de estado de gamificación del usuario
// Incluye XP, nivel, racha, badges y actividad diaria.

/// Estado completo de gamificación del usuario.
///
/// Se obtiene desde `/gamification_status.php` y se cachea en memoria
/// por el [GamificationProvider].
class GamificationState {
  final XpInfo xp;
  final StreakInfo streak;
  final BadgesInfo badges;
  final DailyActivity today;

  GamificationState({
    required this.xp,
    required this.streak,
    required this.badges,
    required this.today,
  });

  factory GamificationState.fromJson(Map<String, dynamic> json) {
    return GamificationState(
      xp: XpInfo.fromJson(json['xp'] as Map<String, dynamic>),
      streak: StreakInfo.fromJson(json['streak'] as Map<String, dynamic>),
      badges: BadgesInfo.fromJson(json['badges'] as Map<String, dynamic>),
      today: DailyActivity.fromJson(json['today'] as Map<String, dynamic>),
    );
  }

  /// Estado vacío inicial (antes de cargar).
  static GamificationState empty() => GamificationState(
        xp: XpInfo.empty(),
        streak: StreakInfo.empty(),
        badges: BadgesInfo.empty(),
        today: DailyActivity.empty(),
      );
}

/// Información de XP y nivel del usuario.
class XpInfo {
  final int total;
  final int level;
  final int currentLevelXp;     // XP necesaria para el nivel actual
  final int nextLevelXp;        // XP necesaria para el siguiente nivel
  final double progressPct;     // 0-100, progreso hacia el siguiente nivel
  final int xpToNextLevel;      // XP faltante para subir de nivel

  XpInfo({
    required this.total,
    required this.level,
    required this.currentLevelXp,
    required this.nextLevelXp,
    required this.progressPct,
    required this.xpToNextLevel,
  });

  factory XpInfo.fromJson(Map<String, dynamic> json) {
    return XpInfo(
      total: (json['total'] as num).toInt(),
      level: (json['level'] as num).toInt(),
      currentLevelXp: (json['current_level_xp'] as num).toInt(),
      nextLevelXp: (json['next_level_xp'] as num).toInt(),
      progressPct: (json['progress_pct'] as num).toDouble(),
      xpToNextLevel: (json['xp_to_next_level'] as num).toInt(),
    );
  }

  static XpInfo empty() => XpInfo(
        total: 0,
        level: 1,
        currentLevelXp: 0,
        nextLevelXp: 100,
        progressPct: 0,
        xpToNextLevel: 100,
      );
}

/// Información de racha de días consecutivos.
class StreakInfo {
  final int current;
  final int max;
  final int freezeAvailable;
  final String? lastActivity;

  StreakInfo({
    required this.current,
    required this.max,
    required this.freezeAvailable,
    this.lastActivity,
  });

  factory StreakInfo.fromJson(Map<String, dynamic> json) {
    return StreakInfo(
      current: (json['current'] as num).toInt(),
      max: (json['max'] as num).toInt(),
      freezeAvailable: (json['freeze_available'] as num).toInt(),
      lastActivity: json['last_activity'] as String?,
    );
  }

  static StreakInfo empty() => StreakInfo(
        current: 0,
        max: 0,
        freezeAvailable: 0,
        lastActivity: null,
      );

  /// true si el usuario tiene racha activa (>=1 día)
  bool get isActive => current > 0;
}

/// Información de badges del usuario.
class BadgesInfo {
  final List<Badge> unlocked;
  final List<Badge> locked;
  final int totalCount;
  final int unlockedCount;

  BadgesInfo({
    required this.unlocked,
    required this.locked,
    required this.totalCount,
    required this.unlockedCount,
  });

  factory BadgesInfo.fromJson(Map<String, dynamic> json) {
    final unlockedRaw = (json['unlocked'] as List<dynamic>? ?? []);
    final lockedRaw = (json['locked'] as List<dynamic>? ?? []);

    return BadgesInfo(
      unlocked: unlockedRaw
          .map((e) => Badge.fromJson(e as Map<String, dynamic>))
          .toList(),
      locked: lockedRaw
          .map((e) => Badge.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      unlockedCount: (json['unlocked_count'] as num?)?.toInt() ?? 0,
    );
  }

  static BadgesInfo empty() => BadgesInfo(
        unlocked: [],
        locked: [],
        totalCount: 0,
        unlockedCount: 0,
      );

  /// Porcentaje de badges desbloqueados (0-100)
  double get completionPct =>
      totalCount > 0 ? (unlockedCount / totalCount * 100) : 0;
}

/// Modelo de un badge/logro.
class Badge {
  final int id;
  final String code;
  final String name;
  final String description;
  final String icon;        // nombre del icono Material
  final String color;       // hex color
  final int xpReward;
  final String category;    // 'simulacros', 'rachas', 'social', 'especial'
  final bool isHidden;
  final String? unlockedAt; // ISO date, null si está bloqueado
  final int? progress;      // progreso actual (para badges bloqueados)
  final int? progressTarget;
  final double? progressPct;

  Badge({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    this.xpReward = 0,
    required this.category,
    this.isHidden = false,
    this.unlockedAt,
    this.progress,
    this.progressTarget,
    this.progressPct,
  });

  factory Badge.fromJson(Map<String, dynamic> json) {
    return Badge(
      id: (json['id'] as num).toInt(),
      code: json['code'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      icon: json['icon'] as String,
      color: json['color'] as String,
      xpReward: (json['xp_reward'] as num?)?.toInt() ?? 0,
      category: json['category'] as String? ?? 'general',
      isHidden: (json['is_hidden'] as bool?) ?? false,
      unlockedAt: json['unlocked_at'] as String?,
      progress: (json['progress'] as num?)?.toInt(),
      progressTarget: (json['progress_target'] as num?)?.toInt(),
      progressPct: (json['progress_pct'] as num?)?.toDouble(),
    );
  }

  bool get isUnlocked => unlockedAt != null;
}

/// Actividad diaria del usuario (hoy).
class DailyActivity {
  final int simulacros;
  final int retos;
  final int cursos;
  final int questionsAnswered;
  final int xpEarned;

  DailyActivity({
    required this.simulacros,
    required this.retos,
    required this.cursos,
    required this.questionsAnswered,
    required this.xpEarned,
  });

  factory DailyActivity.fromJson(Map<String, dynamic> json) {
    return DailyActivity(
      simulacros: (json['simulacros'] as num?)?.toInt() ?? 0,
      retos: (json['retos'] as num?)?.toInt() ?? 0,
      cursos: (json['cursos'] as num?)?.toInt() ?? 0,
      questionsAnswered: (json['questions_answered'] as num?)?.toInt() ?? 0,
      xpEarned: (json['xp_earned'] as num?)?.toInt() ?? 0,
    );
  }

  static DailyActivity empty() => DailyActivity(
        simulacros: 0,
        retos: 0,
        cursos: 0,
        questionsAnswered: 0,
        xpEarned: 0,
      );

  /// true si el usuario ha hecho alguna actividad hoy
  bool get hasActivity =>
      simulacros > 0 || retos > 0 || cursos > 0 || questionsAnswered > 0;
}

/// Resultado de otorgar XP al usuario.
class AwardXpResult {
  final int xpAwarded;      // total otorgado (base + bonus)
  final int xpBase;
  final int xpBonus;
  final int totalXp;
  final int level;
  final bool leveledUp;
  final int? newLevel;
  final List<Badge> newBadges;
  final bool streakUpdated;
  final int currentStreak;

  AwardXpResult({
    required this.xpAwarded,
    required this.xpBase,
    required this.xpBonus,
    required this.totalXp,
    required this.level,
    required this.leveledUp,
    this.newLevel,
    required this.newBadges,
    required this.streakUpdated,
    required this.currentStreak,
  });

  factory AwardXpResult.fromJson(Map<String, dynamic> json) {
    final badgesRaw = (json['new_badges'] as List<dynamic>? ?? []);
    return AwardXpResult(
      xpAwarded: (json['xp_awarded'] as num).toInt(),
      xpBase: (json['xp_base'] as num?)?.toInt() ?? 0,
      xpBonus: (json['xp_bonus'] as num?)?.toInt() ?? 0,
      totalXp: (json['total_xp'] as num).toInt(),
      level: (json['level'] as num).toInt(),
      leveledUp: json['leveled_up'] as bool? ?? false,
      newLevel: (json['new_level'] as num?)?.toInt(),
      newBadges: badgesRaw
          .map((e) => Badge.fromJson(e as Map<String, dynamic>))
          .toList(),
      streakUpdated: json['streak_updated'] as bool? ?? false,
      currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
    );
  }
}
