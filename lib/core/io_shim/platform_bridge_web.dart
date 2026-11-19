// lib/core/io_shim/platform_bridge_web.dart
// Saber+ v1.6.1 — Implementación WEB del puente de plataforma.
//
// ⚠️ NUNCA importar directamente — solo a través de platform_bridge.dart.
//
// Cómo funciona la selección de imágenes en web:
//   - image_picker abre el diálogo nativo del navegador (<input type=file>)
//     cuando la fuente es la galería.
//   - El XFile devuelto tiene como `path` un blob: URL que el navegador
//     puede renderizar → se muestra con NetworkImage (mismo mecanismo
//     documentado por image_picker para web).
//   - Los bytes reales se leen a través del XFile (el stub File de
//     io_web_stub.dart guarda la referencia y delega readAsBytes()), lo
//     que permite subir el avatar a base64 exactamente como en móvil.
//   - La cámara NO está soportada por image_picker en web (las pantallas
//     la ocultan con kIsWeb).

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'io_web_stub.dart';

/// Crea un [File] web a partir del [XFile] de image_picker.
///
/// Conserva la referencia al XFile para que [File.readAsBytes] pueda
/// leer los bytes reales del blob: URL (ver io_web_stub.dart).
File fileFromXFile(XFile xfile) => File.fromXFile(xfile);

/// Proveedor de imagen para archivos seleccionados en web.
///
/// En web el `path` del XFile es un blob: URL del propio origen (sin
/// problema de CORS), que NetworkImage renderiza correctamente.
ImageProvider<Object> fileImageProvider(File file) => NetworkImage(file.path);

/// La reproducción local de videos descargados no existe en web:
/// el botón de descarga está oculto (kIsWeb) en premium_video_player,
/// por lo que este método jamás debería invocarse. Si ocurriera, el
/// error se captura en _initializeVideo y se muestra el widget de error
/// con botón "Reintentar" (degradación controlada, nunca un crash).
VideoPlayerController localVideoController(String path) =>
    throw UnsupportedError(
      'La reproducción local de videos no está disponible en la versión web. '
      'Reproduce el video en streaming.',
    );
