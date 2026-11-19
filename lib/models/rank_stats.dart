class RankStats {
  final Map<String, dynamic> eligibility;
  final int? tuPosicion;
  final List<Map<String, dynamic>> top;
  final int? totalParticipantes; // nuevo campo

  RankStats({
    required this.eligibility,
    required this.tuPosicion,
    required this.top,
    this.totalParticipantes,
  });

  factory RankStats.fromJson(Map<String, dynamic> json) {
    return RankStats(
      eligibility: Map<String, dynamic>.from(json['eligibility'] ?? {}),
      tuPosicion: json['tuPosicion'],
      top: (json['top'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      totalParticipantes: json['totalParticipantes'], // parseo del nuevo campo
    );
  }
}
