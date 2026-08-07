// lib/widgets/html_math.dart
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Widget que renderiza HTML y además procesa expresiones TeX con
/// delimitadores \(...\) y \[...\].
class HtmlWithMath extends StatelessWidget {
  final String html;
  final EdgeInsetsGeometry? padding;
  final TextStyle? textStyle;

  const HtmlWithMath({
    Key? key,
    required this.html,
    this.padding,
    this.textStyle,
  }) : super(key: key);

  // 1) Marcamos las expresiones TEX dentro del HTML con etiquetas <tex>
  //    para poder separarlas y renderizarlas con flutter_math_fork.
  String _injectTexTags(String input) {
    String out = input;

    // Display math primero ( \[ ... ] )
    final display = RegExp(r'\\\[(.+?)\\\]', dotAll: true, multiLine: true);
    out = out.replaceAllMapped(display, (m) {
      final latex = m.group(1)!.trim();
      return '<tex data-display="1">${_escapeForTag(latex)}</tex>';
    });

    // Inline math ( \( ... ) )
    final inline = RegExp(r'\\\((.+?)\\\)', dotAll: true, multiLine: true);
    out = out.replaceAllMapped(inline, (m) {
      final latex = m.group(1)!.trim();
      return '<tex data-inline="1">${_escapeForTag(latex)}</tex>';
    });

    // (Opcional) Si usan $$...$$ y $...$, puedes habilitarlo:
    // Cuidado con falsos positivos si hay dólares en texto normal.
    // final displayDollars = RegExp(r'\$\$(.+?)\$\$', dotAll: true, multiLine: true);
    // out = out.replaceAllMapped(displayDollars, (m) =>
    //   '<tex data-display="1">${_escapeForTag(m.group(1)!.trim())}</tex>');
    // final inlineDollar = RegExp(r'(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)', dotAll: true, multiLine: true);
    // out = out.replaceAllMapped(inlineDollar, (m) =>
    //   '<tex data-inline="1">${_escapeForTag(m.group(1)!.trim())}</tex>');

    return out;
  }

  // Evita que caracteres especiales rompan el HTML al insertar dentro de <tex>
  String _escapeForTag(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  // 2) Separamos por bloques <tex ...>...</tex> para mezclar Html + Math.tex.
  List<_Segment> _splitIntoSegments(String input) {
    final re = RegExp(
      r'<tex([^>]*)>([\s\S]*?)<\/tex>',
      multiLine: true,
      dotAll: true,
    );

    final segments = <_Segment>[];
    int last = 0;
    for (final m in re.allMatches(input)) {
      if (m.start > last) {
        // HTML normal entre bloques TeX
        segments.add(_Segment.html(input.substring(last, m.start)));
      }
      final attrsRaw = m.group(1) ?? '';
      final latexEscaped = m.group(2) ?? '';
      final latex = latexEscaped
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&amp;', '&');

      final isDisplay = attrsRaw.contains('data-display="1"');
      final isInline = attrsRaw.contains('data-inline="1"');

      segments.add(_Segment.tex(latex, display: isDisplay, inline: isInline));
      last = m.end;
    }
    if (last < input.length) {
      segments.add(_Segment.html(input.substring(last)));
    }

    return segments;
  }

  @override
  Widget build(BuildContext context) {
    final prepared = _injectTexTags(html);
    final segments = _splitIntoSegments(prepared);

    final children = <Widget>[];
    for (final seg in segments) {
      if (seg.kind == _SegKind.html) {
        final data = seg.htmlData.trim();
        if (data.isEmpty) continue;
        children.add(
          Html(
            data: data,
            style: {
              "body": Style.fromTextStyle(textStyle ?? TextStyle(fontSize: 16)),
            },
          ),
        );
      } else {
        // Render TeX
        final isDisplay = seg.display;
        final latex = seg.latexData;

        // Ajusta tamaños a tu gusto
        final math = Math.tex(
          latex,
          mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
          textStyle: (textStyle ?? TextStyle(fontSize: 16)).copyWith(
            fontSize: isDisplay ? 18 : 16,
          ),
        );

        // Si es display, dejamos margen vertical; inline lo dejamos tal cual.
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(vertical: isDisplay ? 6 : 0),
            child: math,
          ),
        );
      }
    }

    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

enum _SegKind { html, tex }

class _Segment {
  final _SegKind kind;
  final String htmlData;
  final String latexData;
  final bool display;
  final bool inline;

  _Segment.html(this.htmlData)
      : latexData = '',
        display = false,
        inline = false,
        kind = _SegKind.html;

  _Segment.tex(this.latexData, {required this.display, required this.inline})
      : htmlData = '',
        kind = _SegKind.tex;
}
