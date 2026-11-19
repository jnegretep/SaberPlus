// lib/models/quiz_block.dart
// Saber+ — Modelo intermedio de contenido (AST) para el motor de cuestionarios.
//
// Propósito:
//   Representar el HTML crudo de Moodle como un árbol de bloques serializable.
//   Este AST se construye UNA SOLA VEZ por pregunta (en isolate vía compute())
//   y se consume N veces por los widgets de render en main thread.
//
//   Esto elimina el cuello de botella actual donde MoodleRichText/MathText
//   vuelven a ejecutar parseFragment + RegExp en cada build().
//
// Diseño:
//   - `QuizBlock` es una `sealed class`: el compilador fuerza `switch` exhaustivo.
//   - Todos los subtipos son `const` e inmutables.
//   - Los campos son tipos primitivos (String, int, double, bool, List) →
//     serializables entre isolates (necesario para compute()).
//   - Los bloques son autosuficientes: no referencian elementos del DOM
//     (`package:html`), ni widgets Flutter, ni BuildContext.

/// Bloque base del AST de contenido de Moodle.
sealed class QuizBlock {
  const QuizBlock();
}

/// Texto con formato HTML inline (puede contener <b>, <i>, <sub>, <sup>,
/// <span>, <a>, etc.) PERO sin matemáticas — el parser ya separó las
/// ecuaciones LaTeX en bloques [MathBlock] adyacentes.
///
/// El widget MathText recibe este bloque y lo renderiza con `flutter_html`
/// sin necesidad de normalizar ni re-segmentar.
class TextBlock extends QuizBlock {
  /// HTML inline ya normalizado (entidades decodificadas, $$ y MathML ya
  /// convertidos a `\(...\)` / `\[...\]` y extraídos como MathBlock).
  final String html;
  const TextBlock(this.html);
}

/// Ecuación matemática LaTeX aislada.
class MathBlock extends QuizBlock {
  /// LaTeX puro sin delimitadores (`\(`, `\)`, `\[`, `\]`).
  final String latex;

  /// `true` para ecuaciones display (`\[...\]`), `false` para inline (`\(...\)`).
  final bool isDisplay;
  const MathBlock(this.latex, {this.isDisplay = false});
}

/// Imagen embebida en el contenido.
class ImageBlock extends QuizBlock {
  /// URL original del HTML de Moodle (puede ser pluginfile).
  final String src;

  /// URL ya proxyada a través de `get_file.php` (lista para CachedNetworkImage).
  final String proxiedSrc;

  /// Texto alternativo si existe en el atributo `alt`.
  final String alt;

  const ImageBlock({
    required this.src,
    required this.proxiedSrc,
    this.alt = '',
  });
}

/// Tabla HTML pre-parseada a matriz de celdas.
///
/// Cada celda es una `List<QuizBlock>` (porque una celda puede contener
/// texto + imagen + math, etc.). El widget `MoodleTable` recibe este
/// bloque y construye un `Table` nativo sin necesidad de re-parsing.
class TableBlock extends QuizBlock {
  final int rows;
  final int cols;

  /// `cells[r][c]` = lista de bloques para esa celda.
  /// Las celdas vacías (colspan/rowspan) se representan como lista vacía.
  final List<List<List<QuizBlock>>> cells;

  /// `true` si la primera fila tiene `<th>` o clase `header`.
  final bool hasHeaderRow;

  /// Anchos relativos por columna (0..1) si están definidos en `<col>`.
  /// Si no, lista vacía → el widget usará `IntrinsicColumnWidth`.
  final List<double> columnWidths;

  const TableBlock({
    required this.rows,
    required this.cols,
    required this.cells,
    this.hasHeaderRow = false,
    this.columnWidths = const [],
  });
}

/// Lista ordenada o desordenada.
class ListBlock extends QuizBlock {
  /// `true` para `<ol>`, `false` para `<ul>`.
  final bool ordered;

  /// Cada item es la lista de bloques que contiene ese `<li>`.
  final List<List<QuizBlock>> items;
  const ListBlock({required this.ordered, required this.items});
}

/// Bloque de código preformateado (`<pre>`).
class CodeBlock extends QuizBlock {
  final String text;
  const CodeBlock(this.text);
}

/// Marcador de contenido multimedia no soportado en la app (video, audio,
/// iframe, embed, object). Se renderiza como placeholder informativo.
class MediaPlaceholderBlock extends QuizBlock {
  final String tag;
  const MediaPlaceholderBlock(this.tag);
}

/// Espaciador vertical entre bloques.
class SpacerBlock extends QuizBlock {
  final double height;
  const SpacerBlock(this.height);
}

/// Línea divisoria (`<hr>`).
class DividerBlock extends QuizBlock {
  const DividerBlock();
}

// ═══════════════════════════════════════════════════════════════════
// Contenedores agregados: una pregunta completa + opción de respuesta.
// ═══════════════════════════════════════════════════════════════════

/// Opción de respuesta con su contenido pre-procesado a AST.
class AnswerOptionBlocks {
  final String value;

  /// AST del label de la opción (texto, imágenes, math, etc.).
  final List<QuizBlock> label;

  const AnswerOptionBlocks({required this.value, required this.label});
}

/// Conjunto completo de bloques para una pregunta.
///
/// Cada campo (questionText, opciones, feedback, rightAnswer) es una lista
/// de bloques pre-procesados. Los campos opcionales son `null` cuando no
/// aplican (p. ej. `feedback` solo está en modo revisión).
class QuestionBlocks {
  /// Slot de Moodle — identificador estable de la pregunta dentro del intento.
  final int slot;

  /// AST del enunciado (contenido de `.qtext` en Moodle).
  final List<QuizBlock> questionText;

  /// AST de cada opción de respuesta.
  final List<AnswerOptionBlocks> options;

  /// AST de la respuesta correcta (modo revisión). `null` si no aplica.
  final List<QuizBlock>? rightAnswer;

  /// AST del feedback específico de la pregunta (modo revisión).
  final List<QuizBlock>? feedback;

  /// AST del feedback general (modo revisión).
  final List<QuizBlock>? generalFeedback;

  /// AST del feedback específico de la opción seleccionada (modo revisión).
  final List<QuizBlock>? specificFeedback;

  const QuestionBlocks({
    required this.slot,
    required this.questionText,
    required this.options,
    this.rightAnswer,
    this.feedback,
    this.generalFeedback,
    this.specificFeedback,
  });
}
