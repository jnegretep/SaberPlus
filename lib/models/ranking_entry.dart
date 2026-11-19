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

// ═══════════════════════════════════════════════════════════
// v1.6.0 — Rankings institucionales (colegios / departamentos)
// ═══════════════════════════════════════════════════════════

/// Una institución (colegio o departamento) en el ranking.
class InstitutionRankingEntry {
  final int posicion;
  final String nombre;
  final String? departamento;
  final String? ciudad;
  final int totalXp;
  final int usuarios;
  final double nivelPromedio;
  final bool esMia;

  InstitutionRankingEntry({
    required this.posicion,
    required this.nombre,
    this.departamento,
    this.ciudad,
    required this.totalXp,
    required this.usuarios,
    required this.nivelPromedio,
    this.esMia = false,
  });

  factory InstitutionRankingEntry.fromJson(Map<String, dynamic> json) {
    return InstitutionRankingEntry(
      posicion: (json['posicion'] as num).toInt(),
      nombre: json['nombre'] as String? ?? '—',
      departamento: json['departamento'] as String?,
      ciudad: json['ciudad'] as String?,
      totalXp: (json['total_xp'] as num?)?.toInt() ?? 0,
      usuarios: (json['usuarios'] as num?)?.toInt() ?? 0,
      nivelPromedio: (json['nivel_promedio'] as num?)?.toDouble() ?? 0,
      esMia: json['es_mia'] as bool? ?? false,
    );
  }

  /// Iniciales del nombre para el avatar placeholder.
  String get initials {
    final clean = nombre.trim();
    if (clean.isEmpty) return '?';
    return clean.substring(0, 1).toUpperCase();
  }
}

/// Posición de la institución del usuario actual.
class MiInstitucion {
  final String nombre;
  final int posicion;
  final int? totalXp;
  final int? usuarios;

  MiInstitucion({
    required this.nombre,
    required this.posicion,
    this.totalXp,
    this.usuarios,
  });

  factory MiInstitucion.fromJson(Map<String, dynamic> json) {
    return MiInstitucion(
      nombre: json['nombre'] as String? ?? '',
      posicion: (json['posicion'] as num?)?.toInt() ?? 0,
      totalXp: (json['total_xp'] as num?)?.toInt(),
      usuarios: (json['usuarios'] as num?)?.toInt(),
    );
  }
}

/// Respuesta completa del ranking institucional.
class InstitutionRankingResponse {
  final String tipo;               // 'colegios' | 'departamentos'
  final String period;             // 'all_time', 'weekly', 'monthly'
  final int totalInstituciones;
  final MiInstitucion? miInstitucion;
  final List<InstitutionRankingEntry> ranking;

  InstitutionRankingResponse({
    required this.tipo,
    required this.period,
    required this.totalInstituciones,
    this.miInstitucion,
    required this.ranking,
  });

  factory InstitutionRankingResponse.fromJson(Map<String, dynamic> json) {
    final rankingRaw = (json['ranking'] as List<dynamic>? ?? []);
    return InstitutionRankingResponse(
      tipo: json['tipo'] as String? ?? 'colegios',
      period: json['period'] as String? ?? 'all_time',
      totalInstituciones: (json['total_instituciones'] as num?)?.toInt() ?? 0,
      miInstitucion: json['mi_institucion'] == null
          ? null
          : MiInstitucion.fromJson(json['mi_institucion'] as Map<String, dynamic>),
      ranking: rankingRaw
          .map((e) => InstitutionRankingEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
