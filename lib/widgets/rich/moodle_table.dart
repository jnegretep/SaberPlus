// lib/widgets/rich/moodle_table.dart
// Saber+ — Renderizador nativo de tablas HTML de Moodle.
//
// ¿Por qué un renderer propio? flutter_html 3.0.0 tiene soporte de tablas
// inestable (tablas que no muestran su contenido, celdas sin bordes,
// crash de intrinsic width con imágenes dentro de celdas). Este widget:
// - Parsea <table>/<thead>/<tbody>/<tr>/<td>/<th> con el paquete html.
// - Expande colspan/rowspan a una matriz de celdas.
// - Renderiza con el widget Table nativo de Flutter (IntrinsicColumnWidth).
// - Cada celda se renderiza recursivamente con MoodleRichText → soporta
//   texto con formato, matemáticas, imágenes e incluso tablas anidadas.
// - Bordes estilo "collapse" (cada celda dibuja derecha+abajo, el contenedor
//   dibuja arriba+izquierda), encabezados con fondo, filas alternadas.
//
// OPTIMIZACIÓN (motor v2):
//   Se añade el constructor `MoodleTable.fromBlock` que acepta un
//   `TableBlock` pre-parseado (producido por `quiz_block_parser.dart`).
//   Esto evita volver a ejecutar `_parse()` en cada `build()`. El
//   constructor legacy se mantiene para compatibilidad con otros usos.

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import '../../core/theme/app_colors.dart';
import '../../models/quiz_block.dart';
import 'moodle_rich_text.dart';

class MoodleTable extends StatelessWidget {
  /// Elemento DOM crudo (modo legacy). Si es `null`, se usa `block`.
  final dom.Element? tableElement;

  /// Bloque pre-parseado (modo optimizado). Si es `null`, se usa `tableElement`.
  final TableBlock? block;

  final double fontSize;
  final void Function(List<String> urls, int index)? onImageTap;
  final double maxImageHeight;

  /// Constructor legacy: recibe elemento DOM y lo parsea en cada build.
  const MoodleTable({
    Key? key,
    required dom.Element this.tableElement,
    this.fontSize = 14,
    this.onImageTap,
    this.maxImageHeight = 110,
  })  : block = null,
        super(key: key);

  /// Constructor optimizado: recibe un `TableBlock` pre-parseado.
  ///
  /// Acepta la matriz de celdas ya expandida (colspan/rowspan resueltos).
  /// Cada celda es una `List<QuizBlock>` que se renderiza recursivamente
  /// con `MoodleRichText(blocks:)`. Esto elimina el coste de `_parse()`
  /// en cada `build()`.
  const MoodleTable.fromBlock({
    Key? key,
    required TableBlock this.block,
    this.fontSize = 14,
    this.onImageTap,
    this.maxImageHeight = 110,
  })  : tableElement = null,
        super(key: key);

  // ── Modelo de celda expandida (modo legacy) ──
  _ParsedTable? _parse(dom.Element tableEl) {
    final rows = tableEl.querySelectorAll('tr');
    if (rows.isEmpty) return null;

    final cells = <_CellInfo>[];
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
        cells.add(_CellInfo(
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

    // Fila de encabezado: si hay <thead> con <th>, o la primera fila son <th>.
    final thead = tableEl.querySelector('thead');
    final hasHeaderRow = (thead != null &&
            thead.querySelector('th') != null) ||
        cells.any((c) => c.row == 0 && c.isHeader);

    return _ParsedTable(cells: cells, rows: rows.length, cols: totalCols,
        hasHeaderRow: hasHeaderRow);
  }

  static int _clampSpan(String? raw, int max) {
    final v = int.tryParse(raw?.trim() ?? '') ?? 1;
    if (v < 1) return 1;
    if (v > max) return max;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final parsed = block != null
        ? _ParsedTable.fromBlock(block!)
        : _parse(tableElement!);
    if (parsed == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.darkBorder : const Color(0xFFCBD5E1);
    final headerBg = isDark
        ? const Color(0xFF1E3A8A).withOpacity(0.35)
        : const Color(0xFFE0E7FF);
    final headerFg =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF1E3A8A);
    final altRowBg = isDark
        ? AppColors.darkSurfaceVariant.withOpacity(0.45)
        : const Color(0xFFF8FAFC);

    // Mapa r-c → celda para acceso O(1).
    final cellMap = <String, _CellInfo>{};
    for (final cell in parsed.cells) {
      cellMap['${cell.row}-${cell.col}'] = cell;
    }

    final tableWidget = Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: List<TableRow>.generate(parsed.rows, (r) {
        final isHeader = parsed.hasHeaderRow && r == 0;
        final isAltRow = !isHeader && r % 2 == 0;
        return TableRow(
          children: List<Widget>.generate(parsed.cols, (c) {
            final cell = cellMap['$r-$c'];
            if (cell == null) {
              // Posición cubierta por un colspan/rowspan → hueco invisible.
              return const SizedBox.shrink();
            }
            final cellBg = isHeader
                ? headerBg
                : (isAltRow ? altRowBg : Colors.transparent);

            return Container(
              decoration: BoxDecoration(
                color: cellBg,
                border: Border(
                  right: BorderSide(color: borderColor, width: 0.8),
                  bottom: BorderSide(color: borderColor, width: 0.8),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
              child: cell.cellBlocks != null
                  ? DefaultTextStyle.merge(
                      style: TextStyle(
                        // ✅ FIX B3: en modo legacy `boldAll: cell.isHeader ||
                        // isHeader` envolvía innerHtml en <b>. En modo AST
                        // aplicamos bold con DefaultTextStyle para preservar
                        // el estilo de encabezados sin mutar el AST.
                        fontWeight: (cell.isHeader || isHeader)
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                      child: MoodleRichText(blocks: cell.cellBlocks!),
                    )
                  : MoodleRichText.fromElement(
                      element: cell.element!,
                      fontSize: isHeader ? fontSize : fontSize - 0.5,
                      boldAll: cell.isHeader || isHeader,
                      onImageTap: onImageTap,
                      maxImageHeight: maxImageHeight,
                    ),
            );
          }),
        );
      }),
    );

    // Contenedor exterior: borde superior+izquierdo + esquinas redondeadas.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border(
          top: BorderSide(color: borderColor, width: 0.8),
          left: BorderSide(color: borderColor, width: 0.8),
        ),
        color: isDark ? AppColors.darkSurface : Colors.white,
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.25) : AppColors.shadowSm,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: tableWidget,
        ),
      ),
    );
  }
}

class _ParsedTable {
  final List<_CellInfo> cells;
  final int rows;
  final int cols;
  final bool hasHeaderRow;
  _ParsedTable({
    required this.cells,
    required this.rows,
    required this.cols,
    required this.hasHeaderRow,
  });

  /// Construye un `_ParsedTable` directamente desde un `TableBlock` ya
  /// pre-parseado. No requiere invocar `_parse()`.
  factory _ParsedTable.fromBlock(TableBlock b) {
    final cells = <_CellInfo>[];
    for (int r = 0; r < b.rows; r++) {
      for (int c = 0; c < b.cols; c++) {
        final cellBlocks = b.cells[r][c];
        // Solo creamos una entrada _CellInfo para la celda origen (no para
        // las celdas expandidas por colspan/rowspan, que están vacías en el
        // bloque pre-parseado).
        if (cellBlocks.isEmpty) continue;
        cells.add(_CellInfo(
          row: r,
          col: c,
          colspan: 1,
          rowspan: 1,
          element: null,
          cellBlocks: cellBlocks,
          isHeader: b.hasHeaderRow && r == 0,
        ));
      }
    }
    return _ParsedTable(
      cells: cells,
      rows: b.rows,
      cols: b.cols,
      hasHeaderRow: b.hasHeaderRow,
    );
  }
}

class _CellInfo {
  final int row;
  final int col;
  final int colspan;
  final int rowspan;
  /// Elemento DOM crudo (modo legacy). `null` si se usa `cellBlocks`.
  final dom.Element? element;
  /// Bloques pre-parseados (modo optimizado). `null` si se usa `element`.
  final List<QuizBlock>? cellBlocks;
  final bool isHeader;
  _CellInfo({
    required this.row,
    required this.col,
    required this.colspan,
    required this.rowspan,
    this.element,
    this.cellBlocks,
    required this.isHeader,
  });
}
