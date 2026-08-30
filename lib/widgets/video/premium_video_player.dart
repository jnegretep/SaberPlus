// lib/widgets/video/premium_video_player.dart
// Saber+ — Reproductor de video premium con soporte offline
//
// Características:
// - Streaming online (como antes, con chewie)
// - Descarga para ver offline (con flutter_downloader)
// - Indicador de progreso de descarga
// - Botón para eliminar descarga y liberar espacio
// - Detección automática: si está descargado, reproduce local; si no, streaming
// - Manejo de errores mejorado con botón reintentar
// - Placeholder con thumbnail/poster mientras carga

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_logger.dart';
import '../../core/services/video_download_service.dart';

/// Reproductor de video premium con soporte offline.
///
/// Uso:
/// ```dart
/// PremiumVideoPlayer(url: 'https://example.com/video.mp4')
/// ```
class PremiumVideoPlayer extends StatefulWidget {
  final String url;
  final String? title;        // título opcional para mostrar en el header
  final String? posterUrl;    // URL de imagen de poster (opcional)

  const PremiumVideoPlayer({
    super.key,
    required this.url,
    this.title,
    this.posterUrl,
  });

  @override
  State<PremiumVideoPlayer> createState() => _PremiumVideoPlayerState();
}

class _PremiumVideoPlayerState extends State<PremiumVideoPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  ChewieController? _chewie;
  bool _isInitializing = true;
  bool _hasError = false;
  String? _errorMessage;

  // Estado de descarga
  VideoDownloadInfo? _downloadInfo;
  bool _isCheckingDownload = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkDownloadStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VideoDownloadService.unregisterCallback(widget.url);
    _chewie?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pausar el video cuando la app va a background
    if (state == AppLifecycleState.paused) {
      _controller?.pause();
    }
  }

  /// Verifica si el video ya está descargado.
  Future<void> _checkDownloadStatus() async {
    final isDownloaded = await VideoDownloadService.isDownloaded(widget.url);
    final info = VideoDownloadService.getInfo(widget.url);

    if (!mounted) return;

    setState(() {
      _downloadInfo = info;
      _isCheckingDownload = false;
    });

    // Si ya está descargado, reproducir desde local
    if (isDownloaded) {
      final localPath = await VideoDownloadService.getLocalPath(widget.url);
      if (localPath != null && mounted) {
        await _initializeVideo(localPath, isLocal: true);
      }
    } else {
      // Si hay una descarga en progreso, registrar callback
      if (info != null &&
          (info.status == DownloadStatus.downloading ||
              info.status == DownloadStatus.paused)) {
        VideoDownloadService.registerCallback(widget.url, _onDownloadProgress);
      }
      // Reproducir streaming
      await _initializeVideo(widget.url, isLocal: false);
    }
  }

  /// Callback que se llama cuando hay progreso en la descarga.
  void _onDownloadProgress(VideoDownloadInfo info) {
    if (!mounted) return;
    setState(() {
      _downloadInfo = info;
    });

    // Si la descarga se completó y estamos en streaming, cambiar a local
    if (info.status == DownloadStatus.completed && _controller != null) {
      _switchToLocalPlayback(info.localPath!);
    }
  }

  /// Inicializa el reproductor de video.
  Future<void> _initializeVideo(String source, {required bool isLocal}) async {
    setState(() {
      _isInitializing = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      // Limpiar controlador anterior si existe
      _chewie?.dispose();
      _controller?.dispose();

      _controller = isLocal
          ? VideoPlayerController.file(File(source))
          : VideoPlayerController.networkUrl(Uri.parse(source));

      await _controller!.initialize();

      if (!mounted) return;

      _chewie = ChewieController(
        videoPlayerController: _controller!,
        autoPlay: false,
        looping: false,
        showControls: true,
        aspectRatio: _controller!.value.aspectRatio,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.primary,
          handleColor: AppColors.primary,
          backgroundColor: AppColors.stepInactive,
          bufferedColor: AppColors.textDisabled,
        ),
        placeholder: _buildPlaceholder(),
        errorBuilder: (context, errorMessage) {
          return _buildErrorWidget(errorMessage);
        },
      );

      setState(() {
        _isInitializing = false;
      });

      AppLogger.d('VideoPlayer: inicializado (${isLocal ? "local" : "streaming"}) - ${widget.url}');
    } catch (e) {
      AppLogger.e('VideoPlayer: error inicializando', e);
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  /// Cambia la reproducción de streaming a local (cuando se completa la descarga).
  Future<void> _switchToLocalPlayback(String localPath) async {
    AppLogger.i('VideoPlayer: cambiando a reproducción local');

    // Guardar la posición actual para continuar desde ahí
    final position = _controller?.value.position;

    await _initializeVideo(localPath, isLocal: true);

    // Restaurar posición
    if (position != null && _controller != null) {
      await _controller!.seekTo(position);
    }
  }

  /// Inicia la descarga del video para ver offline.
  Future<void> _startDownload() async {
    VideoDownloadService.registerCallback(widget.url, _onDownloadProgress);
    await VideoDownloadService.download(widget.url, onProgress: _onDownloadProgress);
  }

  /// Elimina la descarga para liberar espacio.
  Future<void> _deleteDownload() async {
    VideoDownloadService.unregisterCallback(widget.url);

    // Mostrar confirmación
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Eliminar video descargado?'),
        content: const Text(
          'Se borrará el video de tu dispositivo. '
          'Podrás verlo nuevamente en streaming o descargarlo de nuevo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await VideoDownloadService.delete(widget.url);
      if (mounted) {
        setState(() {
          _downloadInfo = null;
        });
        // Volver a streaming
        await _initializeVideo(widget.url, isLocal: false);
      }
    } else {
      // Re-registrar callback si no se eliminó
      VideoDownloadService.registerCallback(widget.url, _onDownloadProgress);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowLg,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // ── Reproductor ──
            _buildPlayer(),

            // ── Barra de acciones (descarga/eliminar) ──
            _buildActionBar(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayer() {
    if (_isCheckingDownload || _isInitializing) {
      return _buildLoadingWidget();
    }

    if (_hasError) {
      return _buildErrorWidget(_errorMessage ?? 'Error desconocido');
    }

    if (_chewie == null) return const SizedBox.shrink();

    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: Chewie(controller: _chewie!),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.divider,
      child: Center(
        child: Icon(
          Icons.videocam_outlined,
          color: AppColors.textDisabled,
          size: 48,
        ),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      height: 200,
      color: AppColors.divider,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
            const SizedBox(height: 12),
            Text(
              _isCheckingDownload ? 'Verificando...' : 'Cargando video...',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String errorMessage) {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      color: AppColors.divider,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            const Text(
              'No se pudo cargar el video',
              style: TextStyle(
                color: AppColors.textDisabled,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _initializeVideo(widget.url, isLocal: false),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Barra de acciones debajo del reproductor.
  Widget _buildActionBar(bool isDark) {
    // Si está verificando descarga, no mostrar nada
    if (_isCheckingDownload) return const SizedBox.shrink();

    final info = _downloadInfo;

    // Caso 1: No descargado → botón "Descargar para offline"
    if (info == null || info.status == DownloadStatus.notDownloaded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.download_outlined,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Descargar para ver sin conexión',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: _startDownload,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: const Size(0, 28),
              ),
              child: const Text(
                'Descargar',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    // Caso 2: Descargando → barra de progreso
    if (info.status == DownloadStatus.downloading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                value: info.progress / 100,
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Descargando... ${info.progress}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: info.progress / 100,
                      backgroundColor: AppColors.stepInactive,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => VideoDownloadService.cancel(widget.url),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 28),
              ),
              child: const Text(
                'Cancelar',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    // Caso 3: Descarga completada → badge "Disponible offline" + botón eliminar
    if (info.status == DownloadStatus.completed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.1),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: AppColors.success,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Disponible sin conexión',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.successDark,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _deleteDownload,
              icon: Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Eliminar'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 28),
              ),
            ),
          ],
        ),
      );
    }

    // Caso 4: Descarga fallida → botón reintentar
    if (info.status == DownloadStatus.failed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.1),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Error en la descarga',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ),
            TextButton(
              onPressed: _startDownload,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 28),
              ),
              child: const Text(
                'Reintentar',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    // Caso 5: Pausada → botón reanudar
    if (info.status == DownloadStatus.paused) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        ),
        child: Row(
          children: [
            Icon(Icons.pause_circle_outline, size: 18, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Descarga pausada (${info.progress}%)',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => VideoDownloadService.resume(widget.url),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 28),
              ),
              child: const Text(
                'Reanudar',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
