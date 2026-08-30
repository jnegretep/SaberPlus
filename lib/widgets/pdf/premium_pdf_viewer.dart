// lib/widgets/pdf/premium_pdf_viewer.dart
// Saber+ — Visor de PDF premium con soporte offline
//
// Características:
// - Descarga y cachea PDFs para uso offline
// - Indicador de progreso de descarga
// - Barra de progreso de lectura (página X de Y)
// - Recordar última página leída
// - Botón descargar/eliminar para offline
// - Zoom pinzable
// - Navegación de páginas (swipe)
// - Modo pantalla completa
// - Manejo de errores con reintentar
// - Dark mode adaptado

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_logger.dart';
import '../../core/services/pdf_cache_service.dart';

/// Visor de PDF premium con soporte offline.
class PremiumPdfViewer extends StatefulWidget {
  final String url;
  final String title;

  const PremiumPdfViewer({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<PremiumPdfViewer> createState() => _PremiumPdfViewerState();
}

class _PremiumPdfViewerState extends State<PremiumPdfViewer>
    with WidgetsBindingObserver {
  String? _localPath;
  bool _isLoading = true;
  bool _isDownloading = false;
  int _downloadProgress = 0;
  String? _errorMessage;

  // Estado del PDF
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isReady = false;

  // UI state
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPdf();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Guardar última página leída
    if (_totalPages > 0 && _currentPage > 0) {
      PdfCacheService.updateLastPageRead(widget.url, _currentPage);
    }
    super.dispose();
  }

  /// Carga el PDF: si está cacheado, local; si no, descarga.
  Future<void> _loadPdf() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 1. Verificar si ya está descargado (offline)
    final cachedPath = PdfCacheService.getLocalPath(widget.url);
    if (cachedPath != null) {
      AppLogger.d('PdfViewer: PDF cacheado encontrado → $cachedPath');
      _localPath = cachedPath;
      _loadLastPageRead();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // 2. Descargar
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final path = await PdfCacheService.download(
        widget.url,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      if (path == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _isDownloading = false;
          _errorMessage = 'No se pudo descargar el PDF';
        });
        return;
      }

      _localPath = path;
      _loadLastPageRead();

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isDownloading = false;
      });
    } catch (e) {
      AppLogger.e('PdfViewer: error descargando', e);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isDownloading = false;
        _errorMessage = 'Error: $e';
      });
    }
  }

  void _loadLastPageRead() {
    final info = PdfCacheService.getInfo(widget.url);
    if (info != null && info.lastPageRead > 0) {
      _currentPage = info.lastPageRead;
    }
  }

  /// Descarga el PDF para uso offline permanente (botón explícito).
  Future<void> _downloadForOffline() async {
    if (PdfCacheService.isDownloaded(widget.url)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este PDF ya está disponible sin conexión'),
          backgroundColor: AppColors.success,
        ),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    final path = await PdfCacheService.download(
      widget.url,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
          });
        }
      },
    );

    if (!mounted) return;

    if (path != null) {
      setState(() {
        _isDownloading = false;
        _localPath = path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ PDF descargado para uso offline'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      setState(() {
        _isDownloading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error descargando PDF'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _deleteDownload() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Eliminar PDF descargado?'),
        content: const Text(
          'Se borrará el documento de tu dispositivo. '
          'Podrás descargarlo nuevamente cuando quieras.',
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
      await PdfCacheService.delete(widget.url);
      if (!mounted) return;
      _loadPdf();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF eliminado del dispositivo'),
          backgroundColor: AppColors.textSecondary,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
              foregroundColor: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              elevation: 0,
              actions: [
                _buildDownloadButton(),
                IconButton(
                  icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                  onPressed: () {
                    setState(() {
                      _isFullscreen = !_isFullscreen;
                    });
                  },
                  tooltip: 'Pantalla completa',
                ),
              ],
            ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildDownloadButton() {
    final isDownloaded = PdfCacheService.isDownloaded(widget.url);

    if (isDownloaded) {
      return IconButton(
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: _deleteDownload,
        tooltip: 'Eliminar descarga',
      );
    }

    return IconButton(
      icon: const Icon(Icons.download_rounded),
      onPressed: _isDownloading ? null : _downloadForOffline,
      tooltip: 'Descargar para offline',
    );
  }

  Widget _buildBody(bool isDark) {
    // 1. Descargando
    if (_isDownloading && _localPath == null) {
      return _buildDownloadingWidget(isDark);
    }

    // 2. Cargando
    if (_isLoading) {
      return _buildLoadingWidget(isDark);
    }

    // 3. Error
    if (_errorMessage != null || _localPath == null) {
      return _buildErrorWidget(isDark);
    }

    // 4. PDF cargado
    return Stack(
      children: [
        Container(
          color: isDark ? AppColors.darkBackground : Colors.grey[200],
          child: PDFView(
            filePath: _localPath!,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            pageSnap: true,
            defaultPage: _currentPage,
            fitPolicy: FitPolicy.BOTH,
            backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
            onRender: (pages) {
              setState(() {
                _totalPages = pages ?? 0;
                _isReady = true;
              });
              PdfCacheService.updateTotalPages(widget.url, _totalPages);
            },
            onError: (error) {
              setState(() {
                _errorMessage = 'Error: $error';
              });
              AppLogger.e('PdfViewer: error renderizando', error);
            },
            onPageError: (page, error) {
              AppLogger.w('PdfViewer: error en página $page: $error');
            },
            onPageChanged: (page, total) {
              setState(() {
                _currentPage = page ?? 0;
                _totalPages = total ?? 0;
              });
              PdfCacheService.updateLastPageRead(widget.url, _currentPage);
            },
          ),
        ),

        // Barra de progreso inferior
        if (_isReady && _totalPages > 0 && !_isFullscreen)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildPageIndicator(isDark),
          ),

        // Indicador de página en pantalla completa
        if (_isReady && _totalPages > 0 && _isFullscreen)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_currentPage + 1} / $_totalPages',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPageIndicator(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSm,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Indicador de página + barra de progreso
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Página ${_currentPage + 1} de $_totalPages',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _totalPages > 0 ? (_currentPage + 1) / _totalPages : 0,
                      backgroundColor: isDark
                          ? AppColors.darkSurfaceVariant
                          : AppColors.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingWidget(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'Cargando documento...',
            style: TextStyle(
              color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadingWidget(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: _downloadProgress / 100,
                    strokeWidth: 6,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    backgroundColor: isDark
                        ? AppColors.darkSurfaceVariant
                        : AppColors.surfaceVariant,
                  ),
                ),
                Text(
                  '$_downloadProgress%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Descargando documento...',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 64,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              'No se pudo cargar el documento',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Verifica tu conexión e inténtalo de nuevo.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadPdf,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
