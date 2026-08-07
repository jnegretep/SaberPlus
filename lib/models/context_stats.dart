class ContextStats {
  final double? tuPromedio;
  final double? segmentoPromedio;
  final int n;
  final double? percentil;
  final String status;
  final String scope;
  final String area;
  final bool preliminar;
  final int nMin;

  ContextStats({
    required this.tuPromedio,
    required this.segmentoPromedio,
    required this.n,
    required this.percentil,
    required this.status,
    required this.scope,
    required this.area,
    required this.preliminar,
    required this.nMin,
  });

  factory ContextStats.fromJson(Map<String, dynamic> json) {
    return ContextStats(
      tuPromedio: (json['tuPromedio'] as num?)?.toDouble(),
      segmentoPromedio: (json['segmentoPromedio'] as num?)?.toDouble(),
      n: json['n'] ?? 0,
      percentil: (json['percentil'] as num?)?.toDouble(),
      status: json['status'] ?? 'insufficient',
      scope: json['scope'] ?? 'national',
      area: json['area'] ?? 'global',
      preliminar: json['preliminar'] ?? false,
      nMin: json['nMin'] ?? 0,
    );
  }
}
