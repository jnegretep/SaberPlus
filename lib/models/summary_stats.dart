// lib/models/summary_stats.dart
class SummaryStats {
  final int simulacrosRealizados;
  final DateTime? ultimaFecha;
  final double? promedioGlobal;
  final int? tiempoPromedioSeg;
  final Map<String, double?> areas;

  SummaryStats({
    required this.simulacrosRealizados,
    required this.ultimaFecha,
    required this.promedioGlobal,
    required this.tiempoPromedioSeg,
    required this.areas,
  });

  factory SummaryStats.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json; // soporta respuesta directa o envuelta en {status, data}
    final rawAreas = (data['areas'] ?? {}) as Map<String, dynamic>;

    return SummaryStats(
      simulacrosRealizados: (data['simulacros_realizados'] ?? 0) as int,
      ultimaFecha: data['ultima_fecha'] != null
          ? DateTime.tryParse(data['ultima_fecha'].toString())
          : null,
      promedioGlobal: (data['promedio_global'] is num)
          ? (data['promedio_global'] as num).toDouble()
          : double.tryParse(data['promedio_global']?.toString() ?? ''),
      tiempoPromedioSeg: (data['tiempo_promedio_seg'] is num)
          ? (data['tiempo_promedio_seg'] as num).toInt()
          : int.tryParse(data['tiempo_promedio_seg']?.toString() ?? ''),
      areas: {
        'lectura': _toDoubleOrNull(rawAreas['lectura']),
        'matematicas': _toDoubleOrNull(rawAreas['matematicas']),
        'sociales': _toDoubleOrNull(rawAreas['sociales']),
        'naturales': _toDoubleOrNull(rawAreas['naturales']),
        'ingles': _toDoubleOrNull(rawAreas['ingles']),
      },
    );
  }

  static double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
