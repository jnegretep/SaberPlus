// lib/models/ranking_entry.dart
// Saber+ — Modelo de entrada del ranking de usuarios

/// Una entrada en el ranking de usuarios.
class RankingEntry {
  final int position;
  final int userId;
  final String name;
  final String? avatarPath;
  final String? colegio;
  final String? ciudad;
  final int xp;
  final int level;
  final bool isCurrentUser;

  RankingEntry({
    required this.position,
    required this.userId,
    required this.name,
    this.avatarPath,
    this.colegio,
    this.ciudad,
    required this.xp,
    required this.level,
    this.isCurrentUser = false,
  });

  factory RankingEntry.fromJson(Map<String, dynamic> json) {
    return RankingEntry(
      position: (json['position'] as num).toInt(),
      userId: (json['user_id'] as num).toInt(),
      name: json['name'] as String? ?? 'Usuario',
      avatarPath: json['avatar_path'] as String?,
      colegio: json['colegio'] as String?,
      ciudad: json['ciudad'] as String?,
      xp: (json['xp'] as num).toInt(),
      level: (json['level'] as num).toInt(),
      isCurrentUser: json['is_current_user'] as bool? ?? false,
    );
  }

  /// Iniciales del nombre para mostrar en avatar placeholder
  String get initials {
    final parts = name.trim().split(' ');
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/// Respuesta completa del ranking.
class RankingResponse {
  final String period;            // 'all_time', 'weekly', 'monthly'
  final int userPosition;         // posición del usuario actual (puede ser > ranking.length)
  final int totalUsers;           // total de usuarios en el ranking
  final List<RankingEntry> ranking;

  RankingResponse({
    required this.period,
    required this.userPosition,
    required this.totalUsers,
    required this.ranking,
  });

  factory RankingResponse.fromJson(Map<String, dynamic> json) {
    final rankingRaw = (json['ranking'] as List<dynamic>? ?? []);
    return RankingResponse(
      period: json['period'] as String? ?? 'all_time',
      userPosition: (json['user_position'] as num?)?.toInt() ?? 0,
      totalUsers: (json['total_users'] as num?)?.toInt() ?? 0,
      ranking: rankingRaw
          .map((e) => RankingEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
