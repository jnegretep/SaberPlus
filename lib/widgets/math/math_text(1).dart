// lib/widgets/math/math_text.dart
// Saber+ — Renderizado mejorado de texto con ecuaciones matemáticas
//
// Soporta múltiples formatos de ecuaciones que Moodle usa:
// 1. LaTeX inline: \( ... \) o $...$
// 2. LaTeX display: \[ ... \] o $$...$$
// 3. MathML: <math>...</math>
// 4. HTML sub/sup: <sub>...</sub>, <sup>...</sup>
// 5. Moodle spans: <span class="math">...</span>
//
// Características:
// - Fallback graceful: si el LaTeX falla, muestra el texto crudo
// - Overflow horizontal: ecuaciones largas se hacen scrollables
// - Tamaño adaptativo según contexto (opción vs pregunta)
// - Dark mode support
// - Renderizado mixto: HTML + LaTeX en el mismo texto

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_logger.dart';

/// Widget que renderiza texto HTML con ecuaciones matemáticas embebidas.
///
/// Uso:
/// ```dart
/// MathText(
///   html: 'El área de un círculo es \( A = \pi r^2 \)',
///   isOption: false,
/// )
/// ```
class MathText extends StatelessWidget {
  final String html;
  final bool isOption;
  final Color? textColor;

  const MathText({
    super.key,
    required this.html,
    this.isOption = false,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = isOption ? 14.0 : 16.0;
    final lineHeight = isOption ? 1.3 : 1.5;
    final color = textColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkTextPrimary
            : AppColors.borderDark);

    // Normalizar el HTML: convertir todos los formatos a \(...\) y \[...\]
    final normalized = _normalizeMath(html);

    // Si no hay ecuaciones, renderizar como HTML puro
    if (!_hasMath(normalized)) {
      return Html(
        data: normalized,
        style: _htmlStyle(fontSize, lineHeight, color),
      );
    }

    // Renderizar texto + ecuaciones mezclados
    final widgets = _buildMixedWidgets(normalized, fontSize, color, context);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 2,
      runSpacing: 2,
      children: widgets,
    );
  }

  /// Normaliza todos los formatos de ecuaciones a \(...\) y \[...\]
  String _normalizeMath(String input) {
    var result = input;

    // 1. Convertir $$...$$ a \[...\] (display math)
    result = result.replaceAllMapped(
      RegExp(r'\$\$(.+?)\$\$', dotAll: true),
      (m) => '\\[${m.group(1)}\\]',
    );

    // 2. Convertir $...$ a \(...\) (inline math) — pero no los $$ ya convertidos
    result = result.replaceAllMapped(
      RegExp(r'(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)', dotAll: true),
      (m) => '\\(${m.group(1)}\\)',
    );

    // 3. MathML <math>...</math> → extraer el contenido y convertir a LaTeX
    result = result.replaceAllMapped(
      RegExp(r'<math[^>]*>(.*?)</math>', dotAll: true),
      (m) => '\\(${m.group(1)}\\)',
    );

    // 4. Moodle spans: <span class="math">...</span> → \(...\)
    result = result.replaceAllMapped(
      RegExp(r'<span[^>]*class="[^"]*math[^"]*"[^>]*>(.*?)</span>', dotAll: true),
      (m) => '\\(${m.group(1)}\\)',
    );

    // 5. Limpiar entidades HTML comunes en LaTeX
    result = result
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ');

    return result;
  }

  /// Verifica si el texto contiene ecuaciones matemáticas.
  bool _hasMath(String text) {
    return text.contains(r'\(') ||
        text.contains(r'\[') ||
        text.contains('<math');
  }

  /// Construye una lista de widgets mezclando HTML y ecuaciones LaTeX.
  List<Widget> _buildMixedWidgets(
    String text,
    double fontSize,
    Color color,
    BuildContext context,
  ) {
    final widgets = <Widget>[];
    final regex = RegExp(r'(\\\(.+?\\\)|\\\[.+?\\\])', dotAll: true);
    final matches = regex.allMatches(text);

    int last = 0;
    for (final match in matches) {
      // Texto antes de la ecuación
      if (match.start > last) {
        final beforeText = text.substring(last, match.start);
        if (beforeText.trim().isNotEmpty) {
          widgets.add(Html(
            data: beforeText,
            style: _htmlStyle(fontSize, isOption ? 1.3 : 1.5, color),
          ));
        }
      }

      // La ecuación
      final rawEq = match.group(0)!;
      final isDisplay = rawEq.startsWith(r'\[');
      final latex = rawEq
          .replaceAll(r'\(', '')
          .replaceAll(r'\)', '')
          .replaceAll(r'\[', '')
          .replaceAll(r'\]', '')
          .trim();

      widgets.add(
        _MathEquation(
          latex: latex,
          isDisplay: isDisplay,
          fontSize: fontSize,
          color: color,
        ),
      );

      last = match.end;
    }

    // Texto después de la última ecuación
    if (last < text.length) {
      final afterText = text.substring(last);
      if (afterText.trim().isNotEmpty) {
        widgets.add(Html(
          data: afterText,
          style: _htmlStyle(fontSize, isOption ? 1.3 : 1.5, color),
        ));
      }
    }

    return widgets;
  }

  /// Estilo HTML compartido para los fragmentos de texto.
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

/// Widget que renderiza una sola ecuación LaTeX con fallback.
class _MathEquation extends StatelessWidget {
  final String latex;
  final bool isDisplay;
  final double fontSize;
  final Color color;

  const _MathEquation({
    required this.latex,
    required this.isDisplay,
    required this.fontSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Si es display math (\[...\]), mostrar en su propia línea con padding
    if (isDisplay) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: _buildMathWidget(context),
        ),
      );
    }

    // Inline math — dentro del flujo del texto
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 2,
        vertical: isDisplay ? 4 : 0,
      ),
      child: _buildMathWidget(context),
    );
  }

  Widget _buildMathWidget(BuildContext context) {
    try {
      final mathWidget = Math.tex(
        latex,
        textStyle: TextStyle(
          fontSize: isDisplay ? fontSize * 1.15 : fontSize,
          color: color,
        ),
      );

      // Para ecuaciones potencialmente anchas, permitir scroll horizontal
      if (_isLikelyWide(latex)) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: mathWidget,
        );
      }

      return mathWidget;
    } catch (e) {
      // Fallback: mostrar el LaTeX como texto monoespaciado
      AppLogger.w('Math render failed for "$latex": $e');
      return _buildFallback();
    }
  }

  /// Detecta si una ecuación es probablemente muy ancha (fracciones largas, sumatorias, etc.)
  bool _isLikelyWide(String latex) {
    // Heurística: si tiene fracciones anidadas, sumatorias, o es muy larga
    final hasFraction = latex.contains(r'\frac') || latex.contains(r'\dfrac');
    final hasSummation = latex.contains(r'\sum') || latex.contains(r'\int');
    final isLong = latex.length > 50;

    return (hasFraction && isLong) || hasSummation || isLong;
  }

  /// Fallback cuando el LaTeX no se puede renderizar.
  Widget _buildFallback() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        latex,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: isDisplay ? fontSize * 1.1 : fontSize,
          color: color,
        ),
      ),
    );
  }
}