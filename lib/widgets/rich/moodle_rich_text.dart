// lib/widgets/rich/moodle_rich_text.dart
// Saber+ — Renderizador de contenido Moodle (preguntas, opciones, feedback).
//
// Problema que resuelve (v1.7.1):
//  1. Las tablas HTML de las preguntas no se mostraban en la app.
//  2. Las imágenes de las opciones de respuesta no se mostraban.
//  3. Las imágenes del enunciado salían todas amontonadas ARRIBA del texto
//     en vez de distribuidas donde aparecen en el contenido.
//
// Solución: en lugar de extraer imágenes con regex y reordenarlas, este
// widget recorre el árbol DOM del HTML y lo renderiza EN ORDEN:
//  - Texto con formato + matemáticas  → MathText (existente, sin tocar)
//  - <img>                            → QImage inline (táctil → zoom)
//  - <table>                          → MoodleTable (nativo, con bordes)
//  - <ul>/<ol>/<li>                   → listas con viñetas/números
//  - <p>/<div>/encabezados            → bloques con espaciado
//
// Las URLs de imagen se proxyean de forma inteligente (sin doble proxy).
//
// OPTIMIZACIÓN (motor v2):
//   Se añade el constructor `MoodleRichText(blocks:)` que acepta una lista
//   de `QuizBlock` pre-parseados (AST). Esto elimina `parseFragment` y
//   `_DomWalker` del `build()`, que era el cuello de botella principal.
//   El constructor legacy `MoodleRichText(html:)` se mantiene para
//   compatibilidad con otros usos y como fallback.

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as htmlParser;
import 'package:html/dom.dart' as dom;
import '../../core/theme/app_colors.dart';
import '../../models/quiz_block.dart';
import '../math/math_text.dart';
import 'moodle_table.dart';
import 'q_image.dart';

class MoodleRichText extends StatelessWidget {
  /// HTML crudo (modo legacy).
  final String? html;

  /// AST pre-parseado (modo optimizado).
  final List<QuizBlock>? blocks;

  final bool isOption;

  /// Altura máxima de las imágenes embebidas.
  final double maxImageHeight;

  /// Callback al tocar una imagen: recibe TODAS las URLs (ya proxyadas,
  /// en orden de documento) y el índice de la imagen tocada.
  final void Function(List<String> proxiedUrls, int index)? onImageTap;

  /// Constructor unificado: acepta `html` o `blocks`.
  /// Si se proporcionan ambos, se prioriza `blocks`.
  const MoodleRichText({
    Key? key,
    this.html,
    this.blocks,
    this.isOption = false,
    this.maxImageHeight = 220,
    this.onImageTap,
  })  : assert(html != null || blocks != null, 'Debe proporcionar html o blocks'),
        super(key: key);

  /// Constructor optimizado explícito (mantenido por compatibilidad).
  const MoodleRichText.blocks({
    Key? key,
    required List<QuizBlock> this.blocks,
    this.isOption = false,
    this.maxImageHeight = 220,
    this.onImageTap,
  })  : html = null,
        super(key: key);

  /// Constructor para renderizar el contenido de un elemento DOM
  /// (usado por las celdas de MoodleTable, soporta anidación).
  factory MoodleRichText.fromElement({
    required dom.Element element,
    double? fontSize,
    bool boldAll = false,
    void Function(List<String> urls, int index)? onImageTap,
    double maxImageHeight = 110,
  }) {
    var inner = element.innerHtml;
    if (boldAll && inner.isNotEmpty) {
      inner = '<b>$inner</b>';
    }
    return MoodleRichText(
      html: inner,
      isOption: (fontSize ?? 14) <= 14,
      maxImageHeight: maxImageHeight,
      onImageTap: onImageTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ── Modo optimizado: AST pre-parseado ──
    if (blocks != null) {
      return _buildFromBlocks(blocks!);
    }

    // ── Modo legacy: parsear HTML al vuelo (comportamiento original) ──
    final source = (html ?? '').trim();
    if (source.isEmpty) return const SizedBox.shrink();

    final fragment = htmlParser.parseFragment(source);
    final walker = _DomWalker(
      isOption: isOption,
      maxImageHeight: maxImageHeight,
      onImageTap: onImageTap,
    );
    walker.walkNodes(fragment.nodes);

    if (walker.output.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: walker.output,
    );
  }

  /// Construye el árbol de widgets a partir del AST pre-parseado.
  Widget _buildFromBlocks(List<QuizBlock> blockList) {
    if (blockList.isEmpty) return const SizedBox.shrink();

    final widgets = <Widget>[];
    final imageUrls = <String>[];
    bool lastWasSpacer = false;

    for (final block in blockList) {
      switch (block) {
        case TextBlock():
          if (block.html.trim().isEmpty) continue;
          widgets.add(MathText.fromSegments(
            segments: [block],
            isOption: isOption,
          ));
          lastWasSpacer = false;

        case MathBlock():
          widgets.add(MathText.fromSegments(
            segments: [block],
            isOption: isOption,
          ));
          lastWasSpacer = false;

        case ImageBlock(:final proxiedSrc, :final src):
          if (proxiedSrc.isEmpty) continue;
          if (_shouldAddSpacer(widgets, lastWasSpacer)) {
            widgets.add(SizedBox(height: isOption ? 6 : 8));
            lastWasSpacer = true;
          }
          final index = imageUrls.length;
          imageUrls.add(proxiedSrc);
          widgets.add(QImage(
            src: proxiedSrc,
            maxHeight: maxImageHeight,
            onTap: onImageTap != null
                ? () => onImageTap!(imageUrls, index)
                : null,
          ));
          lastWasSpacer = false;

        case TableBlock():
          if (_shouldAddSpacer(widgets, lastWasSpacer)) {
            widgets.add(SizedBox(height: isOption ? 6 : 8));
            lastWasSpacer = true;
          }
          widgets.add(MoodleTable.fromBlock(
            block: block,
            fontSize: isOption ? 13 : 14,
            onImageTap: onImageTap != null
                ? (urls, idx) => onImageTap!(urls, idx)
                : null,
            maxImageHeight: maxImageHeight * 0.55,
          ));
          lastWasSpacer = false;

        case ListBlock(:final ordered, :final items):
          if (_shouldAddSpacer(widgets, lastWasSpacer)) {
            widgets.add(SizedBox(height: isOption ? 6 : 8));
            lastWasSpacer = true;
          }
          widgets.add(_buildListBlock(ordered, items));
          lastWasSpacer = false;

        case CodeBlock(:final text):
          if (_shouldAddSpacer(widgets, lastWasSpacer)) {
            widgets.add(SizedBox(height: isOption ? 6 : 8));
            lastWasSpacer = true;
          }
          widgets.add(_codeBlock(text));
          lastWasSpacer = false;

        case MediaPlaceholderBlock(:final tag):
          if (_shouldAddSpacer(widgets, lastWasSpacer)) {
            widgets.add(SizedBox(height: isOption ? 6 : 8));
            lastWasSpacer = true;
          }
          widgets.add(_mediaPlaceholder(tag));
          lastWasSpacer = false;

        case SpacerBlock(:final height):
          widgets.add(SizedBox(height: height));
          lastWasSpacer = true;

        case DividerBlock():
          if (_shouldAddSpacer(widgets, lastWasSpacer)) {
            widgets.add(SizedBox(height: isOption ? 6 : 8));
            lastWasSpacer = true;
          }
          widgets.add(_divider());
          lastWasSpacer = false;
      }
    }

    if (widgets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  /// Construye una lista (ordenada o desordenada) a partir de un `ListBlock`.
  Widget _buildListBlock(bool ordered, List<List<QuizBlock>> items) {
    final listWidgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final itemBlocks = items[i];
      final marker = ordered
          ? Text(
              '${i + 1}.',
              style: TextStyle(
                fontSize: isOption ? 14 : 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            )
          : Icon(
              Icons.circle,
              size: 6,
              color: AppColors.primary,
            );

      final itemWidget = MoodleRichText.blocks(
        blocks: itemBlocks,
        isOption: isOption,
        maxImageHeight: maxImageHeight,
        onImageTap: onImageTap,
      );

      listWidgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: marker,
            ),
            Expanded(child: itemWidget),
          ],
        ),
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: listWidgets,
      ),
    );
  }

  bool _shouldAddSpacer(List<Widget> widgets, bool lastWasSpacer) {
    return widgets.isNotEmpty && !lastWasSpacer;
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppColors.border.withOpacity(0.7),
      ),
    );
  }

  Widget _mediaPlaceholder(String tag) {
    final label = tag == 'video'
        ? 'Video'
        : tag == 'audio'
            ? 'Audio'
            : 'Contenido multimedia';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            tag == 'audio' ? Icons.headphones : Icons.play_circle_outline,
            size: 18,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 6),
          Text(
            '$label — disponible en la versión web del curso',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeBlock(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: Color(0xFFE2E8F0),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Caminante del DOM — convierte nodos HTML en widgets Flutter.
// ═══════════════════════════════════════════════════════════════════

class _DomWalker {
  final bool isOption;
  final double maxImageHeight;
  final void Function(List<String>, int)? onImageTap;

  final List<Widget> output = [];
  final StringBuffer _buffer = StringBuffer();
  final List<String> _rawImageSrcs = [];
  bool _lastWasSpacer = false;

  static const Set<String> _blockTags = {
    'p', 'div', 'table', 'ul', 'ol', 'li', 'blockquote', 'figure',
    'figcaption', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'pre',
    'center', 'article', 'section', 'main', 'aside', 'nav', 'form',
  };

  static const Set<String> _skipTags = {
    'script', 'style', 'noscript', 'head', 'title', 'meta', 'link',
  };

  static const Set<String> _mediaTags = {'video', 'audio', 'iframe', 'embed', 'object'};

  _DomWalker({
    required this.isOption,
    required this.maxImageHeight,
    this.onImageTap,
  });

  void walkNodes(Iterable<dom.Node> nodes) {
    for (final node in nodes) {
      _visit(node);
    }
    _flush();
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
        _flush();
        if (output.isNotEmpty && !_lastWasSpacer) {
          output.add(SizedBox(height: isOption ? 3 : 5));
          _lastWasSpacer = true;
        }
        break;

      case 'hr':
        _flush();
        _addBlockSpacing();
        output.add(_divider());
        _lastWasSpacer = false;
        break;

      case 'table':
        _flush();
        _addBlockSpacing();
        output.add(MoodleTable(
          tableElement: node,
          fontSize: isOption ? 13 : 14,
          onImageTap: _galleryTap,
          maxImageHeight: maxImageHeight * 0.55,
        ));
        _lastWasSpacer = false;
        break;

      case 'ul':
      case 'ol':
        _flush();
        _handleList(node, ordered: tag == 'ol');
        break;

      case 'video':
      case 'audio':
      case 'iframe':
      case 'embed':
        _flush();
        _addBlockSpacing();
        output.add(_mediaPlaceholder(tag));
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
        _handleHeading(node);
        break;

      case 'li':
        _handleBlock(node);
        break;

      case 'pre':
        _flush();
        _addBlockSpacing();
        output.add(_codeBlock(node));
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

  void _handleImage(dom.Element img) {
    final src = img.attributes['src']?.trim() ?? '';
    if (src.isEmpty || src.startsWith('@@PLUGINFILE@@')) return;

    _flush();
    _addBlockSpacing();
    final index = _rawImageSrcs.length;
    _rawImageSrcs.add(src);
    output.add(QImage(
      src: src,
      maxHeight: maxImageHeight,
      onTap: onImageTap != null ? () => _galleryTap(_proxiedUrls(), index) : null,
    ));
    _lastWasSpacer = false;
  }

  List<String> _proxiedUrls() =>
      _rawImageSrcs.map(QImage.smartProxy).toList();

  void _galleryTap(List<String> urls, int index) {
    onImageTap?.call(urls, index);
  }

  void _handleBlock(dom.Element element) {
    _flush();
    final spacerAdded = _maybeAddBlockSpacing();
    final before = output.length;
    walkNodes(element.nodes);
    _flush();
    if (output.length == before && spacerAdded) {
      output.removeLast();
      _lastWasSpacer = false;
    }
  }

  void _handleHeading(dom.Element element) {
    _handleBlock(element);
  }

  void _handleList(dom.Element list, {required bool ordered}) {
    _flush();
    _addBlockSpacing();
    final items = list.children
        .where((e) => e.localName == 'li')
        .toList(growable: false);

    if (items.isEmpty) {
      walkNodes(list.nodes);
      _flush();
      return;
    }

    final listWidgets = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final li = items[i];
      final sub = _DomWalker(
        isOption: isOption,
        maxImageHeight: maxImageHeight,
        onImageTap: _wrapSubTap,
      );
      sub.walkNodes(li.nodes);
      sub._flush();

      final marker = ordered
          ? Text(
              '${i + 1}.',
              style: TextStyle(
                fontSize: isOption ? 14 : 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            )
          : Icon(
              Icons.circle,
              size: 6,
              color: AppColors.primary,
            );

      listWidgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: marker,
            ),
            Expanded(
              child: sub.output.length == 1
                  ? sub.output.first
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: sub.output,
                    ),
            ),
          ],
        ),
      ));
    }

    output.add(Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: listWidgets,
      ),
    ));
    _lastWasSpacer = false;
  }

  void Function(List<String>, int)? get _wrapSubTap {
    if (onImageTap == null) return null;
    return (urls, index) => onImageTap!(urls, index);
  }

  void _flush() {
    final text = _buffer.toString().trim();
    _buffer.clear();
    if (text.isEmpty) return;
    output.add(MathText(html: text, isOption: isOption));
  }

  bool _maybeAddBlockSpacing() {
    if (output.isNotEmpty && !_lastWasSpacer) {
      output.add(SizedBox(height: isOption ? 6 : 8));
      _lastWasSpacer = true;
      return true;
    }
    return false;
  }

  void _addBlockSpacing() {
    _maybeAddBlockSpacing();
  }

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

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppColors.border.withOpacity(0.7),
      ),
    );
  }

  Widget _mediaPlaceholder(String tag) {
    final label = tag == 'video'
        ? 'Video'
        : tag == 'audio'
            ? 'Audio'
            : 'Contenido multimedia';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            tag == 'audio' ? Icons.headphones : Icons.play_circle_outline,
            size: 18,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 6),
          Text(
            '$label — disponible en la versión web del curso',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeBlock(dom.Element element) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        element.text,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: Color(0xFFE2E8F0),
        ),
      ),
    );
  }
}