class AnswerOption {
  final String value;     // Ej: "0", "1", "2", "3"
  final String labelHtml; // HTML del texto de la opción
  final bool isSelected;

  AnswerOption({
    required this.value,
    required this.labelHtml,
    required this.isSelected,
  });
}
