// lib/services/share_service.dart
// SaberPlus — Compartir resultados en redes sociales v1.7.0
//
// Usa share_plus (nativo + web: abre el diálogo de compartir del
// sistema o del navegador). Registra el evento 'share_clicked' en
// analítica para medir el crecimiento orgánico.
//
// v1.7.0:
// - Textos más atractivos por rango de puntaje (brackets de score).
// - En móvil adjunta el logo oficial (assets/images/saberplus.png)
//   copiado a un archivo temporal (reutilizable). En web: solo texto.
// - Nuevo: sharePredictedScore() para el puntaje estimado por la IA.
//
// Uso:
//   await ShareService.shareSimulacroResult(score: 342);
//   await ShareService.sharePredictedScore(368);

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants/app_constants.dart';
import '../core/io_shim/io_shim.dart'; // v1.6.0: dart:io con stub para web
import 'analytics_service.dart';

class ShareService {
  ShareService._();

  static const String _hashtag = '#SaberPlus #ICFES';
  static const String _storeLine =
      '📲 Descárgala gratis: ${AppConstants.webUrl}';

  /// Ruta del logo ya materializado en el directorio temporal (móvil).
  static String? _cachedLogoPath;

  // ─────────────────────────────────────────────
  // Públicos
  // ─────────────────────────────────────────────

  /// Comparte el resultado de un simulacro.
  ///
  /// El mensaje cambia según el puntaje para que siempre suene ganador:
  /// <250 (entrenando), 250-349 (reto directo), >=350 (modo leyenda).
  static Future<void> shareSimulacroResult({
    required double score,
    String? areaFuerte,
  }) async {
    final scoreTxt = _formatScore(score);

    String headline;
    if (score >= 350) {
      headline = '🏆 ¡$scoreTxt/500 en mi simulacro ICFES con SaberPlus! '
          'Estoy en modo leyenda 😎 ¿Quién se atreve a retarme?';
    } else if (score >= 250) {
      headline = '🎯 $scoreTxt/500 en mi simulacro ICFES. '
          '¿Crees que me alcanzas? Descarga SaberPlus y compítete conmigo 🔥';
    } else {
      headline = '🎓 Estoy entrenando para el ICFES: saqué $scoreTxt/500 '
          'en mi simulacro con SaberPlus 💪 ¡Cada día subo más!';
    }

    final buffer = StringBuffer()
      ..writeln(headline)
      ..writeln();
    if (areaFuerte != null && areaFuerte.isNotEmpty) {
      buffer
        ..writeln('💪 Mi área más fuerte: $areaFuerte')
        ..writeln();
    }
    buffer
      ..writeln(_storeLine)
      ..write(_hashtag);

    await _share(buffer.toString(), 'simulacro');
  }

  /// Comparte el puntaje estimado por la IA.
  static Future<void> sharePredictedScore(double score) async {
    final scoreTxt = _formatScore(score);

    final buffer = StringBuffer()
      ..writeln(
          '🔮 Mi puntaje estimado del ICFES es $scoreTxt/500 según la IA '
          'de SaberPlus ¡Entrena conmigo!')
      ..writeln()
      ..writeln(_storeLine)
      ..write(_hashtag);

    await _share(buffer.toString(), 'predicted_score');
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
      ..writeln('🏆 ¡$etiqueta${_ordinal(posicion)} de $total en SaberPlus! ⭐')
      ..writeln()
      ..writeln('⚡ ${_formatXp(xp)} XP acumulados y subiendo 📈')
      ..writeln()
      ..writeln('¿En qué puesto estás tú? 👀 ¡Entra y dale! 🔥')
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
          ? '🥇 ¡Gané el reto ICFES en SaberPlus! 😎 ¿Quién se atreve a retarme? 🔥'
          : '🎯 Quedé ${_ordinal(posicion)} de $totalJugadores en un reto '
              'ICFES de SaberPlus. ¡La revancha está lista! ⚔️')
      ..writeln();
    if (xpGanada != null && xpGanada > 0) {
      buffer
        ..writeln('⚡ +$xpGanada XP al instante 🚀')
        ..writeln();
    }
    buffer
      ..writeln('¿Te atreves a retarme? 💪')
      ..writeln(_storeLine)
      ..write(_hashtag);

    await _share(buffer.toString(), 'reto');
  }

  /// Comparte una insignia desbloqueada.
  static Future<void> shareBadge({required String nombreBadge}) async {
    final buffer = StringBuffer()
      ..writeln('🎖️ ¡Desbloqueé la insignia "$nombreBadge" en SaberPlus! 🎉')
      ..writeln()
      ..writeln('¿Cuáles tienes tú? 👇 ¡Consíguelas todas antes que yo! 🏁')
      ..writeln(_storeLine)
      ..write(_hashtag);

    await _share(buffer.toString(), 'badge');
  }

  /// Comparte un nivel/nivel de XP alcanzado.
  static Future<void> shareLevelUp({required int nivel, required int xp}) async {
    final buffer = StringBuffer()
      ..writeln('🚀 ¡Alcancé el nivel $nivel en SaberPlus! ⭐')
      ..writeln()
      ..writeln('⚡ ${_formatXp(xp)} XP de preparación ICFES')
      ..writeln()
      ..writeln('Acompáñame a llegar más lejos 💪 ¡Nos vemos arriba! 📈')
      ..writeln(_storeLine)
      ..write(_hashtag);

    await _share(buffer.toString(), 'level_up');
  }

  // ─────────────────────────────────────────────
  // Internos
  // ─────────────────────────────────────────────

  /// 🔧 FIX v1.7.0: usa la API clásica de share_plus (Share.share /
  /// Share.shareXFiles). Es compatible con TODAS las versiones instalables
  /// de share_plus (7.x, 8.x, 9.x, 10.x, 11.x, 12.x, 13.x). La API nueva
  /// (SharePlus.instance.share + ShareParams) solo existe desde 11.x, así
  /// que en versiones anteriores el proyecto no compilaba.
  static Future<void> _share(String text, String contentType) async {
    const shareTitle = 'SaberPlus — Preparación ICFES';
    try {
      AnalyticsService.logShareClicked(contentType: contentType);

      // En móvil intentamos adjuntar el logo; en web SOLO texto.
      final logoPath = await _logoFileForShare();

      if (logoPath == null) {
        // ignore: deprecated_member_use
        await Share.share(text, subject: shareTitle);
      } else {
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [XFile(logoPath)],
          text: text,
          subject: shareTitle,
        );
      }
    } catch (_) {
      // Algunos share targets fallan con archivos: reintento solo texto.
      try {
        // ignore: deprecated_member_use
        await Share.share(text, subject: 'SaberPlus — Preparación ICFES');
      } catch (_) {
        // Compartir nunca debe romper la app
      }
    }
  }

  /// Devuelve la ruta del logo oficial para adjuntar al compartir,
  /// o null si no está disponible (web, sin almacenamiento, asset faltante).
  ///
  /// El asset se copia UNA vez a un archivo temporal y se REUTILIZA en
  /// cada share posterior (no escribimos en cada tap).
  static Future<String?> _logoFileForShare() async {
    if (kIsWeb) return null; // web: no hay sistema de archivos

    try {
      // 1) ¿Ya lo tenemos en memoria y sigue en disco?
      if (_cachedLogoPath != null) {
        final cached = File(_cachedLogoPath!);
        if (await cached.exists()) return _cachedLogoPath;
      }

      // 2) ¿Existe ya el archivo temporal de una sesión anterior?
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/saberplus_share_logo.png');
      if (await file.exists()) {
        _cachedLogoPath = file.path;
        return file.path;
      }

      // 3) Primera vez: materializar el asset en disco.
      final byteData = await rootBundle.load(AppConstants.assetLogo);
      final sink = file.openWrite();
      sink.add(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
      );
      await sink.flush();
      await sink.close();

      _cachedLogoPath = file.path;
      return file.path;
    } catch (_) {
      // Si falla el logo → comparte solo texto (nunca romper).
      return null;
    }
  }

  /// 342.0 → "342" · 342.5 → "342.5"
  static String _formatScore(double score) {
    if (score == score.roundToDouble()) {
      return score.round().toString();
    }
    return score.toStringAsFixed(1);
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