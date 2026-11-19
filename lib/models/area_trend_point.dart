// lib/models/area_trend_point.dart
class AreaTrendPoint {
  final int simulacroId;
  final int courseId;
  final DateTime fecha;
  final double? puntaje;

  /// 🔹 Puntaje máximo esperado para esta área (hasta 100)
  static const int maxPuntajeArea = 100;

  AreaTrendPoint({
    required this.simulacroId,
    required this.courseId,
    required this.fecha,
    required this.puntaje,
  });

  factory AreaTrendPoint.fromJson(Map<String, dynamic> json) {
    return AreaTrendPoint(
      simulacroId: json['simulacroId'] ?? 0,
      courseId: json['courseId'] ?? 0,
      fecha: DateTime.tryParse(json['fecha'] ?? '') ?? DateTime.now(),
      puntaje: (json['puntaje'] is num)
    ? ((json['puntaje'] as num).toDouble().clamp(0, maxPuntajeArea).toDouble())
    : null,
    );
  }

  /// 🔹 Devuelve el puntaje como porcentaje respecto al máximo (0–100%)
  double? get porcentaje {
    if (puntaje == null) return null;
    return (puntaje! / maxPuntajeArea) * 100;
  }

  /// 🔹 Texto amigable para mostrar en la gráfica
  String get displayLabel {
    if (puntaje == null) return '—';
    return '${puntaje!.toStringAsFixed(1)} / $maxPuntajeArea';
  }
}
