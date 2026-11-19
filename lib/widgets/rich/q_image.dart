// lib/widgets/rich/q_image.dart
// Saber+ — Imagen embebida en contenido de preguntas.
//
// - Proxy inteligente: evita doble-proxy cuando el backend ya rewritó la URL
//   (modo revisión) y envuelve las URLs crudas de Moodle (modo intento).
// - Soporta data URIs (base64) que Moodle embebe ocasionalmente.
// - Altura máxima para no romper el layout; toque para abrir galería zoom.
//
// OPTIMIZACIÓN (motor v2):
//   Se migra de `Image(image: NetworkImage(url))` a `CachedNetworkImage`
//   para obtener caché en disco + memoria.
//
// FIX M2 (2026-11-13):
//   `smartProxy` acepta un parámetro opcional `apiBaseUrl`. Cuando se invoca
//   desde un isolate (vía `_BlockWalker._handleImage` dentro de `compute()`),
//   el llamador DEBE pasar `apiBaseUrl` explícito porque `Env.apiBaseUrl`
//   no es accesible allí (DotEnv no está inicializado en isolates). Si se
//   omite y estamos en main thread, se lee `Env.apiBaseUrl` con fallback.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/env.dart';
import '../../core/theme/app_colors.dart';

/// Galería a pantalla completa para imágenes de preguntas.
/// Recibe URLs YA proxyadas (por QImage.smartProxy / MoodleRichText).
class QImageGallery {
  static void open(BuildContext context, List<String> urls, int initialIndex) {
    if (urls.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _GalleryPage(urls: urls, initialIndex: initialIndex),
      ),
    );
  }
}

class _GalleryPage extends StatelessWidget {
  final List<String> urls;
  final int initialIndex;

  const _GalleryPage({required this.urls, required this.initialIndex});

  ImageProvider _provider(String url) {
    if (url.startsWith('data:')) {
      final commaIdx = url.indexOf(',');
      if (commaIdx > 0) {
        try {
          return MemoryImage(base64.decode(url.substring(commaIdx + 1)));
        } catch (_) {}
      }
    }
    return NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${initialIndex + 1} / ${urls.length}',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ),
      body: PhotoViewGallery.builder(
        itemCount: urls.length,
        pageController: PageController(initialPage: initialIndex),
        builder: (_, i) => PhotoViewGalleryPageOptions(
          imageProvider: _provider(urls[i]),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          errorBuilder: (context, error, stackTrace) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.broken_image_outlined,
                    color: Colors.white38, size: 48),
                SizedBox(height: 8),
                Text('No se pudo cargar la imagen',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          ),
        ),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      ),
    );
  }
}

class QImage extends StatelessWidget {
  final String src;
  final double maxHeight;
  final double? maxWidth;
  final VoidCallback? onTap;
  final String? semanticLabel;

  const QImage({
    Key? key,
    required this.src,
    this.maxHeight = 220,
    this.maxWidth,
    this.onTap,
    this.semanticLabel,
  }) : super(key: key);

  /// Proxy inteligente:
  /// 1. data URI → tal cual.
  /// 2. Ya pasa por get_file.php → tal cual (evita proxy anidado).
  /// 3. URL absoluta http(s) → envolver con el proxy del backend.
  /// 4. Protocolo-relativa //host/... → https://host/...
  /// 5. Relativa (/pluginfile.php/... o @@PLUGINFILE@@) → no resolvible,
  ///    se devuelve vacía y el widget muestra placeholder.
  ///
  /// [apiBaseUrl] es OBLIGATORIO cuando esta función se invoca desde un
  /// isolate (por ejemplo, `_BlockWalker._handleImage` dentro de
  /// `compute()`), porque `Env.apiBaseUrl` no es accesible allí
  /// (`DotEnv` no está inicializado). Si se omite, se asume main thread
  /// y se lee `Env.apiBaseUrl` con fallback seguro.
  static String smartProxy(String rawSrc, {String? apiBaseUrl}) {
    final src = rawSrc.trim();
    if (src.isEmpty) return '';
    if (src.startsWith('data:')) return src;
    if (src.contains('get_file.php')) return src;

    final base = apiBaseUrl ?? _safeApiBaseUrl();
    // Sin base no se puede proxear. Devolver '' para que el widget
    // muestre el placeholder, en lugar de una URL relativa rota.
    if (base.isEmpty) return '';

    if (src.startsWith('//')) {
      return '$base/get_file.php?url=${Uri.encodeFull('https:$src')}';
    }
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return '$base/get_file.php?url=${Uri.encodeFull(src)}';
    }
    // Relativa sin host — imposible de resolver en cliente.
    return '';
  }

  /// Lee `Env.apiBaseUrl` de forma segura. Solo debe llamarse en main
  /// thread. En isolate devuelve '' (y el llamador ya debería haber
  /// pasado `apiBaseUrl` explícito).
  static String _safeApiBaseUrl() {
    try {
      return Env.apiBaseUrl;
    } catch (e) {
      debugPrint('[QImage] Env.apiBaseUrl no disponible: $e');
      return '';
    }
  }

  ImageProvider? _imageProvider(String proxied) {
    if (proxied.isEmpty) return null;
    if (proxied.startsWith('data:')) {
      final commaIdx = proxied.indexOf(',');
      if (commaIdx < 0) return null;
      try {
        final data = base64.decode(proxied.substring(commaIdx + 1));
        return MemoryImage(data);
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(proxied);
  }

  @override
  Widget build(BuildContext context) {
    final proxied = smartProxy(src);
    final provider = _imageProvider(proxied);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (provider == null) {
      return Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 18,
              color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Imagen no disponible',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // ✅ OPTIMIZACIÓN (motor v2): usar CachedNetworkImage en lugar de
    // Image(image: NetworkImage(url)). CachedNetworkImage trae:
    //   - caché en disco (persistente entre sesiones)
    //   - caché en memoria (compartida con ImageCache global)
    //   - placeholder y errorBuilder nativos
    // Para data: URIs (base64) seguimos usando Image porque no son URLs
    // de red y no se benefician del caché en disco.
    final isDataUri = proxied.startsWith('data:');

    Widget image;
    if (isDataUri) {
      image = Image(
        image: provider!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          height: 60,
          width: 160,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.broken_image_outlined,
            size: 26,
            color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
          ),
        ),
      );
    } else {
      image = CachedNetworkImage(
        imageUrl: proxied,
        fit: BoxFit.contain,
        memCacheWidth: 800,
        placeholder: (context, url) => Container(
          height: 90,
          width: 160,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.primary,
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          height: 60,
          width: 160,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.broken_image_outlined,
            size: 26,
            color: isDark ? AppColors.darkTextTertiary : AppColors.textTertiary,
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight,
        maxWidth: maxWidth ?? double.infinity,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border,
              ),
            ),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: image,
                ),
                if (onTap != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppColors.overlay,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.zoom_in_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}