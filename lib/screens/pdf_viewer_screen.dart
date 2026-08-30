// lib/screens/pdf_viewer_screen.dart
// Saber+ — Pantalla wrapper para el visor de PDF premium
//
// Mantiene compatibilidad con el código existente que usa PdfViewerScreen,
// pero delega al widget PremiumPdfViewer con todas las mejoras:
// - Descarga offline
// - Progreso de lectura
// - Recordar última página
// - Modo pantalla completa

import 'package:flutter/material.dart';
import '../widgets/pdf/premium_pdf_viewer.dart';

class PdfViewerScreen extends StatelessWidget {
  final String url;
  final String title;

  const PdfViewerScreen({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return PremiumPdfViewer(
      url: url,
      title: title,
    );
  }
}
