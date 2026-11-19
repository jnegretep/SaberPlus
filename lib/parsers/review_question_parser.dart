// lib/parsers/review_question_parser.dart
// SaberPlus — Parser DOM del HTML de revisión de Moodle.
//
// Reemplaza la extracción por regex que hacía ReviewScreen, vulnerable al
// HTML anidado: cortaba el feedback en el primer `</div>` interno, perdía
// generalfeedback/specificfeedback/rightanswer, borraba las opciones al
// eliminar div.answer/div.ablock y solo reconocía estados de multichoice.
//
// Fuente de datos: `mod_quiz_get_attempt_review` → questions[].html con
// estructura:
//   div.que.{qtype}.{behaviour}.{state}
//     > div.info        (h3.no, div.state, div.grade)
//     > div.content
//         > div.formulation (div.qtext + div.ablock > div.answer)
//         > div.outcome    (div.feedback, div.specificfeedback,
//                           div.generalfeedback, div.rightanswer)
//
// Todo el análisis usa el árbol DOM (package:html), nunca regex para
// contenido estructurado.

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as htmlParser;

/// Estados normalizados de una pregunta revisada.
class ReviewQuestionState {
  ReviewQuestionState._();

  static const String correct = 'correct';
  static const String incorrect = 'incorrect';
  static const String partially = 'partially';
  static const String unanswered = 'unanswered';
}

/// Una opción de respuesta tal como quedó en el intento revisado.
class ReviewOption {
  /// innerHtml del label de la opción (ya sin numeración "a." ni inputs).
  final String labelHtml;

  /// true si el input aparecía marcado (fue la respuesta del usuario).
  final bool isUserSelected;

  /// true si la opción es la correcta (o una de las correctas).
  final bool isCorrect;

  const ReviewOption({
    required this.labelHtml,
    required this.isUserSelected,
    required this.isCorrect,
  });
}

/// Datos listos para renderizar de una pregunta de revisión.
class ReviewQuestionData {
  final int slot;
  final int page;

  /// Uno de [ReviewQuestionState].
  final String state;

  /// Enunciado limpio (.qtext; ver _extractQuestionHtml para los fallbacks).
  final String questionHtml;

  final List<ReviewOption> options;
  final bool hasOptions;

  /// div.rightanswer (vacío si el behaviour no revela la respuesta).
  final String rightAnswerHtml;

  /// div.specificfeedback (feedback específico de la respuesta dada).
  final String specificFeedbackHtml;

  /// div.generalfeedback (feedback general de la pregunta).
  final String generalFeedbackHtml;

  /// div.feedback (el feedback clásico de estado: "Tu respuesta es correcta").
  final String feedbackHtml;

  /// div.grade (ej. "Se puntúa 1,00/1,00").
  final String gradeHtml;

  ReviewQuestionData({
    required this.slot,
    required this.page,
    required this.state,
    required this.questionHtml,
    required this.options,
    required this.rightAnswerHtml,
    required this.specificFeedbackHtml,
    required this.generalFeedbackHtml,
    required this.feedbackHtml,
    required this.gradeHtml,
  }) : hasOptions = options.isNotEmpty;

  /// true si hay algún bloque de retroalimentación con contenido.
  bool get hasAnyFeedback =>
      specificFeedbackHtml.trim().isNotEmpty ||
      feedbackHtml.trim().isNotEmpty ||
      generalFeedbackHtml.trim().isNotEmpty;
}

/// Parsea el map `question` de `mod_quiz_get_attempt_review`.
///
/// Nunca lanza: ante HTML inesperado devuelve valores por defecto
/// (estado "unanswered" y strings vacíos).
ReviewQuestionData parseReviewQuestion(Map<String, dynamic> q) {
  // Extracción defensiva: la API siempre envía int/String, pero ante un
  // payload inesperado se degradan los valores en vez de lanzar.
  final rawSlot = q['slot'];
  final rawPage = q['page'];
  final rawHtml = q['html'];
  final slot = rawSlot is num ? rawSlot.toInt() : 0;
  final page = rawPage is num ? rawPage.toInt() : 0;
  final html = rawHtml is String ? rawHtml : '';

  final fragment = htmlParser.parseFragment(html);

  // ── 1) Estado (clases de div.que como tokens; tolerante a qtypes) ──
  final state = _extractState(fragment);

  // ── 2) Opciones (inputs radio/checkbox + labels, en orden de aparición) ──
  // rightanswer se necesita aquí para el fallback de corrección por texto.
  final rightAnswerHtml = _sectionInnerHtml(fragment, 'outcome', 'rightanswer');
  final options = _extractOptions(fragment, rightAnswerHtml, state);

  // ── 3) Retroalimentaciones y calificación ──
  final specificFeedbackHtml =
      _sectionInnerHtml(fragment, 'outcome', 'specificfeedback');
  final generalFeedbackHtml =
      _sectionInnerHtml(fragment, 'outcome', 'generalfeedback');
  final feedbackHtml = _sectionInnerHtml(fragment, 'outcome', 'feedback');
  final gradeHtml = _sectionInnerHtml(fragment, 'info', 'grade');

  // ── 4) Enunciado (al final: el último fallback muta el DOM) ──
  final questionHtml = _extractQuestionHtml(fragment);

  return ReviewQuestionData(
    slot: slot,
    page: page,
    state: state,
    questionHtml: questionHtml,
    options: options,
    rightAnswerHtml: rightAnswerHtml,
    specificFeedbackHtml: specificFeedbackHtml,
    generalFeedbackHtml: generalFeedbackHtml,
    feedbackHtml: feedbackHtml,
    gradeHtml: gradeHtml,
  );
}

// ═══════════════════════════════════════════════════════════════════
// Estado
// ═══════════════════════════════════════════════════════════════════

/// Lee el estado de la pregunta:
///  a) clases del `div.que` como tokens exactos (correct / incorrect /
///     partiallycorrect / notanswered, más alias de otros behaviours);
///  b) fallback: texto del `div.state` ("Correcta", "Incorrecta", ...).
String _extractState(dom.DocumentFragment fragment) {
  final que = fragment.querySelector('div.que');
  if (que != null) {
    final tokens = _classTokens(que);
    if (tokens.contains('correct') || tokens.contains('gradedright')) {
      return ReviewQuestionState.correct;
    }
    if (tokens.contains('incorrect') || tokens.contains('gradedwrong')) {
      return ReviewQuestionState.incorrect;
    }
    if (tokens.contains('partiallycorrect') ||
        tokens.contains('partially') ||
        tokens.contains('gradedpartial')) {
      return ReviewQuestionState.partially;
    }
    if (tokens.contains('notanswered') ||
        tokens.contains('invalidanswer') ||
        tokens.contains('needsgrading')) {
      return ReviewQuestionState.unanswered;
    }
  }

  // Fallback textual: ojo con el orden, "Incorrecta" contiene "correcta"
  // y "Parcialmente correcta" contiene ambas.
  final stateText =
      fragment.querySelector('div.state')?.text.toLowerCase() ?? '';
  if (stateText.contains('parcial')) return ReviewQuestionState.partially;
  if (stateText.contains('incorrect')) return ReviewQuestionState.incorrect;
  if (stateText.contains('correct')) return ReviewQuestionState.correct;
  return ReviewQuestionState.unanswered;
}

// ═══════════════════════════════════════════════════════════════════
// Opciones
// ═══════════════════════════════════════════════════════════════════

/// Versión mutable interna mientras se deduce la corrección de cada opción.
class _MutableOption {
  final String labelHtml;
  final bool isUserSelected;
  bool isCorrect;

  _MutableOption({
    required this.labelHtml,
    required this.isUserSelected,
    this.isCorrect = false,
  });
}

List<ReviewOption> _extractOptions(
  dom.DocumentFragment fragment,
  String rightAnswerHtml,
  String state,
) {
  // Radios (single choice) y checkboxes (multi answer) en orden del documento.
  // ✅ FIX (v1.7.2): excluir el checkbox "Marcar pregunta" (flag question)
  // de Moodle, que también es type="checkbox" pero NO es una opción de
  // respuesta. Antes se colaba como opción A y desplazaba a las reales.
  final inputs = fragment.querySelectorAll('input').where((el) {
    final type = (el.attributes['type'] ?? '').toLowerCase();
    if (type != 'radio' && type != 'checkbox') return false;

    // (1) Descartar por nombre/id: Moodle usa sufijos `flagged`, `flagged`
    //     en el atributo name y `q<attempt>:<slot>_:flagged` en el id.
    final name = (el.attributes['name'] ?? '').toLowerCase();
    final id = (el.attributes['id'] ?? '').toLowerCase();
    if (name.contains('flagged') ||
        id.contains('flagged') ||
        name.contains('flagquestion') ||
        id.contains('flagquestion')) {
      return false;
    }

    // (2) Descartar si está dentro de un contenedor de flag de Moodle:
    //     .questionflag, .im-controls, .flagquestion, .questionflagsaveform,
    //     .submitbtns. Recorremos como mucho 8 niveles hacia arriba.
    dom.Element? ancestor = el.parent;
    var depth = 0;
    while (ancestor != null && depth < 8) {
      final classes = _classTokens(ancestor);
      if (classes.contains('questionflag') ||
          classes.contains('flagquestion') ||
          classes.contains('im-controls') ||
          classes.contains('questionflagsaveform') ||
          classes.contains('submitbtns')) {
        return false;
      }
      // Parar al llegar al bloque de respuestas o al contenedor `que`.
      if (classes.contains('answer') || classes.contains('que')) break;
      ancestor = ancestor.parent;
      depth++;
    }

    return true;
  }).toList();

  if (inputs.isEmpty) return const [];

  // Texto plano de la respuesta correcta (para el fallback b).
  final rightText = _normalizeHtmlText(rightAnswerHtml);

  final parsed = <_MutableOption>[];
  for (final input in inputs) {
    final isSelected = input.attributes.containsKey('checked');

    // (a) La fila contenedora (ancestro del input hasta div.answer/div.que)
    //     lleva clase 'correct' → es la respuesta correcta. La clase
    //     'incorrect' solo la lleva la fila seleccionada errónea → false
    //     (ya es el valor por defecto).
    //     OJO: se lee ANTES de extraer el label porque en la estructura
    //     legacy (<label><input> texto</label>) la extracción saca el
    //     input del árbol y perderíamos su ancestro.
    final rowIsCorrect = _ancestorRowHasClass(input, 'correct');

    final labelHtml = _extractLabelHtml(fragment, input);
    if (labelHtml.isEmpty) continue;

    parsed.add(_MutableOption(
      labelHtml: labelHtml,
      isUserSelected: isSelected,
      isCorrect: rowIsCorrect,
    ));
  }

  if (parsed.isEmpty) return const [];

  // (b) Sin marcas de fila: comparar el texto del label con el texto de
  //     div.rightanswer (contención, case-insensitive, sin tags/&nbsp;).
  if (!parsed.any((o) => o.isCorrect) && rightText.isNotEmpty) {
    for (final option in parsed) {
      final label = _normalizeHtmlText(option.labelHtml);
      // Longitud mínima para evitar falsos positivos con letras sueltas.
      if (label.length >= 2 && rightText.contains(label)) {
        option.isCorrect = true;
      }
    }
  }

  // (c) Último recurso: si el estado global es "correcto", las opciones
  //     seleccionadas son correctas (en single-choice es exactamente una;
  //     en multi-choice correcto el conjunto marcado coincide con el
  //     correcto, así que todas las seleccionadas valen).
  if (!parsed.any((o) => o.isCorrect) && state == ReviewQuestionState.correct) {
    for (final option in parsed) {
      if (option.isUserSelected) option.isCorrect = true;
    }
  }

  return parsed
      .map((o) => ReviewOption(
            labelHtml: o.labelHtml,
            isUserSelected: o.isUserSelected,
            isCorrect: o.isCorrect,
          ))
      .toList(growable: false);
}

/// Misma estrategia de extracción de labels que quiz_question_parser.dart:
/// aria-labelledby → label[for=id] → [id="id_label"] → .flex-fill.
String _extractLabelHtml(dom.DocumentFragment fragment, dom.Element input) {
  dom.Element? labelElem;

  // 1) aria-labelledby
  final ariaId = input.attributes['aria-labelledby'];
  if (ariaId != null && ariaId.isNotEmpty) {
    labelElem = fragment.querySelector('[id="$ariaId"]');
  }

  // 2) label[for=id]
  final inputId = input.id;
  if (labelElem == null && inputId.isNotEmpty) {
    labelElem = fragment.querySelector('label[for="$inputId"]');
  }

  // 3) elemento con id="id_label"
  if (labelElem == null && inputId.isNotEmpty) {
    labelElem = fragment.querySelector('[id="${inputId}_label"]');
  }

  // 4) fallback Moodle: .flex-fill en el contenedor inmediato
  labelElem ??= input.parent?.querySelector('.flex-fill');

  // 5) estructura legacy: el propio padre es un <label> con el input dentro
  if (labelElem == null) {
    final parent = input.parent;
    if (parent != null && parent.localName?.toLowerCase() == 'label') {
      labelElem = parent;
    }
  }

  if (labelElem == null) return '';

  // Limpiar dentro del label: numeración "a." y el propio input si va anidado.
  for (final el in labelElem.querySelectorAll('.answernumber')) {
    el.remove();
  }
  for (final el in labelElem.querySelectorAll('input')) {
    el.remove();
  }
  return labelElem.innerHtml.trim();
}

/// true si algún ancestro del input (la "fila" de la opción, sin salir del
/// bloque de respuestas) lleva la clase [cls].
bool _ancestorRowHasClass(dom.Element input, String cls) {
  dom.Element? node = input.parent;
  var depth = 0;
  while (node != null && depth < 8) {
    final classes = _classTokens(node);
    // No subir más allá de la fila: div.answer / div.que delimitan.
    if (classes.contains('answer') || classes.contains('que')) return false;
    if (classes.contains(cls)) return true;
    node = node.parent;
    depth++;
  }
  return false;
}

// ═══════════════════════════════════════════════════════════════════
// Enunciado
// ═══════════════════════════════════════════════════════════════════

/// Enunciado limpio por cascada:
///  1) `.qtext` (el enunciado canónico);
///  2) `.formulation` sin `.ablock` (por si no hay .qtext);
///  3) el html original sin `.info`/`.outcome` (último recurso).
/// Se llama después de extraer opciones porque los fallbacks mutan el DOM.
String _extractQuestionHtml(dom.DocumentFragment fragment) {
  final qtext = fragment.querySelector('.qtext');
  if (qtext != null) {
    final html = _cleanElementInnerHtml(qtext);
    if (html.isNotEmpty) return html;
  }

  final formulation = fragment.querySelector('.formulation');
  if (formulation != null) {
    // Las opciones ya se extrajeron: quitar el bloque de respuestas.
    for (final ablock in formulation.querySelectorAll('.ablock')) {
      ablock.remove();
    }
    final html = _cleanElementInnerHtml(formulation);
    if (html.isNotEmpty) return html;
  }

  for (final el in fragment.querySelectorAll('.info')) {
    el.remove();
  }
  for (final el in fragment.querySelectorAll('.outcome')) {
    el.remove();
  }
  for (final el in fragment.querySelectorAll('input')) {
    el.remove();
  }
  _stripComments(fragment);

  // FIX: DocumentFragment no tiene `innerHtml` (solo los Element) y Node
  // tampoco tiene `outerHtml`. Solución: mover los nodos restantes a un
  // <div> wrapper temporal y leer su innerHtml (serializa todos los tipos
  // de nodo: Element, Text, Comment, etc. automáticamente).
  final wrapper = dom.Element.tag('div');
  wrapper.nodes.addAll(fragment.nodes.toList());
  return wrapper.innerHtml.trim();
}

/// innerHtml del elemento sin comentarios HTML, `<input>` ni la
/// numeración `.answernumber` de Moodle.
String _cleanElementInnerHtml(dom.Element element) {
  for (final el in element.querySelectorAll('input')) {
    el.remove();
  }
  for (final el in element.querySelectorAll('.answernumber')) {
    el.remove();
  }
  _stripComments(element);
  return element.innerHtml.trim();
}

void _stripComments(dom.Node node) {
  for (final child in node.nodes.toList()) {
    if (child is dom.Comment) {
      child.remove();
    } else {
      _stripComments(child);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
// Secciones (feedback, grade, rightanswer...)
// ═══════════════════════════════════════════════════════════════════

/// innerHtml del `div.{targetClass}` buscando primero entre los hijos
/// directos de `div.{containerClass}` (evita confundir, p.ej., un
/// div.feedback anidado en una fila de respuesta con el del outcome);
/// si no, primer `div.{targetClass}` del documento. Vacío si no existe.
String _sectionInnerHtml(
  dom.DocumentFragment fragment,
  String containerClass,
  String targetClass,
) {
  final container = fragment.querySelector('div.$containerClass');
  if (container != null) {
    for (final child in container.children) {
      if (_hasClass(child, targetClass)) return child.innerHtml.trim();
    }
  }
  return fragment.querySelector('div.$targetClass')?.innerHtml.trim() ?? '';
}

// ═══════════════════════════════════════════════════════════════════
// Utilidades DOM
// ═══════════════════════════════════════════════════════════════════

/// Clases del elemento como tokens exactos (split por espacios).
List<String> _classTokens(dom.Element element) {
  final cls = element.attributes['class']?.trim() ?? '';
  if (cls.isEmpty) return const [];
  return cls.split(RegExp(r'\s+'));
}

bool _hasClass(dom.Element element, String cls) =>
    _classTokens(element).contains(cls);

/// Texto plano normalizado de un fragmento HTML: sin tags, &nbsp; → espacio,
/// espacios colapsados, en minúsculas. Para comparaciones de contenido.
String _normalizeHtmlText(String htmlText) {
  if (htmlText.isEmpty) return '';
  // FIX: DocumentFragment.text es String? en package:html 0.15.6 → `?? ''`.
  final text = htmlParser.parseFragment(htmlText).text ?? '';
  return text
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
}