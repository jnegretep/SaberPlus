// lib/parsers/quiz_block_parser.dart
// Saber+ — Parser HTML → AST de bloques (QuizBlock).
//
// Propósito:
//   Convierte el HTML crudo de Moodle en un AST serializable (List<QuizBlock>)
//   que los widgets pueden consumir directamente sin volver a parsear.
//
//   Esta función es PURE FUNCTION (no toca Flutter, no toca BuildContext),
//   apta para ejecutarse en isolate vía `compute()`.
//
// FIX M2 (2026-11-13):
//   `parseQuestionBlocks` recibe `apiBaseUrl` como parámetro obligatorio y
//   lo propaga a `_BlockWalker` → `_parseHtmlToBlocks` → `_handleImage` →
//   `QImage.smartProxy(src, apiBaseUrl: ...)`. Antes `smartProxy` leía
//   `Env.apiBaseUrl` internamente, lo que lanzaba `NotInitializedError`
//   dentro del isolate (DotEnv no inicializado allí) y tumbaba el 100%
//   de los lotes que contenían imágenes.

import 'package:html/parser.dart' as htmlParser;
import 'package:html/dom.dart' as dom;

import '../models/quiz_block.dart';
import '../models/quiz_question.dart';
import '../widgets/rich/q_image.dart';

/// Parsea una pregunta completa (con HTML crudo) a su AST de bloques.
///
/// Esta función es la entrada principal del preprocesador. Es top-level
/// para que pueda invocarse vía `compute(...)`.
///
/// [apiBaseUrl] debe leerse en main thread (vía `Env.apiBaseUrl`) y
/// pasarse explícito al isolate. Ver FIX M2.
QuestionBlocks parseQuestionBlocks(
  QuizQuestion q, {
  required String apiBaseUrl,
}) {
  // ── 1) Enunciado (questionText) ──
  final questionTextBlocks = _parseHtmlToBlocks(q.questionText, apiBaseUrl);

  // ── 2) Opciones ──
  final optionBlocks = q.options.map((opt) {
    return AnswerOptionBlocks(
      value: opt.value,
      label: _parseHtmlToBlocks(opt.labelHtml, apiBaseUrl),
    );
  }).toList(growable: false);

  return QuestionBlocks(
    slot: q.slot,
    questionText: questionTextBlocks,
    options: optionBlocks,
  );
}

// ═══════════════════════════════════════════════════════════════════
// Walker DOM → List<QuizBlock>
// ═══════════════════════════════════════════════════════════════════

const Set<String> _blockTags = {
  'p', 'div', 'table', 'ul', 'ol', 'li', 'blockquote', 'figure',
  'figcaption', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'pre',
  'center', 'article', 'section', 'main', 'aside', 'nav', 'form',
};

const Set<String> _skipTags = {
  'script', 'style', 'noscript', 'head', 'title', 'meta', 'link',
};

const Set<String> _mediaTags = {'video', 'audio', 'iframe', 'embed', 'object'};

/// Convierte un String HTML en `List<QuizBlock>`.
List<QuizBlock> _parseHtmlToBlocks(String htmlSource, String apiBaseUrl) {
  final source = htmlSource.trim();
  if (source.isEmpty) return const [];

  final fragment = htmlParser.parseFragment(source);
  final walker = _BlockWalker(apiBaseUrl);
  walker.walkNodes(fragment.nodes);
  walker.flush();
  return walker.output;
}

/// Walker que produce `List<QuizBlock>` a partir de nodos DOM.
///
/// Replica EXACTAMENTE la lógica de `_DomWalker` de `moodle_rich_text.dart`:
/// - Misma clasificación de tags (block/skip/media).
/// - Mismo manejo de texto acumulado (buffer + flush).
/// - Mismo manejo de listas (sub-walker por item).
/// - Mismo manejo de tablas (matriz de celdas).
/// - Mismos espaciados entre bloques.
class _BlockWalker {
  final String apiBaseUrl;
  final List<QuizBlock> output = [];
  final StringBuffer _buffer = StringBuffer();
  bool _lastWasSpacer = false;

  _BlockWalker(this.apiBaseUrl);

  void walkNodes(Iterable<dom.Node> nodes) {
    for (final node in nodes) {
      _visit(node);
    }
  }

  void flush() {
    final text = _buffer.toString().trim();
    _buffer.clear();
    if (text.isEmpty) return;
    final segments = _segmentHtmlAndMath(text);
    output.addAll(segments);
  }

  void _visit(dom.Node node) {
    if (node is dom.Text) {
      final collapsed = _collapseWhitespace(node.text);
      if (collapsed.isNotEmpty) {
        _buffer.write(_escapeText(collapsed));
        _lastWasSpacer = false;
      }
      return;
    }

    if (node is! dom.Element) return;

    final tag = node.localName?.toLowerCase() ?? '';

    if (_skipTags.contains(tag)) return;

    switch (tag) {
      case 'img':
        _handleImage(node);
        break;

      case 'br':
        flush();
        if (output.isNotEmpty && !_lastWasSpacer) {
          output.add(const SpacerBlock(5));
          _lastWasSpacer = true;
        }
        break;

      case 'hr':
        flush();
        _addBlockSpacing();
        output.add(const DividerBlock());
        _lastWasSpacer = false;
        break;

      case 'table':
        flush();
        _addBlockSpacing();
        final tableBlock = _parseTable(node, apiBaseUrl);
        if (tableBlock != null) output.add(tableBlock);
        _lastWasSpacer = false;
        break;

      case 'ul':
      case 'ol':
        flush();
        _handleList(node, ordered: tag == 'ol');
        break;

      case 'video':
      case 'audio':
      case 'iframe':
      case 'embed':
      case 'object':
        flush();
        _addBlockSpacing();
        output.add(MediaPlaceholderBlock(tag));
        _lastWasSpacer = false;
        break;

      case 'p':
      case 'div':
      case 'center':
      case 'figure':
      case 'article':
      case 'section':
      case 'blockquote':
        _handleBlock(node);
        break;

      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        _handleBlock(node);
        break;

      case 'li':
        _handleBlock(node);
        break;

      case 'pre':
        flush();
        _addBlockSpacing();
        output.add(CodeBlock(node.text));
        _lastWasSpacer = false;
        break;

      default:
        if (_hasBlockDescendant(node)) {
          _handleBlock(node);
        } else {
          _buffer.write(node.outerHtml);
          _lastWasSpacer = false;
        }
    }
  }

  // ── Imagen → ImageBlock ──
  void _handleImage(dom.Element img) {
    final src = img.attributes['src']?.trim() ?? '';
    if (src.isEmpty || src.startsWith('@@PLUGINFILE@@')) return;

    flush();
    _addBlockSpacing();
    // ✅ FIX M2: pasar apiBaseUrl explícito. En isolate, Env.apiBaseUrl
    //    lanzaría NotInitializedError.
    final proxied = QImage.smartProxy(src, apiBaseUrl: apiBaseUrl);
    output.add(ImageBlock(
      src: src,
      proxiedSrc: proxied,
      alt: img.attributes['alt']?.trim() ?? '',
    ));
    _lastWasSpacer = false;
  }

  // ── Bloque genérico: <p>, <div>, ... ──
  void _handleBlock(dom.Element element) {
    flush();
    final spacerAdded = _maybeAddBlockSpacing();
    final before = output.length;
    walkNodes(element.nodes);
    flush();
    if (output.length == before && spacerAdded) {
      output.removeLast();
      _lastWasSpacer = false;
    }
  }

  // ── Listas → ListBlock ──
  void _handleList(dom.Element list, {required bool ordered}) {
    flush();
    _addBlockSpacing();
    final items = list.children
        .where((e) => e.localName == 'li')
        .toList(growable: false);

    if (items.isEmpty) {
      walkNodes(list.nodes);
      flush();
      return;
    }

    final itemBlocks = <List<QuizBlock>>[];
    for (final li in items) {
      // ✅ FIX M2: propagar apiBaseUrl al sub-walker.
      final sub = _BlockWalker(apiBaseUrl);
      sub.walkNodes(li.nodes);
      sub.flush();
      itemBlocks.add(sub.output);
    }

    output.add(ListBlock(ordered: ordered, items: itemBlocks));
    _lastWasSpacer = false;
  }

  bool _maybeAddBlockSpacing() {
    if (output.isNotEmpty && !_lastWasSpacer) {
      output.add(const SpacerBlock(8));
      _lastWasSpacer = true;
      return true;
    }
    return false;
  }

  void _addBlockSpacing() {
    _maybeAddBlockSpacing();
  }

  // ── Utilidades ──

  bool _hasBlockDescendant(dom.Element element) {
    for (final child in element.children) {
      final tag = child.localName?.toLowerCase() ?? '';
      if (_blockTags.contains(tag) ||
          _mediaTags.contains(tag) ||
          tag == 'img' ||
          tag == 'br' ||
          _hasBlockDescendant(child)) {
        return true;
      }
    }
    return false;
  }

  static String _collapseWhitespace(String s) {
    return s.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _escapeText(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}

// ═══════════════════════════════════════════════════════════════════
// Tabla → TableBlock
// ═══════════════════════════════════════════════════════════════════

TableBlock? _parseTable(dom.Element tableElement, String apiBaseUrl) {
  final rows = tableElement.querySelectorAll('tr');
  if (rows.isEmpty) return null;

  final cellInfos = <_CellInfo>[];
  final occupied = <String>{};
  int totalCols = 0;

  for (int r = 0; r < rows.length; r++) {
    final tr = rows[r];
    final tds = tr.children
        .where((e) => e.localName == 'td' || e.localName == 'th')
        .toList();
    int c = 0;
    for (final td in tds) {
      while (occupied.contains('$r-$c')) {
        c++;
      }
      final colspan = _clampSpan(td.attributes['colspan'], 6);
      final rowspan = _clampSpan(td.attributes['rowspan'], 30);
      final isHeader = td.localName == 'th';
      cellInfos.add(_CellInfo(
        row: r,
        col: c,
        colspan: colspan,
        rowspan: rowspan,
        element: td,
        isHeader: isHeader,
      ));
      for (int dr = 0; dr < rowspan; dr++) {
        for (int dc = 0; dc < colspan; dc++) {
          if (dr > 0 || dc > 0) occupied.add('${r + dr}-${c + dc}');
        }
      }
      c += colspan;
    }
    if (c > totalCols) totalCols = c;
  }

  if (totalCols == 0) return null;

  final thead = tableElement.querySelector('thead');
  final hasHeaderRow = (thead != null && thead.querySelector('th') != null) ||
      cellInfos.any((c) => c.row == 0 && c.isHeader);

  final cellsMatrix = List<List<List<QuizBlock>>>.generate(
    rows.length,
    (_) => List<List<QuizBlock>>.generate(totalCols, (_) => const []),
  );

  for (final info in cellInfos) {
    if (cellsMatrix[info.row][info.col].isEmpty) {
      // ✅ FIX M2: propagar apiBaseUrl al sub-walker de cada celda.
      final cellWalker = _BlockWalker(apiBaseUrl);
      cellWalker.walkNodes(info.element.nodes);
      cellWalker.flush();
      cellsMatrix[info.row][info.col] = cellWalker.output;
    }
  }

  return TableBlock(
    rows: rows.length,
    cols: totalCols,
    cells: cellsMatrix,
    hasHeaderRow: hasHeaderRow,
  );
}

class _CellInfo {
  final int row;
  final int col;
  final int colspan;
  final int rowspan;
  final dom.Element element;
  final bool isHeader;
  _CellInfo({
    required this.row,
    required this.col,
    required this.colspan,
    required this.rowspan,
    required this.element,
    required this.isHeader,
  });
}

int _clampSpan(String? raw, int max) {
  final v = int.tryParse(raw?.trim() ?? '') ?? 1;
  if (v < 1) return 1;
  if (v > max) return max;
  return v;
}

// ═══════════════════════════════════════════════════════════════════
// Segmentación HTML ↔ LaTeX
// ═══════════════════════════════════════════════════════════════════

String _normalizeHtmlWithMath(String input) {
  var result = input;

  result = result.replaceAllMapped(
    RegExp(r'\$\$(.+?)\$\$', dotAll: true),
    (m) => '\\[${m.group(1)}\\]',
  );

  result = result.replaceAllMapped(
    RegExp(r'<math[^>]*>(.*?)</math>', dotAll: true),
    (m) => '\\(${m.group(1)}\\)',
  );

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

List<QuizBlock> _segmentHtmlAndMath(String html) {
  if (html.trim().isEmpty) return const [];

  final normalized = _normalizeHtmlWithMath(html);

  final regex = RegExp(r'(\\\(.+?\\\)|\\\[.+?\\\])', dotAll: true);
  final matches = regex.allMatches(normalized);

  if (matches.isEmpty) {
    return [TextBlock(normalized)];
  }

  final blocks = <QuizBlock>[];
  int last = 0;

  for (final match in matches) {
    if (match.start > last) {
      final text = normalized.substring(last, match.start);
      if (text.trim().isNotEmpty) {
        blocks.add(TextBlock(text));
      }
    }

    final rawEq = match.group(0)!;
    final isDisplay = rawEq.startsWith(r'\[');
    final latex = rawEq
        .replaceAll(r'\(', '')
        .replaceAll(r'\)', '')
        .replaceAll(r'\[', '')
        .replaceAll(r'\]', '')
        .trim();

    blocks.add(MathBlock(latex, isDisplay: isDisplay));

    last = match.end;
  }

  if (last < normalized.length) {
    final text = normalized.substring(last);
    if (text.trim().isNotEmpty) {
      blocks.add(TextBlock(text));
    }
  }

  return blocks;
}