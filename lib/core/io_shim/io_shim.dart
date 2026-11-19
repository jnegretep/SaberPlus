// lib/core/io_shim/io_shim.dart
// Saber+ v1.6.0 — Shim condicional de dart:io para Flutter Web.
//
// USO: reemplaza `import 'dart:io';` por:
//   import '../core/io_shim/io_shim.dart';   // (ajustar ruta relativa)
//
// - En móvil/escritorio: exporta dart:io real (comportamiento normal).
// - En web: exporta stubs que compilan pero no hacen nada.
//
// Los flujos que SÍ deben funcionar en web están protegidos con kIsWeb
// en sus respectivos servicios (descargas, caché de PDFs/videos).

export 'dart:io' if (dart.library.html) 'io_web_stub.dart';
