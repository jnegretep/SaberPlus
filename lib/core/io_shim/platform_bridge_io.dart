// lib/core/io_shim/platform_bridge_io.dart
// Saber+ v1.6.1 — Implementación MÓVIL/ESCRITORIO del puente de plataforma.
//
// ⚠️ NUNCA importar directamente — solo a través de platform_bridge.dart.
//    Este archivo SOLO se compila cuando el target NO es web (usa dart:io
//    real). En web lo sustituye platform_bridge_web.dart vía import
//    condicional, por lo que ninguna de estas líneas llega al bundle JS.
//
// Comportamiento: idéntico al código original anterior a v1.6.0
// (Image.file / FileImage / VideoPlayerController.file nativos).

import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

/// Crea un [File] real a partir del [XFile] que devuelve image_picker.
///
/// En móvil/escritorio el XFile siempre tiene un path de filesystem válido,
/// por lo que esto equivale al `File(pickedFile.path)` original.
File fileFromXFile(XFile xfile) => File(xfile.path);

/// Proveedor de imagen para archivos seleccionados con image_picker.
///
/// Equivale al `FileImage(file)` original — sin cambios de comportamiento
/// ni de caché en móvil/escritorio.
ImageProvider<Object> fileImageProvider(File file) => FileImage(file);

/// Controlador para reproducir un video descargado localmente.
///
/// Equivale al `VideoPlayerController.file(File(path))` original.
VideoPlayerController localVideoController(String path) =>
    VideoPlayerController.file(File(path));
