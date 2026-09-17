// lib/widgets/math/math_text.dart
// Saber+ - Renderizado de texto con ecuaciones matematicas
//
// FIX: Volviendo al enfoque simple que funcionaba.
// NO normaliza $...$ (Moodle ya usa \(...\))
// NO limpia el LaTeX con _cleanLatex (solo quita delimitadores)
// Solo convierte $$...$$ y MathML que si son necesarios.

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_logger.dart';

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

    // Solo normalizar $$...$$ a \[...\] y entidades HTML basicas
    final normalized = _normalize(html);

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

      widgets.add(
        Padding(
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
            // 🔧 FIX: onErrorFallback espera `Widget Function(FlutterMathException)`.
            // Si el LaTeX es inválido, mostramos el código crudo como texto plano
            // en lugar de romper el árbol de widgets.
            onErrorFallback: (error) {
              AppLogger.w('Math render error: ${error.message} (latex=$latex)');
              return Text(
                latex,
                style: TextStyle(fontSize: fontSize, color: color),
              );
            },
          ),
        ),
      );

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