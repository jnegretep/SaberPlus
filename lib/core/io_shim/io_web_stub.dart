// lib/core/io_shim/io_web_stub.dart
// Saber+ v1.6.0 — Stubs de dart:io para compilación en Flutter Web.
//
// ⚠️ NUNCA usar directamente — solo a través de io_shim.dart.
//
// En web estas clases existen solo para satisfacer el compilador.
// Todos los métodos son no-op o devuelven valores vacíos/falsos.
// Los flujos reales de web NO dependen de estas clases (están
// protegidos con kIsWeb en los servicios correspondientes).

import 'dart:async';

/// Stub de [dart:io.File] — ver io_shim.dart.
class File {
  final String path;
  File(this.path);

  bool existsSync() => false;
  Future<bool> exists() async => false;

  /// En web devuelve vacío: la subida de imágenes desde galería
  /// no está soportada en web v1 (usar avatares predefinidos).
  Future<List<int>> readAsBytes() async => <int>[];

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
