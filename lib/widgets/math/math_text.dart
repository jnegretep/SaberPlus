// lib/widgets/math/math_text.dart
// Saber+ - Renderizado de texto con ecuaciones matematicas
//
// FIX: Volviendo al enfoque simple que funcionaba.
// NO normaliza $...$ (Moodle ya usa \(...\))
// NO limpia el LaTeX con _cleanLatex (solo quita delimitadores)
// Solo convierte $$...$$ y MathML que si son necesarios.
//
// OPTIMIZACIÓN (motor de cuestionarios v2):
//   Se añade el constructor `MathText.fromSegments` que acepta los
//   segmentos pre-parseados (`TextBlock` + `MathBlock`) producidos por
//   `quiz_block_parser.dart`. Esto elimina el coste de `_normalize` +
//   `RegExp.allMatches` en cada `build()`, que era uno de los cuellos de
//   botella principales.
//   El constructor legacy `MathText(html: ...)` se mantiene para
//   compatibilidad con otros usos (course_contents_screen, etc.).

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_logger.dart';
import '../../models/quiz_block.dart';

class MathText extends StatelessWidget {
  /// HTML crudo (modo legacy). Si es `null`, se usa `segments`.
  final String? html;

  /// Segmentos pre-parseados (modo optimizado).
  /// Si es `null`, se usa `html` y se parsea al vuelo.
  final List<QuizBlock>? segments;

  final bool isOption;
  final Color? textColor;

  /// Constructor legacy: recibe HTML crudo y lo parsea en cada build.
  ///
  /// Se mantiene para compatibilidad con usos fuera del flujo de cuestionario
  /// (course_contents_screen, etc.). En el flujo de cuestionario se debe
  /// usar `MathText.fromSegments` en su lugar.
  const MathText({
    super.key,
    required String this.html,
    this.isOption = false,
    this.textColor,
  }) : segments = null;

  /// Constructor optimizado: recibe segmentos pre-parseados.
  ///
  /// Acepta una lista de `QuizBlock` (típicamente `TextBlock` + `MathBlock`)
  /// producidos por `quiz_block_parser.dart`. Esto elimina el coste de
  /// `_normalize` + `RegExp.allMatches` en cada `build()`.
  const MathText.fromSegments({
    super.key,
    required List<QuizBlock> this.segments,
    this.isOption = false,
    this.textColor,
  }) : html = null;

  @override
  Widget build(BuildContext context) {
    final fontSize = isOption ? 14.0 : 16.0;
    final lineHeight = isOption ? 1.3 : 1.5;
    final color = textColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkTextPrimary
            : AppColors.borderDark);

    // Si tenemos segmentos pre-parseados, los usamos directamente (sin regex).
    if (segments != null) {
      return _buildFromSegments(segments!, fontSize, lineHeight, color);
    }

    // Modo legacy: parsear HTML al vuelo (comportamiento original).
    final source = html ?? '';
    final normalized = _normalize(source);

    // Buscar ecuaciones con el mismo regex que siempre funciono
    final regex = RegExp(r'(\\\(.+?\\\)|\\\[.+?\\\])', dotAll: true);
    final matches = regex.allMatches(normalized);

    // Si no hay ecuaciones, renderizar como HTML puro
    if (matches.isEmpty) {
      return Html(
        data: normalized,
        style: _htmlStyle(fontSize, lineHeight, color),
      );
    }

    // Renderizar texto + ecuaciones mezclados (enfoque simple que funcionaba)
    final widgets = <Widget>[];
    int last = 0;

    for (final match in matches) {
      // Texto antes de la ecuacion
      if (match.start > last) {
        final text = normalized.substring(last, match.start);
        if (text.trim().isNotEmpty) {
          widgets.add(Html(
            data: text,
            style: _htmlStyle(fontSize, lineHeight, color),
          ));
        }
      }

      // La ecuacion - extraer LaTeX quitando SOLO los delimitadores
      final rawEq = match.group(0)!;
      final isDisplay = rawEq.startsWith(r'\[');
      final latex = rawEq
          .replaceAll(r'\(', '')
          .replaceAll(r'\)', '')
          .replaceAll(r'\[', '')
          .replaceAll(r'\]', '')
          .trim();

      widgets.add(_buildMathWidget(latex, isDisplay, fontSize, color));
      last = match.end;
    }

    // Texto despues de la ultima ecuacion
    if (last < normalized.length) {
      final text = normalized.substring(last);
      if (text.trim().isNotEmpty) {
        widgets.add(Html(
          data: text,
          style: _htmlStyle(fontSize, lineHeight, color),
        ));
      }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 2,
      children: widgets,
    );
  }

  /// Construye el widget a partir de segmentos pre-parseados.
  ///
  /// Recorre `List<QuizBlock>` y construye widgets directamente, sin regex
  /// ni normalización. Los `TextBlock` se renderizan con `Html` (texto con
  /// formato inline) y los `MathBlock` con `Math.tex`.
  Widget _buildFromSegments(
    List<QuizBlock> segs,
    double fontSize,
    double lineHeight,
    Color color,
  ) {
    if (segs.isEmpty) return const SizedBox.shrink();

    // Caso frecuente: un único TextBlock → devolver Html directamente
    // sin envolver en Wrap.
    if (segs.length == 1) {
      final b = segs.first;
      if (b is TextBlock) {
        return Html(
          data: b.html,
          style: _htmlStyle(fontSize, lineHeight, color),
        );
      }
      if (b is MathBlock) {
        return _buildMathWidget(b.latex, b.isDisplay, fontSize, color);
      }
    }

    // Múltiples segmentos → Wrap.
    final widgets = <Widget>[];
    for (final b in segs) {
      if (b is TextBlock) {
        if (b.html.trim().isEmpty) continue;
        widgets.add(Html(
          data: b.html,
          style: _htmlStyle(fontSize, lineHeight, color),
        ));
      } else if (b is MathBlock) {
        widgets.add(_buildMathWidget(b.latex, b.isDisplay, fontSize, color));
      }
      // Otros tipos de bloque no deberían aparecer dentro de un TextBlock;
      // si aparecen, se ignoran silenciosamente.
    }

    if (widgets.isEmpty) return const SizedBox.shrink();
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 2,
      children: widgets,
    );
  }

  /// Construye un widget `Math.tex` con el fallback de error.
  /// Extraído para no duplicar lógica entre modo legacy y modo optimizado.
  Widget _buildMathWidget(
    String latex,
    bool isDisplay,
    double fontSize,
    Color color,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 4,
        vertical: isOption ? 2 : 4,
      ),
      child: Math.tex(
        latex,
        textStyle: TextStyle(
          fontSize: isDisplay ? fontSize * 1.15 : fontSize,
          color: color,
        ),
        onErrorFallback: (error) {
          AppLogger.w('Math render error: ${error.message} (latex=$latex)');
          return Text(
            latex,
            style: TextStyle(fontSize: fontSize, color: color),
          );
        },
      ),
    );
  }

  /// Normalizacion MINIMA - solo lo necesario:
  /// 1. $$...$$ a \[...\] (display math)
  /// 2. MathML a \(...\)
  /// 3. Entidades HTML basicas
  /// NO convierte $...$ a \(...\) — Moodle ya usa \(...\) directamente
  String _normalize(String input) {
    var result = input;

    // 1. Convertir $$...$$ a \[...\]
    result = result.replaceAllMapped(
      RegExp(r'\$\$(.+?)\$\$', dotAll: true),
      (m) => '\\[${m.group(1)}\\]',
    );

    // 2. MathML <math>...</math> -> extraer contenido
    result = result.replaceAllMapped(
      RegExp(r'<math[^>]*>(.*?)</math>', dotAll: true),
      (m) => '\\(${m.group(1)}\\)',
    );

    // 3. Entidades HTML basicas
    result = result
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#39;', "'");

    return result;
  }

  Map<String, Style> _htmlStyle(double fontSize, double lineHeight, Color color) {
    return {
      "body": Style(
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
        fontSize: FontSize(fontSize),
        lineHeight: LineHeight(lineHeight),
        color: color,
      ),
      "p": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
      "sub": Style(
        fontSize: FontSize(fontSize * 0.7),
        verticalAlign: VerticalAlign.sub,
      ),
      "sup": Style(
        fontSize: FontSize(fontSize * 0.7),
        verticalAlign: VerticalAlign.sup,
      ),
    };
  }
}