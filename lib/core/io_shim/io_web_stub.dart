// lib/core/io_shim/io_web_stub.dart
// Saber+ v1.6.0 — Stubs de dart:io para compilación en Flutter Web.
//
// ⚠️ NUNCA usar directamente — solo a través de io_shim.dart.
//
// En web estas clases existen solo para satisfacer el compilador.
// Los métodos que no tienen equivalente web son no-op o devuelven
// valores vacíos/falsos. Los flujos reales de web están protegidos
// con kIsWeb en los servicios correspondientes (descargas, FCM, etc.).
//
// EXCEPCIÓN v1.6.1 — lectura de imágenes seleccionadas: cuando el File
// se construye desde el XFile de image_picker (vía File.fromXFile o
// fileFromXFile del platform_bridge), readAsBytes() lee los bytes
// REALES del blob: URL, lo que permite mostrar y subir el avatar en
// web igual que en móvil.

import 'dart:async';

import 'package:cross_file/cross_file.dart' as xfile;

/// Stub de [dart:io.File] — ver io_shim.dart.
class File {
  final String path;

  /// Referencia al XFile real de image_picker (solo web).
  /// Permite leer los bytes del blob: URL cuando la app los necesite
  /// (subida de avatar en base64, etc.).
  final xfile.XFile? _picked;

  File(this.path, [xfile.XFile? picked]) : _picked = picked;

  /// Construye un File web a partir del XFile devuelto por image_picker.
  ///
  /// Usar preferiblemente `fileFromXFile()` de platform_bridge.dart,
  /// que funciona igual en móvil y en web.
  factory File.fromXFile(xfile.XFile picked) => File(picked.path, picked);

  bool existsSync() => _picked != null;

  Future<bool> exists() async => _picked != null;

  /// Lee los bytes reales del archivo cuando proviene de image_picker
  /// (en web, XFile.readAsBytes resuelve el blob: URL vía XHR).
  /// Si no hay origen legible (rutas sintéticas de otros servicios)
  /// devuelve una lista vacía, igual que en versiones anteriores.
  Future<List<int>> readAsBytes() async {
    final picked = _picked;
    if (picked == null) return const <int>[];
    try {
      return await picked.readAsBytes();
    } catch (_) {
      // blob: URL revocado o ilegible → degradar a vacío, nunca lanzar.
      return const <int>[];
    }
  }

  IOSink openWrite() => IOSink();

  void deleteSync() {}
  Future<void> delete() async {}

  int lengthSync() => 0;
  Future<int> length() async => 0;
}

/// Stub de [dart:io.Directory].
class Directory {
  final String path;
  Directory(this.path);

  void createSync({bool recursive = false}) {}
  Future<void> create({bool recursive = false}) async {}
  bool existsSync() => false;
  Future<bool> exists() async => false;
}

/// Stub mínimo de [dart:io.IOSink].
class IOSink {
  void add(List<int> data) {}
  Future<void> close() async {}
  Future<void> flush() async {}
}

/// Stub de [dart:io.HttpClient] — en web se usa Dio/http (JS) en su lugar.
class HttpClient {
  Future<HttpClientRequest> getUrl(Uri url) async {
    throw UnsupportedError('HttpClient no está disponible en web');
  }

  void close() {}
}

class HttpClientRequest {
  Future<HttpClientResponse> close() async {
    throw UnsupportedError('HttpClient no está disponible en web');
  }
}

/// Stub de [dart:io.HttpClientResponse] — es un Stream vacío.
class HttpClientResponse extends Stream<List<int>> {
  int get statusCode => 0;
  int get contentLength => 0;
  bool get isRedirect => false;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return const Stream<List<int>>.empty().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
