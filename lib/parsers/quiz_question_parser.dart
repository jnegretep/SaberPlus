import 'package:html/parser.dart' as htmlParser;
import 'package:html/dom.dart';
import '../models/quiz_question.dart';
import '../models/answer_option.dart';
// import '../core/utils/app_logger.dart'; // Quitamos el logger para no ralentizar

// ✅ NUEVO: Función top-level para ejecutar en un Isolate (compute)
// Recibe la lista cruda del JSON y devuelve la lista de objetos ya parseados.
List<QuizQuestion> parseQuestionsBatch(List<Map<String, dynamic>> rawQuestions) {
  final List<QuizQuestion> parsed = [];
  for (final json in rawQuestions) {
    try {
      parsed.add(_parseSingle(json));
    } catch (e) {
      // En un isolate no podemos loguear al UI fácilmente, así que ignoramos 
      // o imprimimos en consola de debug
      print('>>> Error parseando pregunta en isolate: $e');
    }
  }
  return parsed;
}

// Renombramos el método original a privado para que solo se use desde el batch
QuizQuestion _parseSingle(Map<String, dynamic> json) {
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

    final ariaId = input.attributes['aria-labelledby'];
    if (ariaId != null && ariaId.isNotEmpty) {
      labelElem = document.querySelector('[id="$ariaId"]');
    }

    if (labelElem == null && input.id.isNotEmpty) {
      labelElem = document.querySelector('label[for="${input.id}"]');
    }

    if (labelElem == null && input.id.isNotEmpty) {
      labelElem = document.querySelector('[id="${input.id}_label"]');
    }

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

  final nameAnswer = inputs.isNotEmpty ? inputs.first.attributes['name']! : '';

  final sequenceInput = document.querySelector('input[name*="sequencecheck"]');
  final flaggedInput = document.querySelector('input[name*="flagged"][type="hidden"]');

  final sequenceCheckName = sequenceInput?.attributes['name'] ?? '';
  final flaggedName = flaggedInput?.attributes['name'] ?? '';
  final sequenceCheckValue =
      int.tryParse(sequenceInput?.attributes['value'] ?? '1') ?? 1;
  final flagged = flaggedInput?.attributes['value'] == '1';

  // ==========================================
  // 🔥 5) TAGS
  // ==========================================
  List<String> tags = [];

  try {
    if (json.containsKey('tags') && json['tags'] != null) {
      final rawTags = json['tags'];
      if (rawTags is List) {
        tags = rawTags.map((e) {
          if (e is Map && e.containsKey('name')) {
            return e['name'].toString();
          }
          return e.toString();
        }).toList();
      } else if (rawTags is String) {
        tags = rawTags
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }
  } catch (e) {
    // Silencioso en isolate
  }

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
    tags: tags,
  );
}

// Mantenemos tu función original para no romper otras partes del código
// que la llamen directamente (ej. si hay un parseo único en algún lado)
QuizQuestion parseQuizQuestion(Map<String, dynamic> json) {
  return _parseSingle(json);
}