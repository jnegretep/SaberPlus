// lib/widgets/web_max_width.dart
// Saber+ — Utilidad responsive para pantallas anchas (web/escritorio/tablet).
//
// Centra el contenido y lo limita a un ancho máximo legible, evitando que
// preguntas y tarjetas se estiren a lo ancho en monitores de PC.
// En móvil (≤700px) no altera nada — el contenido fluye a ancho completo.

import 'package:flutter/material.dart';

class WebMaxWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final bool center;

  const WebMaxWidth({
    Key? key,
    required this.child,
    this.maxWidth = 820,
    this.center = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width <= maxWidth + 32) return child;

    return center
        ? Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          )
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          );
  }
}
