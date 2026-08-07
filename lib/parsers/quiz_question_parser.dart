import 'package:html/parser.dart' as htmlParser;
import 'package:html/dom.dart';
import '../models/quiz_question.dart';
import '../models/answer_option.dart';
import '../core/utils/app_logger.dart';

QuizQuestion parseQuizQuestion(Map<String, dynamic> json) {
  final slot = json['slot'] as int;
  final page = json['page'] as int? ?? 0;
  final rawHtml = json['html'] as String? ?? '';

  // ==========================================
  // 🔹 1) ENUNCIADO
  // ==========================================
  String questionText = '';
  if (json['questiontext'] is Map && json['questiontext']['text'] is String) {
    questionText = (json['questiontext']['text'] as String).trim();
  }

  final DocumentFragment document = htmlParser.parseFragment(rawHtml);
  if (questionText.isEmpty) {
    final qtextElem = document.querySelector('.qtext');
    questionText = qtextElem?.innerHtml.trim() ?? '';
  }

  // ==========================================
  // 🔹 2) OPCIONES
  // ==========================================
  final inputs = document.querySelectorAll('input[type="radio"]');
  final options = <AnswerOption>[];

  for (final input in inputs) {
    final value = input.attributes['value'] ?? '';
    final isSelected = input.attributes.containsKey('checked');
    Element? labelElem;

    // aria-labelledby
    final ariaId = input.attributes['aria-labelledby'];
    if (ariaId != null && ariaId.isNotEmpty) {
      labelElem = document.querySelector('[id="$ariaId"]');
    }

    // label[for=id]
    if (labelElem == null && input.id.isNotEmpty) {
      labelElem = document.querySelector('label[for="${input.id}"]');
    }

    // div con id="id_label"
    if (labelElem == null && input.id.isNotEmpty) {
      labelElem = document.querySelector('[id="${input.id}_label"]');
    }

    // fallback Moodle
    if (labelElem == null) {
      final flex = input.parent?.querySelector('.flex-fill');
      if (flex != null) {
        labelElem = flex;
      }
    }

    final labelHtml = labelElem?.innerHtml.trim() ?? '';
    if (labelHtml.isNotEmpty) {
      options.add(AnswerOption(
        value: value,
        labelHtml: labelHtml,
        isSelected: isSelected,
      ));
    }
  }

  // ==========================================
  // 🔹 3) NAME ANSWER
  // ==========================================
  final nameAnswer = inputs.isNotEmpty ? inputs.first.attributes['name']! : '';

  // ==========================================
  // 🔹 4) SEQUENCE / FLAGGED
  // ==========================================
  final sequenceInput = document.querySelector('input[name*="sequencecheck"]');
  final flaggedInput = document.querySelector('input[name*="flagged"][type="hidden"]');

  final sequenceCheckName = sequenceInput?.attributes['name'] ?? '';
  final flaggedName = flaggedInput?.attributes['name'] ?? '';
  final sequenceCheckValue =
      int.tryParse(sequenceInput?.attributes['value'] ?? '1') ?? 1;
  final flagged = flaggedInput?.attributes['value'] == '1';

  // ==========================================
  // 🔥 5) TAGS (NUEVO - ROBUSTO)
  // ==========================================
  List<String> tags = [];

  try {
    if (json.containsKey('tags') && json['tags'] != null) {
      final rawTags = json['tags'];

      if (rawTags is List) {
        tags = rawTags.map((e) {
          // Caso 1: {name: "geometría"}
          if (e is Map && e.containsKey('name')) {
            return e['name'].toString();
          }
          // Caso 2: string directo
          return e.toString();
        }).toList();
      }

      // Caso 3: string tipo "tag1,tag2"
      else if (rawTags is String) {
        tags = rawTags
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }
  } catch (e) {
    // Evitar que falle el parseo por tags
    AppLogger.e('[TAGS ERROR] slot $slot', e);
  }

  // 🔍 DEBUG (puedes quitar luego)
  AppLogger.d('[TAGS] Pregunta $slot: $tags');

  // ==========================================
  // 🔹 RETURN
  // ==========================================
  return QuizQuestion(
    slot: slot,
    page: page,
    html: rawHtml,
    questionText: questionText,
    nameAnswer: nameAnswer,
    options: options,
    sequenceCheckName: sequenceCheckName,
    flaggedName: flaggedName,
    sequenceCheckValue: sequenceCheckValue,
    flagged: flagged,

    // 🔥 NUEVO
    tags: tags,
  );
}