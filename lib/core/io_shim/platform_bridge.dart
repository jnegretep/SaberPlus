// lib/core/io_shim/platform_bridge.dart
// Saber+ v1.6.1 — Puente multiplataforma para APIs del framework que
// exigen el File REAL de dart:io (inexistente en Flutter Web).
//
// Problema que resuelve:
//   Image.file(), FileImage() y VideoPlayerController.file() del framework
//   reciben `dart:io File`. El shim (io_shim.dart) define otro tipo `File`
//   para compilar en web, y por eso dart2js rechazaba pasarlo a esas APIs.
//
// Solución:
//   Helpers con firma idéntica que se resuelven mediante import condicional:
//
//   - File fileFromXFile(XFile)     → construye un File desde el resultado
//                                     de image_picker (ambas plataformas).
//   - ImageProvider fileImageProvider(File) → mostrar una imagen local:
//                                     móvil → FileImage | web → NetworkImage
//                                     (en web el path es un blob: URL).
//   - VideoPlayerController localVideoController(String) → video descargado:
//                                     móvil → VideoPlayerController.file |
//                                     web → no soportado (descargas ocultas).
//
// USO:  import '../core/io_shim/platform_bridge.dart';
//
// ⚠️ Este archivo NUNCA se importa directamente en pantallas — solo su
//    export condicional. No agregar código aquí.

export 'platform_bridge_io.dart' if (dart.library.html) 'platform_bridge_web.dart';
