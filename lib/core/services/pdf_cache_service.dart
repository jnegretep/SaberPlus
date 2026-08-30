// lib/core/services/pdf_cache_service.dart
// Saber+ — Servicio de descarga y cache de PDFs offline
//
// Similar a VideoDownloadService pero para PDFs.
// Los PDFs se guardan en el directorio de la app (persistentes).
// Se mantiene un registro en SharedPreferences.

import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

/// Información de un PDF descargado.
class PdfDownloadInfo {
  final String url;
  final String localPath;
  final int totalPages;
  final int lastPageRead;
  final DateTime downloadedAt;
  final int fileSize;

  PdfDownloadInfo({
    required this.url,
    required this.localPath,
    this.totalPages = 0,
    this.lastPageRead = 0,
    required this.downloadedAt,
    this.fileSize = 0,
  });

  bool get isDownloaded => File(localPath).existsSync();

  PdfDownloadInfo copyWith({
    String? localPath,
    int? totalPages,
    int? lastPageRead,
    int? fileSize,
  }) {
    return PdfDownloadInfo(
      url: url,
      localPath: localPath ?? this.localPath,
      totalPages: totalPages ?? this.totalPages,
      lastPageRead: lastPageRead ?? this.lastPageRead,
      downloadedAt: downloadedAt,
      fileSize: fileSize ?? this.fileSize,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'localPath': localPath,
        'totalPages': totalPages,
        'lastPageRead': lastPageRead,
        'downloadedAt': downloadedAt.toIso8601String(),
        'fileSize': fileSize,
      };

  factory PdfDownloadInfo.fromJson(Map<String, dynamic> json) {
    return PdfDownloadInfo(
      url: json['url'] as String,
      localPath: json['localPath'] as String,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      lastPageRead: (json['lastPageRead'] as num?)?.toInt() ?? 0,
      downloadedAt: DateTime.tryParse(json['downloadedAt'] as String? ?? '') ??
          DateTime.now(),
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
    );
  }
}

class PdfCacheService {
  static SharedPreferences? _prefs;
  static final Map<String, PdfDownloadInfo> _cache = {};

  /// Inicializar (llamar en main.dart)
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadFromPrefs();
    AppLogger.d('PdfCacheService inicializado (${_cache.length} PDFs)');
  }

  static Future<void> _loadFromPrefs() async {
    final raw = _prefs!.getString('pdf_downloads');
    if (raw == null) return;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _cache.clear();
      map.forEach((key, value) {
        _cache[key] = PdfDownloadInfo.fromJson(value as Map<String, dynamic>);
      });
    } catch (e) {
      AppLogger.e('PdfCacheService: error cargando cache', e);
    }
  }

  static Future<void> _saveToPrefs() async {
    try {
      final map = _cache.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs!.setString('pdf_downloads', jsonEncode(map));
    } catch (e) {
      AppLogger.e('PdfCacheService: error guardando cache', e);
    }
  }

  /// Verifica si un PDF ya está descargado y el archivo existe.
  static bool isDownloaded(String url) {
    final info = _cache[url];
    if (info == null) return false;
    return info.isDownloaded;
  }

  /// Obtiene la información de un PDF descargado.
  static PdfDownloadInfo? getInfo(String url) {
    return _cache[url];
  }

  /// Obtiene la ruta local de un PDF descargado (null si no existe).
  static String? getLocalPath(String url) {
    final info = _cache[url];
    if (info == null || !info.isDownloaded) return null;
    return info.localPath;
  }

  /// Descarga un PDF y lo guarda en el directorio de la app.
  ///
  /// [onProgress] se llama con el progreso (0-100) durante la descarga.
  /// Retorna la ruta local del archivo descargado, o null si falla.
  static Future<String?> download(
    String url, {
    void Function(int progress)? onProgress,
  }) async {
    // Si ya está descargado, devolver la ruta existente
    if (isDownloaded(url)) {
      AppLogger.d('PdfCacheService: $url ya está descargado');
      return getLocalPath(url);
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final pdfsDir = Directory('${dir.path}/pdfs');
      if (!await pdfsDir.exists()) {
        await pdfsDir.create(recursive: true);
      }

      final filename = 'pdf_${url.hashCode}.pdf';
      final savePath = '${pdfsDir.path}/$filename';

      // Descargar con HttpClient para soporte de progreso
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        AppLogger.e('PdfCacheService: HTTP ${response.statusCode} descargando $url', null);
        return null;
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;
      final file = File(savePath);
      final sink = file.openWrite();

      await for (final chunk in response) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final progress = (receivedBytes / totalBytes * 100).round();
          onProgress?.call(progress);
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      // Guardar info en cache
      final fileSize = await file.length();
      _cache[url] = PdfDownloadInfo(
        url: url,
        localPath: savePath,
        downloadedAt: DateTime.now(),
        fileSize: fileSize,
      );
      await _saveToPrefs();

      AppLogger.i('PdfCacheService: PDF descargado $url → $savePath (${_formatSize(fileSize)})');
      return savePath;
    } catch (e) {
      AppLogger.e('PdfCacheService: error descargando $url', e);
      return null;
    }
  }

  /// Elimina un PDF descargado para liberar espacio.
  static Future<void> delete(String url) async {
    final info = _cache[url];
    if (info == null) return;

    // Eliminar archivo físico
    try {
      final file = File(info.localPath);
      if (await file.exists()) {
        await file.delete();
        AppLogger.d('PdfCacheService: archivo eliminado ${info.localPath}');
      }
    } catch (e) {
      AppLogger.e('PdfCacheService: error eliminando archivo', e);
    }

    _cache.remove(url);
    await _saveToPrefs();
    AppLogger.i('PdfCacheService: PDF eliminado para $url');
  }

  /// Actualiza la última página leída de un PDF.
  static Future<void> updateLastPageRead(String url, int page) async {
    final info = _cache[url];
    if (info == null) return;

    _cache[url] = info.copyWith(lastPageRead: page);
    await _saveToPrefs();
  }

  /// Actualiza el total de páginas de un PDF.
  static Future<void> updateTotalPages(String url, int totalPages) async {
    final info = _cache[url];
    if (info == null) return;

    _cache[url] = info.copyWith(totalPages: totalPages);
    await _saveToPrefs();
  }

  /// Obtiene el tamaño total de los PDFs descargados.
  static Future<int> getTotalDownloadedSize() async {
    int total = 0;
    for (final info in _cache.values) {
      if (info.isDownloaded) {
        total += info.fileSize;
      }
    }
    return total;
  }

  /// Formatea un tamaño en bytes a cadena legible.
  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
