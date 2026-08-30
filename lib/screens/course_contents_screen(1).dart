import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import '../models/course_section.dart';
import '../models/course_module.dart';
import '../services/api_service.dart';
import 'quiz_intro_screen.dart';
import 'html_viewer_screen.dart';
import '../core/theme/app_colors.dart';

class CourseContentsScreen extends StatefulWidget {
  final int courseId;
  final String courseName;

  const CourseContentsScreen({
    super.key,
    required this.courseId,
    required this.courseName,
  });

  @override
  State<CourseContentsScreen> createState() => _CourseContentsScreenState();
}

class _CourseContentsScreenState extends State<CourseContentsScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  List<CourseSection> _sections = [];
  TabController? _tabController;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadContents();
  }

  Future<void> _loadContents() async {
    final api = context.read<ApiService>();

    try {
      final sections = await api.fetchCourseContents(widget.courseId);
      if (!mounted) return;

      setState(() {
        _sections = sections;
        _loading = false;
      });

      _tabController?.dispose();
      _tabController =
          TabController(length: _sections.length, vsync: this);
    } catch (e) {
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    if (_sections.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 1,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.courseName,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: AppColors.textDisabled,
              ),
              const SizedBox(height: 16),
              Text(
                _loadError ?? 'No hay contenidos disponibles',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (_loadError != null)
                ElevatedButton(
                  onPressed: _loadContents,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Reintentar',
                    style: TextStyle(color: AppColors.textOnPrimary),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header mejorado
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadowSm,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textSecondary,
                      size: 24,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.courseName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),

            // Tabs mejorados
            Container(
              color: AppColors.surface,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                indicatorPadding: const EdgeInsets.symmetric(horizontal: 8),
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textTertiary,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                unselectedLabelStyle: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                tabs: _sections
                    .map((s) => Tab(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              s.name.isEmpty ? 'Unidad' : s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),

            // Contenido
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _sections.map(_buildSectionView).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────── SECTION VIEW ─────────────────

  Widget _buildSectionView(CourseSection s) {
    final summary = s.summary ?? '';

    // Primero extraemos los videos del HTML original
    final videos = _extractVideoUrls(summary);
    // Luego limpiamos el HTML para mostrar, pero sin eliminar las URLs de video
    final cleanedHtml = _cleanHtmlForDisplay(summary);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cleanedHtml.trim().isNotEmpty)
            _buildHtmlWithLatex(cleanedHtml),

          // Mostrar videos si existen
          if (videos.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 8),
              child: Text(
                'Videos del contenido',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ...videos.map((url) => _VideoCard(url: url)),
          ],

          if (s.modules.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 12),
              child: Text(
                'Módulos y actividades',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ...s.modules.map(_buildModuleCard),
          ],
        ],
      ),
    );
  }

  // ───────────────── MODULE CARD ─────────────────

  Widget _buildModuleCard(CourseModule m) {
    final mod = m.modName.toLowerCase();

    IconData icon;
    Color color;
    String typeText;

    switch (mod) {
      case 'quiz':
        icon = Icons.quiz_rounded;
        color = AppColors.primary;
        typeText = 'Cuestionario';
        break;
      case 'page':
      case 'lesson':
        icon = Icons.menu_book_rounded;
        color = AppColors.successDark;
        typeText = 'Lección';
        break;
      case 'url':
        icon = Icons.open_in_new_rounded;
        color = AppColors.purple;
        typeText = 'Enlace externo';
        break;
      case 'resource':
      case 'file':
        icon = Icons.attach_file_rounded;
        color = AppColors.warning;
        typeText = 'Recurso';
        break;
      default:
        icon = Icons.description_rounded;
        color = AppColors.textMuted;
        typeText = 'Contenido';
    }

    return InkWell(
      onTap: () => _onModuleTap(m),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowSm,
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: AppColors.divider,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Icono circular con color de fondo
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withOpacity(0.3), width: 1.5),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            
            const SizedBox(width: 16),
            
            // Información del módulo
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    typeText,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            
            // Indicador de acción
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────── TAP HANDLER ─────────────────

  Future<void> _onModuleTap(CourseModule m) async {
    final api = context.read<ApiService>();
    final mod = m.modName.toLowerCase();

    if (mod == 'quiz' && m.quizId != null) {
      final quizzes = await api.fetchQuizzes(widget.courseId);
      final quiz = quizzes.firstWhere((q) => q.quizId == m.quizId);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuizIntroScreen(
            quizId: quiz.quizId,
            quizName: quiz.name,
            courseId: quiz.courseId,
            timeLimit: quiz.timelimit,
            questions: quiz.questions,
            api: api,
          ),
        ),
      );
      return;
    }

    final html = _findHtmlContentInModule(m);
    if (html != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HtmlViewerScreen(
            title: m.name,
            html: html,
          ),
        ),
      );
      return;
    }

    final uri = Uri.tryParse(m.url ?? '');
    if (uri != null) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ───────────────── VIDEO URL EXTRACTION ─────────────────

  List<String> _extractVideoUrls(String html) {
    final regex = RegExp(r'(https?:\/\/[^\s"<]+\.mp4)', caseSensitive: false);
    
    final matches = regex.allMatches(html);
    final urls = <String>[];
    
    for (final match in matches) {
      String url = match.group(0)!;
      
      // Decodificar la URL
      try {
        url = Uri.decodeFull(url);
      } catch (_) {}
      
      // Limpiar la URL - eliminar basura HTML que pueda estar pegada
      url = _cleanVideoUrl(url);
      
      // Solo agregar si la URL parece válida
      if (url.isNotEmpty && url.contains('.mp4')) {
        urls.add(url);
      }
    }
    
    return urls.toSet().toList(); // Eliminar duplicados
  }

  String _cleanVideoUrl(String url) {
    // Encontrar la posición del .mp4
    final mp4Index = url.toLowerCase().indexOf('.mp4');
    if (mp4Index != -1) {
      // Cortar en .mp4 + 4 caracteres (incluye .mp4)
      url = url.substring(0, mp4Index + 4);
    }
    
    // Eliminar cualquier etiqueta HTML o basura que pueda quedar
    url = url
        .replaceAll(RegExp(r'</video>'), '')
        .replaceAll(RegExp(r'&nbsp;'), '')
        .replaceAll(RegExp(r'<br>'), '')
        .replaceAll(RegExp(r'<p>'), '')
        .replaceAll(RegExp(r'</p>'), '')
        .replaceAll(RegExp(r'\s+'), '') // Eliminar espacios
        .trim();
    
    return url;
  }

  // ───────────────── HTML CLEANING FOR DISPLAY ─────────────────

  String _cleanHtmlForDisplay(String html) {
    if (html.isEmpty) return '';
    
    // Decodificar URL primero
    String decoded;
    try {
      decoded = Uri.decodeFull(html);
    } catch (_) {
      decoded = html;
    }
    
    // Eliminar bloques de video completos con su contenido
    decoded = decoded.replaceAll(
      RegExp(r'<video[\s\S]*?</video>', caseSensitive: false),
      '',
    );
    
    // Eliminar URLs de video sueltas PERO conservar el resto del contenido
    // Solo eliminar la URL en sí, no el contexto alrededor
    decoded = decoded.replaceAll(
      RegExp(r'https?:\/\/[^\s"<]+\.mp4[^\s"<]*', caseSensitive: false),
      '', // Eliminar solo la URL, no todo el texto
    );
    
    // Eliminar etiquetas HTML problemáticas pero mantener contenido
    decoded = decoded
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'<p>\s*</p>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<div[^>]*>'), '')
        .replaceAll('</div>', '')
        .replaceAll(RegExp(r'<span[^>]*>'), '')
        .replaceAll('</span>', '');
    
    // Eliminar múltiples espacios y saltos de línea
    decoded = decoded
        .replaceAll(RegExp(r'\n\s*\n'), '\n\n')
        .replaceAll(RegExp(r'\s{2,}'), ' ');
    
    return decoded.trim();
  }

  // ───────────────── HTML WITH LATEX ─────────────────

  Widget _buildHtmlWithLatex(String html) {
    if (html.trim().isEmpty) return const SizedBox.shrink();
    
    final regex = RegExp(r'(\\\(.+?\\\)|\\\[.+?\\\])', dotAll: true);
    final matches = regex.allMatches(html);

    if (matches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowMd,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: HtmlWidget(
          html,
          textStyle: TextStyle(
            fontSize: 15,
            color: AppColors.borderDark,
            height: 1.5,
          ),
        ),
      );
    }

    final widgets = <Widget>[];
    int last = 0;

    for (final m in matches) {
      if (m.start > last) {
        widgets.add(HtmlWidget(
          html.substring(last, m.start),
          textStyle: TextStyle(
            fontSize: 15,
            color: AppColors.borderDark,
            height: 1.5,
          ),
        ));
      }

      final latex = m.group(0)!
          .replaceAll(r'\(', '')
          .replaceAll(r'\)', '')
          .replaceAll(r'\[', '')
          .replaceAll(r'\]', '');

      widgets.add(
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceClean,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Center(
            child: Math.tex(
              latex,
              textStyle: TextStyle(fontSize: 18),
            ),
          ),
        ),
      );

      last = m.end;
    }

    if (last < html.length) {
      widgets.add(HtmlWidget(
        html.substring(last),
        textStyle: TextStyle(
          fontSize: 15,
          color: AppColors.borderDark,
          height: 1.5,
        ),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMd,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widgets,
      ),
    );
  }

  String? _findHtmlContentInModule(CourseModule m) {
    for (final c in m.contents) {
      if (c.content != null && c.content!.trim().isNotEmpty) {
        return _cleanHtmlForDisplay(c.content!);
      }
    }
    return null;
  }
}

// ───────────────── VIDEO CARD ─────────────────

class _VideoCard extends StatefulWidget {
  final String url;
  const _VideoCard({required this.url});

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  late VideoPlayerController _controller;
  ChewieController? _chewie;
  bool _isInitializing = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      // Limpiar la URL antes de usarla
      String cleanUrl = widget.url.trim();
      
      // Asegurarse de que la URL esté completa
      if (!cleanUrl.startsWith('http')) {
        cleanUrl = 'https://$cleanUrl';
      }
      
      _controller = VideoPlayerController.networkUrl(Uri.parse(cleanUrl));
      await _controller.initialize();
      
      if (!mounted) return;
      
      setState(() {
        _chewie = ChewieController(
          videoPlayerController: _controller,
          autoPlay: false,
          looping: false,
          showControls: true,
          materialProgressColors: ChewieProgressColors(
            playedColor: AppColors.primary,
            handleColor: AppColors.primary,
            backgroundColor: AppColors.stepInactive,
            bufferedColor: AppColors.textDisabled,
          ),
          placeholder: Container(
            color: AppColors.divider,
            child: const Center(
              child: Icon(
                Icons.videocam_outlined,
                color: AppColors.textDisabled,
                size: 48,
              ),
            ),
          ),
          errorBuilder: (context, errorMessage) {
            return Container(
              color: AppColors.divider,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: AppColors.error,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Error cargando video',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
        _isInitializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _hasError = true;
      });
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Container(
        height: 200,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      );
    }

    if (_hasError) {
      return Container(
        height: 200,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 48,
              ),
              const SizedBox(height: 12),
              const Text(
                'No se pudo cargar el video',
                style: TextStyle(
                  color: AppColors.textDisabled,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.url.length > 50 
                    ? '${widget.url.substring(0, 50)}...' 
                    : widget.url,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textDisabled,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_chewie == null) return const SizedBox.shrink();

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
        child: AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: Chewie(controller: _chewie!),
        ),
      ),
    );
  }
}