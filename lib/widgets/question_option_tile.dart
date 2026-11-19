// lib/widgets/question_option_tile.dart
// SaberPlus — Tile reutilizable para mostrar una opción de respuesta en
// modo lectura (revisión de intentos).
//
// Estados visuales (consistente con el design system de la app):
//  - Correcta (marcada o no)      → borde/fondo verde + check.
//  - Seleccionada e incorrecta    → borde/fondo rojo + close.
//  - No seleccionada y sin marca  → neutra (border).

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'rich/moodle_rich_text.dart';

class QuestionOptionTile extends StatelessWidget {
  /// Letra de la opción ('A', 'B', 'C', ...).
  final String letter;

  /// HTML del contenido de la opción (label de Moodle).
  final String labelHtml;

  /// true si el usuario la marcó en su intento.
  final bool isUserSelected;

  /// true si es la respuesta correcta (o una de ellas).
  final bool isCorrect;

  /// En modo lectura (revisión) el tile muestra los iconos de estado y no
  /// es interactivo; con false muestra el círculo de selección (look de
  /// question_screen) para reutilizarlo en flujos interactivos.
  final bool isReadOnly;

  const QuestionOptionTile({
    Key? key,
    required this.letter,
    required this.labelHtml,
    this.isUserSelected = false,
    this.isCorrect = false,
    this.isReadOnly = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Paleta según estado de la opción.
    final Color borderColor;
    final Color fillColor;
    if (isCorrect) {
      borderColor = AppColors.successDark;
      fillColor = AppColors.successLight;
    } else if (isUserSelected) {
      borderColor = AppColors.error;
      fillColor = AppColors.errorLight;
    } else {
      borderColor = AppColors.border;
      fillColor = AppColors.surface;
    }

    final bool highlighted = isCorrect || isUserSelected;

    // Caja de la letra: verde si es correcta, roja si fue la elegida
    // errónea, neutra en el resto.
    final Color letterBg = isCorrect
        ? AppColors.successDark
        : isUserSelected
            ? AppColors.error
            : AppColors.surfaceVariant;
    final Color letterFg =
        highlighted ? AppColors.textOnPrimary : AppColors.textTertiary;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: letterBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: Text(
                letter,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: letterFg,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MoodleRichText(
              html: labelHtml,
              isOption: true,
              maxImageHeight: 150,
            ),
          ),
          const SizedBox(width: 12),
          _buildTrailing(),
        ],
      ),
    );
  }

  /// Iconografía a la derecha según modo y estado.
  Widget _buildTrailing() {
    if (isReadOnly) {
      if (isCorrect) {
        return const Icon(
          Icons.check_circle_rounded,
          size: 22,
          color: AppColors.successDark,
        );
      }
      if (isUserSelected) {
        return const Icon(
          Icons.cancel_rounded,
          size: 22,
          color: AppColors.error,
        );
      }
      return const SizedBox.shrink();
    }

    // Modo interactivo: círculo de selección estilo question_screen.
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isUserSelected ? AppColors.primary : AppColors.textSubtle,
          width: 1.5,
        ),
      ),
      child: isUserSelected
          ? Container(
              margin: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
              ),
            )
          : null,
    );
  }
}
