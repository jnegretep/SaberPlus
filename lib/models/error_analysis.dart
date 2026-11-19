// lib/models/error_analysis.dart
// Saber+ - Modelo de analisis de errores

import 'package:flutter/material.dart';

/// Resumen general de errores.
class ErrorSummary {
  final int totalQuestions;
  final int correct;
  final int incorrect;
  final int unanswered;
  final double accuracyPct;
  final int totalSimulacros;
  final int avgTimePerSimulacro;
  final String weakestArea;
  final String strongestArea;

  ErrorSummary({
    required this.totalQuestions,
    required this.correct,
    required this.incorrect,
    required this.unanswered,
    required this.accuracyPct,
    required this.totalSimulacros,
    required this.avgTimePerSimulacro,
    required this.weakestArea,
    required this.strongestArea,
  });

  factory ErrorSummary.fromJson(Map<String, dynamic> json) {
    return ErrorSummary(
      totalQuestions: (json['total_questions'] as num?)?.toInt() ?? 0,
      correct: (json['correct'] as num?)?.toInt() ?? 0,
      incorrect: (json['incorrect'] as num?)?.toInt() ?? 0,
      unanswered: (json['unanswered'] as num?)?.toInt() ?? 0,
      accuracyPct: (json['accuracy_pct'] as num?)?.toDouble() ?? 0,
      totalSimulacros: (json['total_simulacros'] as num?)?.toInt() ?? 0,
      avgTimePerSimulacro: (json['avg_time_per_simulacro'] as num?)?.toInt() ?? 0,
      weakestArea: json['weakest_area'] as String? ?? 'N/A',
      strongestArea: json['strongest_area'] as String? ?? 'N/A',
    );
  }
}

/// Analisis de errores por area.
class AreaErrors {
  final String area;
  final int total;
  final int correct;
  final int incorrect;
  final double accuracy;
  final String color;
  final String icon;

  AreaErrors({
    required this.area,
    required this.total,
    required this.correct,
    required this.incorrect,
    required this.accuracy,
    required this.color,
    required this.icon,
  });

  factory AreaErrors.fromJson(Map<String, dynamic> json) {
    return AreaErrors(
      area: json['area'] as String? ?? '',
      total: (json['total'] as num?)?.toInt() ?? 0,
      correct: (json['correct'] as num?)?.toInt() ?? 0,
      incorrect: (json['incorrect'] as num?)?.toInt() ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
      color: json['color'] as String? ?? '#1E4ED8',
      icon: json['icon'] as String? ?? 'extension_rounded',
    );
  }
}

/// Tipo de error clasificado.
class ErrorType {
  final String type;
  final String label;
  final int count;
  final double pct;
  final String description;
  final String icon;
  final String color;

  ErrorType({
    required this.type,
    required this.label,
    required this.count,
    required this.pct,
    required this.description,
    required this.icon,
    required this.color,
  });

  factory ErrorType.fromJson(Map<String, dynamic> json) {
    return ErrorType(
      type: json['type'] as String? ?? '',
      label: json['label'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      pct: (json['pct'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? 'error_outline_rounded',
      color: json['color'] as String? ?? '#EF4444',
    );
  }
}

/// Punto en la evolucion de errores.
class ErrorEvolution {
  final String date;
  final double accuracy;
  final int errors;
  final String simulacro;

  ErrorEvolution({
    required this.date,
    required this.accuracy,
    required this.errors,
    required this.simulacro,
  });

  factory ErrorEvolution.fromJson(Map<String, dynamic> json) {
    return ErrorEvolution(
      date: json['date'] as String? ?? '',
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
      errors: (json['errors'] as num?)?.toInt() ?? 0,
      simulacro: json['simulacro'] as String? ?? 'Simulacro',
    );
  }
}

/// Respuesta completa del endpoint de analisis de errores.
class ErrorAnalysisResponse {
  final ErrorSummary? summary;
  final List<AreaErrors> byArea;
  final List<ErrorType> errorTypes;
  final List<ErrorEvolution> evolution;
  final List<String> recommendations;

  ErrorAnalysisResponse({
    this.summary,
    required this.byArea,
    required this.errorTypes,
    required this.evolution,
    required this.recommendations,
  });

  factory ErrorAnalysisResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;

    final summaryRaw = data['summary'];
    final byAreaRaw = (data['by_area'] as List<dynamic>? ?? []);
    final errorTypesRaw = (data['error_types'] as List<dynamic>? ?? []);
    final evolutionRaw = (data['evolution'] as List<dynamic>? ?? []);
    final recsRaw = (data['recommendations'] as List<dynamic>? ?? []);

    return ErrorAnalysisResponse(
      summary: summaryRaw != null
          ? ErrorSummary.fromJson(summaryRaw as Map<String, dynamic>)
          : null,
      byArea: byAreaRaw
          .map((e) => AreaErrors.fromJson(e as Map<String, dynamic>))
          .toList(),
      errorTypes: errorTypesRaw
          .map((e) => ErrorType.fromJson(e as Map<String, dynamic>))
          .toList(),
      evolution: evolutionRaw
          .map((e) => ErrorEvolution.fromJson(e as Map<String, dynamic>))
          .toList(),
      recommendations: recsRaw.map((e) => e.toString()).toList(),
    );
  }
}
