// lib/screens/chat_screen.dart
// Saber+ IA — Premium Chat Screen
// Animated bubbles, typing dots, quick suggestions, dark mode

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../config/env.dart';
import '../core/utils/app_logger.dart';
import '../core/theme/app_colors.dart';
import '../core/animations/app_animations.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;

  final String _apiUrl = Env.aiApiUrl;

  // Quick suggestion chips
  final List<String> _quickSuggestions = [
    '¿Cómo mejorar en Matemáticas?',
    'Tips para el ICFES',
    '¿Qué áreas debo reforzar?',
    'Consejos de estudio',
  ];

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    final nombre = (auth.nombre ?? 'Usuario').split(' ').first;
    _messages.add({
      'role': 'assistant',
      'text':
          '¡Hola $nombre! Soy Saber+, tu tutor inteligente. Pregúntame lo que quieras sobre el ICFES, cómo mejorar tus puntajes o pídame consejos de estudio.'
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildMessageContent(String text) {
    String processedText = text;
    processedText = processedText.replaceAll('**', '<b>');
    processedText = processedText.replaceAll('* ', '<br>• ');
    processedText = processedText.replaceAll('\n', '<br>');

    final widgets = <Widget>[];
    final regex = RegExp(r'(\\\(.+?\\\)|\\\[.+?\\\])', dotAll: true);
    final matches = regex.allMatches(processedText);

    if (matches.isEmpty) {
      return Html(
        data: processedText,
        style: {
          "body": Style(
            margin: Margins.zero,
            padding: HtmlPaddings.zero,
            fontSize: FontSize(15.0),
            lineHeight: LineHeight(1.5),
            color: AppColors.textOnPrimary,
          ),
        },
      );
    }

    int last = 0;
    for (final match in matches) {
      if (match.start > last) {
        final htmlPart = processedText.substring(last, match.start);
        widgets.add(Html(
            data: htmlPart,
            style: {
              "body": Style(
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                  fontSize: FontSize(15.0),
                  lineHeight: LineHeight(1.5),
                  color: AppColors.textOnPrimary),
            }));
      }

      final latex = match
          .group(0)!
          .replaceAll(r'\(', '')
          .replaceAll(r'\)', '')
          .replaceAll(r'\[', '')
          .replaceAll(r'\]', '');
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Math.tex(latex,
            textStyle: TextStyle(fontSize: 15, color: AppColors.textOnPrimary)),
      ));

      last = match.end;
    }

    if (last < processedText.length) {
      widgets.add(Html(
          data: processedText.substring(last),
          style: {
            "body": Style(
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
                fontSize: FontSize(15.0),
                lineHeight: LineHeight(1.5),
                color: AppColors.textOnPrimary),
          }));
    }

    return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: widgets);
  }

  String _cleanJsonResponse(String rawBody) {
    if (rawBody.startsWith('\uFEFF')) {
      rawBody = rawBody.substring(1);
    }
    if (rawBody.startsWith('ï»¿')) {
      rawBody = rawBody.substring(3);
    }
    rawBody = rawBody.trim();

    final jsonStart = rawBody.indexOf('{');
    if (jsonStart != -1 && jsonStart > 0) {
      rawBody = rawBody.substring(jsonStart);
    }

    return rawBody;
  }

  Future<void> _sendMessage({String? preset}) async {
    final text = preset ?? _textController.text.trim();
    if (text.isEmpty || _isLoading) return;

    _textController.clear();

    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final auth = context.read<AuthService>();

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'moodle_id': auth.moodleId,
          'mensaje': text,
        }),
      );

      if (response.statusCode == 200) {
        final cleanBody = _cleanJsonResponse(response.body);
        final data = jsonDecode(cleanBody);

        if (data['exito'] == true) {
          setState(() {
            _messages.add({'role': 'assistant', 'text': data['respuesta']});
          });
        } else {
          setState(() {
            _messages.add({
              'role': 'assistant',
              'text': 'Ups, tuve un problema para pensar. Intenta de nuevo.'
            });
          });
        }
      } else {
        setState(() {
          _messages.add({
            'role': 'assistant',
            'text': 'Error de conexión. Revisa tu internet.'
          });
        });
      }
    } catch (e) {
      AppLogger.e('Chat error', e);
      setState(() {
        _messages.add({
          'role': 'assistant',
          'text': 'Error de conexión. Revisa tu internet.'
        });
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBackground : AppColors.background;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final assistantBubbleColor = isDark ? AppColors.darkSurfaceVariant : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        centerTitle: false,
        title: Row(
          children: [
            // AI avatar with glow
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/saberplus.png',
                height: 28,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.auto_awesome,
                        size: 18, color: AppColors.textSecondary),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Saber+ IA',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                Text('En línea',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    )),
              ],
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: AppColors.border, height: 1.0),
        ),
      ),
      body: Column(
        children: [
          // ── Messages ──
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount:
                  _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isLoading) {
                  return _buildTypingIndicator(assistantBubbleColor);
                }

                final msg = _messages[index];
                final isUser = msg['role'] == 'user';

                return _ChatBubble(
                  key: ValueKey('msg_$index'),
                  isUser: isUser,
                  child: isUser
                      ? Text(msg['text']!,
                          style: TextStyle(
                              color: AppColors.textOnPrimary, fontSize: 15))
                      : _buildMessageContent(msg['text']!),
                  assistantColor: assistantBubbleColor,
                );
              },
            ),
          ),

          // ── Quick Suggestions ──
          if (_messages.length <= 2 && !_isLoading)
            Container(
              height: 44,
              margin: const EdgeInsets.only(top: 4),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _quickSuggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  return ActionChip(
                    label: Text(
                      _quickSuggestions[i],
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      ),
                    ),
                    onPressed: () => _sendMessage(preset: _quickSuggestions[i]),
                    backgroundColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceClean,
                    side: BorderSide(
                      color: isDark ? AppColors.darkBorder : AppColors.border,
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                },
              ),
            ),

          // ── Input Bar ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: surfaceColor,
              border: Border(
                  top: BorderSide(
                      color: isDark ? AppColors.darkBorder : AppColors.border,
                      width: 1)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurfaceVariant
                            : AppColors.surfaceClean,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : AppColors.border,
                          width: 1.5,
                        ),
                      ),
                      child: TextField(
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: 'Pregúntale a Saber+...',
                          hintStyle: TextStyle(
                              color: AppColors.textDisabled, fontSize: 15),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          isDense: true,
                        ),
                        style: TextStyle(
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textSecondary,
                            fontSize: 15),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryLight]),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(Icons.auto_awesome,
                          color: AppColors.accent, size: 22),
                      onPressed: () => _sendMessage(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Premium Typing Indicator ──
  Widget _buildTypingIndicator(Color bubbleColor) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: _TypingDots(),
      ),
    );
  }
}

// ── Animated Chat Bubble ──
class _ChatBubble extends StatefulWidget {
  final bool isUser;
  final Widget child;
  final Color assistantColor;

  const _ChatBubble({
    super.key,
    required this.isUser,
    required this.child,
    required this.assistantColor,
  });

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: SlideTransition(
        position: Tween(
          begin: Offset(widget.isUser ? 0.15 : -0.15, 0),
          end: Offset.zero,
        ).animate(_animation),
        child: Align(
          alignment:
              widget.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85),
            decoration: BoxDecoration(
              color: widget.isUser ? null : widget.assistantColor,
              gradient: widget.isUser
                  ? const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight])
                  : null,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(widget.isUser ? 16 : 4),
                bottomRight: Radius.circular(widget.isUser ? 4 : 16),
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ── Premium Typing Dots (3 bouncing dots) ──
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Each dot bounces at a different phase
            final phase = (_controller.value * 3 - i) % 1.0;
            final bounce = phase < 0.5
                ? Curves.easeOut.transform(phase * 2)
                : Curves.easeIn.transform((1.0 - phase) * 2);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.translate(
                offset: Offset(0, -4 * bounce),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
