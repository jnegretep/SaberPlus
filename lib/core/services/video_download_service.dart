// lib/core/services/video_download_service.dart
// Saber+ — Servicio de descarga y cache de videos offline
//
// Permite descargar videos de cursos para verlos sin conexión.
// Usa flutter_downloader para descargas en background.
//
// Estrategia:
// - Los videos se guardan en el directorio de la app (Application Documents)
// - Se registra un callback de progreso para actualizar la UI
// - Se mantiene un registro de descargas en SharedPreferences
// - Al abrir un video, se verifica si ya está descargado

import 'dart:convert';
import 'dart:io';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';

/// Estado de una descarga de video.
enum DownloadStatus {
  notDownloaded,    // no se ha descargado
  downloading,      // en progreso
  completed,        // descargado y listo para ver offline
  failed,           // falló la descarga
  paused,           // pausada
}

/// Información de una descarga de video.
class VideoDownloadInfo {
  final String url;           // URL original del video
  final String? taskId;       // ID de la tarea de flutter_downloader
  final String? localPath;    // ruta local del archivo descargado
  final DownloadStatus status;
  final int progress;         // 0-100

  VideoDownloadInfo({
    required this.url,
    this.taskId,
    this.localPath,
    required this.status,
    this.progress = 0,
  });

  VideoDownloadInfo copyWith({
    String? taskId,
    String? localPath,
    DownloadStatus? status,
    int? progress,
  }) {
    return VideoDownloadInfo(
      url: url,
      taskId: taskId ?? this.taskId,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'taskId': taskId,
        'localPath': localPath,
        'status': status.name,
        'progress': progress,
      };

  factory VideoDownloadInfo.fromJson(Map<String, dynamic> json) {
    return VideoDownloadInfo(
      url: json['url'] as String,
      taskId: json['taskId'] as String?,
      localPath: json['localPath'] as String?,
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadStatus.notDownloaded,
      ),
      progress: (json['progress'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Servicio singleton para gestionar descargas de videos.
class VideoDownloadService {
  static SharedPreferences? _prefs;
  static final Map<String, VideoDownloadInfo> _downloads = {};
  static final Map<String, void Function(VideoDownloadInfo)> _callbacks = {};

  /// Callback global que flutter_downloader llama para reportar progreso.
  /// Debe estar registrado como @pragma('vm:entry-point').
  static void downloadCallback(
    String id,
    int status,
    int progress,
  ) {
    AppLogger.d('Download callback: id=$id, status=$status, progress=$progress');

    // Buscar la descarga por taskId
    String? urlKey;
    for (final entry in _downloads.entries) {
      if (entry.value.taskId == id) {
        urlKey = entry.key;
        break;
      }
    }

    if (urlKey == null) return;

    final info = _downloads[urlKey]!;
    DownloadStatus newStatus;
    switch (status) {
      case 2: // DownloadTaskStatus.complete
        newStatus = DownloadStatus.completed;
        break;
      case 3: // DownloadTaskStatus.failed
        newStatus = DownloadStatus.failed;
        break;
      case 6: // DownloadTaskStatus.paused
        newStatus = DownloadStatus.paused;
        break;
      default:
        newStatus = DownloadStatus.downloading;
    }

    final updated = info.copyWith(
      status: newStatus,
      progress: progress,
      localPath: newStatus == DownloadStatus.completed
          ? info.localPath
          : info.localPath,
    );

    _downloads[urlKey] = updated;
    _saveToPrefs();

    // Notificar al callback de la UI si existe
    final callback = _callbacks[urlKey];
    if (callback != null) {
      callback(updated);
    }
  }

  /// Inicializar el servicio (llamar en main.dart).
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadFromPrefs();
    AppLogger.d('VideoDownloadService inicializado (${_downloads.length} videos)');
  }

  /// Carga las descargas desde SharedPreferences.
  static Future<void> _loadFromPrefs() async {
    final raw = _prefs!.getString('video_downloads');
    if (raw == null) return;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _downloads.clear();
      map.forEach((key, value) {
        _downloads[key] = VideoDownloadInfo.fromJson(value as Map<String, dynamic>);
      });
    } catch (e) {
      AppLogger.e('VideoDownloadService: error cargando descargas', e);
    }
  }

  /// Guarda las descargas en SharedPreferences.
  static Future<void> _saveToPrefs() async {
    try {
      final map = _downloads.map((key, value) => MapEntry(key, value.toJson()));
      await _prefs!.setString('video_downloads', jsonEncode(map));
    } catch (e) {
      AppLogger.e('VideoDownloadService: error guardando descargas', e);
    }
  }

  /// Verifica si un video ya está descargado y disponible offline.
  static Future<bool> isDownloaded(String url) async {
    final info = _downloads[url];
    if (info == null || info.status != DownloadStatus.completed) return false;

    // Verificar que el archivo exista
    if (info.localPath == null) return false;
    final file = File(info.localPath!);
    return await file.exists();
  }

  /// Obtiene la información de descarga de un video.
  static VideoDownloadInfo? getInfo(String url) {
    return _downloads[url];
  }

  /// Obtiene la ruta local de un video descargado (null si no está descargado).
  static Future<String?> getLocalPath(String url) async {
    final info = _downloads[url];
    if (info == null || info.status != DownloadStatus.completed) return null;

    final file = File(info.localPath!);
    if (await file.exists()) {
      return info.localPath;
    }
    return null;
  }

  /// Inicia la descarga de un video.
  ///
  /// [url] es la URL del video a descargar.
  /// [onProgress] es un callback que se llama cuando hay actualizaciones.
  static Future<void> download(
    String url, {
    void Function(VideoDownloadInfo)? onProgress,
  }) async {
    // Si ya está descargado, no hacer nada
    if (await isDownloaded(url)) {
      AppLogger.d('VideoDownloadService: $url ya está descargado');
      return;
    }

    // Registrar callback
    if (onProgress != null) {
      _callbacks[url] = onProgress;
    }

    try {
      // Obtener directorio de descarga
      final dir = await getApplicationDocumentsDirectory();
      final videosDir = Directory('${dir.path}/videos');
      if (!await videosDir.exists()) {
        await videosDir.create(recursive: true);
      }

      // Generar nombre de archivo basado en el hash de la URL
      final filename = 'video_${url.hashCode}.mp4';
      final savePath = '${videosDir.path}/$filename';

      // Registrar info inicial
      _downloads[url] = VideoDownloadInfo(
        url: url,
        status: DownloadStatus.downloading,
        progress: 0,
        localPath: savePath,
      );
      _saveToPrefs();

      // Iniciar descarga con flutter_downloader
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: videosDir.path,
        fileName: filename,
        showNotification: false,
        openFileFromNotification: false,
      );

      if (taskId == null) {
        _downloads[url] = _downloads[url]!.copyWith(status: DownloadStatus.failed);
        _saveToPrefs();
        AppLogger.e('VideoDownloadService: error iniciando descarga de $url', null);
        return;
      }

      _downloads[url] = _downloads[url]!.copyWith(taskId: taskId);
      _saveToPrefs();

      AppLogger.i('VideoDownloadService: descarga iniciada para $url (taskId=$taskId)');
    } catch (e) {
      AppLogger.e('VideoDownloadService: error descargando $url', e);
      _downloads[url] = _downloads[url]!.copyWith(status: DownloadStatus.failed);
      _saveToPrefs();
    }
  }

  /// Pausa una descarga en progreso.
  static Future<void> pause(String url) async {
    final info = _downloads[url];
    if (info == null || info.taskId == null) return;

    try {
      await FlutterDownloader.pause(taskId: info.taskId!);
      _downloads[url] = info.copyWith(status: DownloadStatus.paused);
      _saveToPrefs();
    } catch (e) {
      AppLogger.e('VideoDownloadService: error pausando $url', e);
    }
  }

  /// Reanuda una descarga pausada.
  static Future<void> resume(String url) async {
    final info = _downloads[url];
    if (info == null || info.taskId == null) return;

    try {
      await FlutterDownloader.resume(taskId: info.taskId!);
      _downloads[url] = info.copyWith(status: DownloadStatus.downloading);
      _saveToPrefs();
    } catch (e) {
      AppLogger.e('VideoDownloadService: error reanudando $url', e);
    }
  }

  /// Cancela una descarga en progreso.
  static Future<void> cancel(String url) async {
    final info = _downloads[url];
    if (info == null) return;

    if (info.taskId != null) {
      try {
        await FlutterDownloader.cancel(taskId: info.taskId!);
      } catch (e) {
        AppLogger.e('VideoDownloadService: error cancelando $url', e);
      }
    }

    _downloads.remove(url);
    _callbacks.remove(url);
    _saveToPrefs();
  }

  /// Elimina un video descargado para liberar espacio.
  static Future<void> delete(String url) async {
    final info = _downloads[url];
    if (info == null) return;

    // Eliminar el archivo físico
    if (info.localPath != null) {
      try {
        final file = File(info.localPath!);
        if (await file.exists()) {
          await file.delete();
          AppLogger.d('VideoDownloadService: archivo eliminado ${info.localPath}');
        }
      } catch (e) {
        AppLogger.e('VideoDownloadService: error eliminando archivo', e);
      }
    }

    // Si hay una tarea activa, cancelarla
    if (info.taskId != null && info.status == DownloadStatus.downloading) {
      try {
        await FlutterDownloader.cancel(taskId: info.taskId!);
      } catch (_) {}
    }

    _downloads.remove(url);
    _callbacks.remove(url);
    _saveToPrefs();
    AppLogger.i('VideoDownloadService: descarga eliminada para $url');
  }

  /// Registra un callback para recibir actualizaciones de una descarga.
  static void registerCallback(
    String url,
    void Function(VideoDownloadInfo) callback,
  ) {
    _callbacks[url] = callback;
  }

  /// Elimina el callback de una descarga.
  static void unregisterCallback(String url) {
    _callbacks.remove(url);
  }

  /// Obtiene el tamaño total de los videos descargados en bytes.
  static Future<int> getTotalDownloadedSize() async {
    int total = 0;
    for (final info in _downloads.values) {
      if (info.status == DownloadStatus.completed && info.localPath != null) {
        try {
          final file = File(info.localPath!);
          if (await file.exists()) {
            total += await file.length();
          }
        } catch (_) {}
      }
    }
    return total;
  }

  /// Formatea un tamaño en bytes a una cadena legible (KB, MB, GB).
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
