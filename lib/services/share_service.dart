// lib/services/share_service.dart
// Saber+ — Compartir resultados en redes sociales v1.6.0
//
// Usa share_plus (nativo + web: abre el diálogo de compartir del
// sistema o del navegador). Registra el evento 'share_clicked' en
// analítica para medir el crecimiento orgánico.
//
// Uso:
//   await ShareService.shareSimulacroResult(score: 342);

import 'package:share_plus/share_plus.dart';

import 'analytics_service.dart';

class ShareService {
  ShareService._();

  static const String _hashtag = '#SaberPlus #ICFES';
  static const String _storeLine =
      '📲 Descárgala gratis y retame: saberplus.app';

  /// Comparte el resultado de un simulacro.
  static Future<void> shareSimulacroResult({
    required double score,
    String? areaFuerte,
  }) async {
    final buffer = StringBuffer()
      ..writeln('🎓 Logré $score/500 en mi simulacro ICFES con Saber+')
      ..writeln();
    if (areaFuerte != null && areaFuerte.isNotEmpty) {
      buffer
        ..writeln('💪 Mi área más fuerte: $areaFuerte')
        ..writeln();
    }
    buffer
      ..writeln('¿Puedes superarme? 🚀')
      ..writeln(_storeLine)
      ..write(_hashtag);

    await _share(buffer.toString(), 'simulacro');
  }

  /// Comparte la posición en un ranking.
  static Future<void> shareRankingPosition({
    required int posicion,
    required int total,
    required int xp,
    String tipo = 'estudiantes',
  }) async {
    final etiqueta = tipo == 'colegios'
        ? 'Mi colegio va '
        : tipo == 'departamentos'
            ? 'Mi departamento va '
            : 'Voy ';

    final buffer = StringBuffer()
      ..writeln('🏆 $etiqueta${_ordinal(posicion)} de $total en Saber+')
      ..writeln()
      ..writeln('⚡ ${_formatXp(xp)} XP acumulados')
      ..writeln()
      ..writeln('¿En qué puesto estás tú? 👀')
      ..writeln(_storeLine)
      ..write(_hashtag);

    await _share(buffer.toString(), 'ranking');
  }

  /// Comparte el resultado de un reto (1v1 o multijugador).
  static Future<void> shareChallengeResult({
    required int posicion,
    required int totalJugadores,
    int? xpGanada,
  }) async {
    final buffer = StringBuffer()
      ..writeln(posicion == 1
          ? '🥇 ¡Gané el reto ICFES en Saber+!'
          : '🎯 Quedé ${_ordinal(posicion)} de $totalJugadores en un reto ICFES de Saber+')
      ..writeln();
    if (xpGanada != null && xpGanada > 0) {
      buffer
        ..writeln('⚡ +$xpGanada XP')
        ..writeln();
    }
    buffer
      ..writeln('¿Te atreves a retarme? 🔥')
      ..writeln(_storeLine)
      ..write(_hashtag);

    await _share(buffer.toString(), 'reto');
  }

  /// Comparte una insignia desbloqueada.
  static Future<void> shareBadge({required String nombreBadge}) async {
    final buffer = StringBuffer()
      ..writeln('🎖️ Desbloqueé la insignia "$nombreBadge" en Saber+')
      ..writeln()
      ..writeln('¿Cuáles tienes tú? 👇')
      ..writeln(_storeLine)
      ..write(_hashtag);

    await _share(buffer.toString(), 'badge');
  }

  /// Comparte un nivel/nivel de XP alcanzado.
  static Future<void> shareLevelUp({required int nivel, required int xp}) async {
    final buffer = StringBuffer()
      ..writeln('🚀 Alcanzé el nivel $nivel en Saber+')
      ..writeln()
      ..writeln('⚡ ${_formatXp(xp)} XP de preparación ICFES')
      ..writeln()
      ..writeln('Acompáñame a llegar más lejos 💪')
      ..writeln(_storeLine)
      ..write(_hashtag);

    await _share(buffer.toString(), 'level_up');
  }

  // ─────────────────────────────────────────────
  // Internos
  // ─────────────────────────────────────────────

  static Future<void> _share(String text, String contentType) async {
    try {
      AnalyticsService.logShareClicked(contentType: contentType);
      await SharePlus.instance.share(
        ShareParams(text: text, title: 'Saber+ — Preparación ICFES'),
      );
    } catch (_) {
      // Compartir nunca debe romper la app
    }
  }

  /// 1 → 1.º, 2 → 2.º, 3 → 3.º (indicador ordinal español)
  static String _ordinal(int n) {
    return '$n.º';
  }

  static String _formatXp(int xp) {
    if (xp >= 1000000) {
      return '${(xp / 1000000).toStringAsFixed(1)}M';
    }
    if (xp >= 1000) {
      return '${(xp / 1000).toStringAsFixed(1)}k';
    }
    return '$xp';
  }
}
