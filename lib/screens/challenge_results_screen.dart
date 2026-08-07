import '../config/env.dart';
// lib/screens/challenge_results_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../services/api_service.dart';
import '../widgets/podium_widget.dart';
import '../core/theme/app_colors.dart';

class ChallengeResultsScreen extends StatefulWidget {
  final ApiService api;
  final int challengeId;

  const ChallengeResultsScreen({
    Key? key,
    required this.api,
    required this.challengeId,
  }) : super(key: key);

  @override
  State<ChallengeResultsScreen> createState() => _ChallengeResultsScreenState();
}

class _ChallengeResultsScreenState extends State<ChallengeResultsScreen> {
  Map<String, dynamic>? _results;
  bool _loading = true;
  String? _error;
  final Map<int, bool> _expandedQuestions = {};

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    try {
      final resp = await widget.api.getChallengeResults(widget.challengeId);
      setState(() {
        _results = resp;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ==========================
  //   UTILIDADES
  // ==========================
  String _proxyUrl(String src) {
    final encoded = Uri.encodeFull(src);
    return '${Env.apiBaseUrl}/get_file.php?url=$encoded';
  }

  List<String> _extractImageUrls(String htmlText) {
    final exp = RegExp(
      r'''<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*>''',
      caseSensitive: false,
    );
    final urls = exp.allMatches(htmlText).map((m) => m.group(1)!).toList();
    return urls.where((u) => !u.contains('/i/unflagged')).toList();
  }

  String _removeImageTagsAndHeaders(String htmlText) {
    return htmlText
        .replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), '')
        .replaceAll(
            RegExp(r'<div[^>]*class="grade"[^>]*>.*?<\/div>',
                caseSensitive: false, dotAll: true),
            '')
        .replaceAll(
            RegExp(r'<h3[^>]*>.*?<\/h3>',
                caseSensitive: false, dotAll: true),
            '')
        .trim();
  }

  void _openImageGallery(BuildContext context, List<String> urls, int index) {
    if (urls.isEmpty) return;
    final proxy = urls.map(_proxyUrl).toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: AppColors.textSecondary,
            elevation: 0,
            iconTheme: const IconThemeData(color: AppColors.textOnPrimary),
          ),
          body: PhotoViewGallery.builder(
            itemCount: proxy.length,
            pageController: PageController(initialPage: index),
            builder: (_, i) => PhotoViewGalleryPageOptions(
              imageProvider: NetworkImage(proxy[i]),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
            ),
            backgroundDecoration: BoxDecoration(color: Colors.black),
            loadingBuilder: (context, event) => Center(
              child: CircularProgressIndicator(
                value: event == null
                    ? 0
                    : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================
  //   ESTADO Y FEEDBACK
  // ==========================
  String _extractState(String htmlText) {
    final low = htmlText.toLowerCase();

    if (low.contains('class="que multichoice deferredfeedback correct"') ||
        low.contains('gradedright')) return 'Correcta';

    if (low.contains('class="que multichoice deferredfeedback incorrect"') ||
        low.contains('gradedwrong')) return 'Incorrecta';

    if (low.contains('no contest') ||
        low.contains('sin responder') ||
        low.contains('not answered')) return 'Sin responder';

    return 'Sin responder';
  }

  Color _stateColor(String s) {
    s = s.toLowerCase();
    if (s == 'correcta') return AppColors.successDark;
    if (s == 'incorrecta') return AppColors.error;
    return AppColors.warning;
  }

  String _extractFeedback(String htmlText) {
    final exp = RegExp(
      r'<div[^>]*class="feedback"[^>]*>([\s\S]*?)<\/div>',
      caseSensitive: false,
    );

    final match = exp.firstMatch(htmlText);
    String content = match != null ? match.group(1)!.trim() : '';

    content = content
        .replaceAll(
          RegExp(
            r'Se\s*punt(úa|ua).*?[\.]?',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'\bCorrecta\b', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\bIncorrecta\b', caseSensitive: false),
          '',
        )
        .trim();

    return content;
  }

  Widget _renderHtmlWithMath(String htmlText, {bool isFeedback = false}) {
    final widgets = <Widget>[];
    final regex = RegExp(r'(\\\(.+?\\\)|\\\[.+?\\\])', dotAll: true);
    final matches = regex.allMatches(htmlText);

    if (matches.isEmpty) {
      return Html(
        data: htmlText,
        style: {
          "body": Style(
            margin: Margins.zero,
            padding: HtmlPaddings.zero,
            fontSize: FontSize(isFeedback ? 14.0 : 15.0),
            lineHeight: LineHeight(isFeedback ? 1.4 : 1.5),
            color: AppColors.borderDark,
          ),
          "p": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        },
      );
    }

    int last = 0;
    for (final match in matches) {
      if (match.start > last) {
        final text = htmlText.substring(last, match.start);
        if (text.trim().isNotEmpty) {
          widgets.add(Html(
            data: text,
            style: {
              "body": Style(
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
                fontSize: FontSize(isFeedback ? 14.0 : 15.0),
                lineHeight: LineHeight(isFeedback ? 1.4 : 1.5),
                color: AppColors.borderDark,
              ),
            },
          ));
        }
      }

      final latex = match.group(0)!
          .replaceAll(r'\(', '')
          .replaceAll(r'\)', '')
          .replaceAll(r'\[', '')
          .replaceAll(r'\]', '');

      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Math.tex(
            latex,
            textStyle: TextStyle(
              fontSize: isFeedback ? 14 : 15,
            ),
          ),
        ),
      );

      last = match.end;
    }

    if (last < htmlText.length) {
      final text = htmlText.substring(last);
      if (text.trim().isNotEmpty) {
        widgets.add(Html(
          data: text,
          style: {
            "body": Style(
              margin: Margins.zero,
              padding: HtmlPaddings.zero,
              fontSize: FontSize(isFeedback ? 14.0 : 15.0),
              lineHeight: LineHeight(isFeedback ? 1.4 : 1.5),
              color: AppColors.borderDark,
            ),
          },
        ));
      }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: widgets,
    );
  }

  // ==========================
  //   HELPERS
  // ==========================
  String _formatElapsed(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatScore(dynamic score) {
    if (score == null) return '0.00';
    final value = score is num ? score.toDouble() : double.tryParse(score.toString()) ?? 0.0;
    return value.toStringAsFixed(2);
  }

  int _correctCount(List<Map<String, dynamic>> qs) {
    return qs.where((q) => _extractState(q['html'] ?? '') == 'Correcta').length;
  }

  // ==========================
  //   WIDGETS REDISEÑADOS
  // ==========================
  Widget _buildQuestionCard(Map<String, dynamic> q, int index) {
    final html = q['html'] ?? '';
    final clean = _removeImageTagsAndHeaders(html);
    final imgs = _extractImageUrls(html);
    final state = _extractState(html);
    final color = _stateColor(state);
    final feedback = _extractFeedback(html);
    final hasFeedback = feedback.isNotEmpty;
    final isExpanded = _expandedQuestions[index] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
          color: color.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER DE LA PREGUNTA
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            state == 'Correcta'
                                ? Icons.check_circle_rounded
                                : state == 'Incorrecta'
                                    ? Icons.cancel_rounded
                                    : Icons.error_outline_rounded,
                            size: 16,
                            color: color,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Pregunta ${q['slot'] ?? (index + 1)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        state,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Imágenes de la pregunta
                if (imgs.isNotEmpty)
                  Column(
                    children: [
                      SizedBox(
                        height: 140,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: imgs.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, idxImg) {
                            final src = imgs[idxImg];
                            return GestureDetector(
                              onTap: () => _openImageGallery(context, imgs, idxImg),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    Image.network(
                                      _proxyUrl(src),
                                      fit: BoxFit.cover,
                                      height: 140,
                                      width: 180,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Container(
                                          width: 180,
                                          height: 140,
                                          color: AppColors.surfaceVariant,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              value: loadingProgress.expectedTotalBytes != null
                                                  ? loadingProgress.cumulativeBytesLoaded /
                                                      loadingProgress.expectedTotalBytes!
                                                  : null,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: AppColors.overlay,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Icon(
                                          Icons.zoom_in_rounded,
                                          size: 16,
                                          color: AppColors.textOnPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                
                // Contenido de la pregunta
                _renderHtmlWithMath(clean),
              ],
            ),
          ),
          
          // FEEDBACK DESPLEGABLE (si existe)
          if (hasFeedback)
            Column(
              children: [
                Divider(height: 0),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _expandedQuestions[index] = !isExpanded;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceClean,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      border: Border.all(
                        color: AppColors.border,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 20,
                          color: color,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Retroalimentación',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: color,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExpanded)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceClean,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      border: Border.all(
                        color: AppColors.border,
                        width: 1,
                      ),
                    ),
                    child: _renderHtmlWithMath(feedback, isFeedback: true),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ==========================
  //   WIDGET DE PARTICIPANTE
  // ==========================
  Widget _buildParticipantCard(Map<String, dynamic> participant, int position) {
    final isTop3 = position <= 3;
    final avatarUrl = participant['avatar_url']?.toString();
    final nombre = participant['nombre']?.toString() ?? 'Usuario';
    final elapsed = participant['elapsed'] is num
        ? participant['elapsed'].toInt()
        : int.tryParse(participant['elapsed'].toString()) ?? 0;
    final score = participant['score'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTop3 ? AppColors.primary : AppColors.border,
          width: isTop3 ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMd,
            blurRadius: isTop3 ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Posición
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isTop3 ? AppColors.primary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$position',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isTop3 ? AppColors.textOnPrimary : AppColors.borderDark,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.surfaceVariant,
            backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? NetworkImage(avatarUrl)
                : null,
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? Text(
                    nombre[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          
          // Información
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Tiempo: ${_formatElapsed(elapsed)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          
          // Puntuación
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${_formatScore(score)} pts',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
              const SizedBox(height: 16),
              const Text(
                'Cargando resultados...',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 1,
          title: const Text(
            'Resultados del reto',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        body: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadowSm,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: AppColors.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error al cargar los resultados: $_error',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
final ranking = _results!['ranking'] as List<dynamic>? ?? [];
final rawQs = _results!['questions'] as List<dynamic>? ?? [];
final questions = rawQs.map((e) => Map<String, dynamic>.from(e)).toList();

final correct = _correctCount(questions);
final total = questions.length;
final scorePercent = total > 0 ? (correct / total) * 100.0 : 0.0;

// 👉 Convertimos ranking a Map seguro y tomamos máximo 3
final podiumRanking = ranking
    .take(3)
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

return Scaffold(
  backgroundColor: AppColors.background,
  appBar: AppBar(
    backgroundColor: AppColors.surface,
    elevation: 1,
    centerTitle: false,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resultados del reto',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${scorePercent.toStringAsFixed(1)}% correctas • $correct/$total preguntas',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    ),
  ),
  body: RefreshIndicator(
    onRefresh: _loadResults,
    color: AppColors.primary,
    backgroundColor: AppColors.surface,
    child: LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🏆 Podio (1, 2 o 3 participantes)
                if (podiumRanking.isNotEmpty)
                  Container(
                    width: double.infinity,
                    child: PodiumWidget(
                      ranking: podiumRanking,
                      maxWidth: constraints.maxWidth - 32, // Restamos padding
                    ),
                  ),

                // 📊 Ranking completo
                if (ranking.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
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
                      children: [
                        const Text(
                          'Ranking completo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...ranking.asMap().entries.map((entry) {
                          final index = entry.key;
                          final participant =
                              Map<String, dynamic>.from(entry.value);
                          return _buildParticipantCard(
                            participant,
                            index + 1,
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],

                // ❓ Revisión de preguntas
                const Text(
                  "Revisión de preguntas",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                ...questions.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final q = entry.value;
                  return _buildQuestionCard(q, idx);
                }).toList(),
              ],
            ),
          ),
        );
      },
    ),
  ),
);
  }
}