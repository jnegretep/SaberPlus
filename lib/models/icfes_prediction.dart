// lib/models/icfes_prediction.dart
// Saber+ - Modelo de prediccion ICFES y comparativa historica

import 'package:flutter/material.dart';

/// Prediccion del puntaje ICFES del usuario.
class IcfesPrediction {
  final int predictedScore;
  final String confidence; // 'baja', 'media', 'alta'
  final int confidencePct;
  final int rangeMin;
  final int rangeMax;
  final int basedOnSimulacros;
  final int lastScore;
  final String trend; // 'ascending', 'descending', 'stable'
  final double trendPct;
  final String message;

  IcfesPrediction({
    required this.predictedScore,
    required this.confidence,
    required this.confidencePct,
    required this.rangeMin,
    required this.rangeMax,
    required this.basedOnSimulacros,
    required this.lastScore,
    required this.trend,
    required this.trendPct,
    required this.message,
  });

  factory IcfesPrediction.fromJson(Map<String, dynamic> json) {
    return IcfesPrediction(
      predictedScore: (json['predicted_score'] as num).toInt(),
      confidence: json['confidence'] as String? ?? 'baja',
      confidencePct: (json['confidence_pct'] as num?)?.toInt() ?? 0,
      rangeMin: (json['range_min'] as num?)?.toInt() ?? 0,
      rangeMax: (json['range_max'] as num?)?.toInt() ?? 500,
      basedOnSimulacros: (json['based_on_simulacros'] as num?)?.toInt() ?? 0,
      lastScore: (json['last_score'] as num?)?.toInt() ?? 0,
      trend: json['trend'] as String? ?? 'stable',
      trendPct: (json['trend_pct'] as num?)?.toDouble() ?? 0,
      message: json['message'] as String? ?? '',
    );
  }

  bool get isAscending => trend == 'ascending';
  bool get isDescending => trend == 'descending';
  bool get isStable => trend == 'stable';

  Color get trendColor =>
      isAscending ? const Color(0xFF22C55E) : (isDescending ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));
}

/// Un punto en el historico de simulacros.
class HistoryPoint {
  final String date;
  final double score;
  final String simulacro;
  final Map<String, double> areas;

  HistoryPoint({
    required this.date,
    required this.score,
    required this.simulacro,
    required this.areas,
  });

  factory HistoryPoint.fromJson(Map<String, dynamic> json) {
    final areasRaw = (json['areas'] ?? {}) as Map<String, dynamic>;
    return HistoryPoint(
      date: json['date'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      simulacro: json['simulacro'] as String? ?? 'Simulacro',
      areas: areasRaw.map((k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0)),
    );
  }
}

/// Analisis de un area especifica.
class AreaAnalysis {
  final String area;
  final double avg;
  final double last;
  final String trend; // 'up', 'down', 'stable', 'no_data'
  final double trendPct;
  final String color;
  final String icon;

  AreaAnalysis({
    required this.area,
    required this.avg,
    required this.last,
    required this.trend,
    required this.trendPct,
    required this.color,
    required this.icon,
  });

  factory AreaAnalysis.fromJson(Map<String, dynamic> json) {
    return AreaAnalysis(
      area: json['area'] as String? ?? '',
      avg: (json['avg'] as num?)?.toDouble() ?? 0,
      last: (json['last'] as num?)?.toDouble() ?? 0,
      trend: json['trend'] as String? ?? 'stable',
      trendPct: (json['trend_pct'] as num?)?.toDouble() ?? 0,
      color: json['color'] as String? ?? '#1E4ED8',
      icon: json['icon'] as String? ?? 'extension_rounded',
    );
  }

  bool get isUp => trend == 'up';
  bool get isDown => trend == 'down';
}

/// Respuesta completa del endpoint de prediccion.
class PredictionResponse {
  final IcfesPrediction? prediction;
  final List<HistoryPoint> history;
  final List<AreaAnalysis> areaAnalysis;
  final List<String> recommendations;

  PredictionResponse({
    this.prediction,
    required this.history,
    required this.areaAnalysis,
    required this.recommendations,
  });

  factory PredictionResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;

    final predictionRaw = data['prediction'];
    final historyRaw = (data['history'] as List<dynamic>? ?? []);
    final areasRaw = (data['area_analysis'] as List<dynamic>? ?? []);
    final recsRaw = (data['recommendations'] as List<dynamic>? ?? []);

    return PredictionResponse(
      prediction: predictionRaw != null
          ? IcfesPrediction.fromJson(predictionRaw as Map<String, dynamic>)
          : null,
      history: historyRaw
          .map((e) => HistoryPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      areaAnalysis: areasRaw
          .map((e) => AreaAnalysis.fromJson(e as Map<String, dynamic>))
          .toList(),
      recommendations: recsRaw.map((e) => e.toString()).toList(),
    );
  }
}
