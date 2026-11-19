import 'answer_option.dart';

class QuizQuestion {
  final int slot;
  final int page;
  final String html;
  final String questionText;
  final String nameAnswer;
  final List<AnswerOption> options;
  final String sequenceCheckName;
  final String flaggedName;
  final int sequenceCheckValue;
  final bool flagged;

  // 🔹 NUEVO
  final List<String> tags;

  QuizQuestion({
    required this.slot,
    required this.page,
    required this.html,
    required this.questionText,
    required this.nameAnswer,
    required this.options,
    required this.sequenceCheckName,
    required this.flaggedName,
    required this.sequenceCheckValue,
    required this.flagged,

    // 🔹 NUEVO (default vacío para no romper nada)
    this.tags = const [],
  });
}