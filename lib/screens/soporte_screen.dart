// lib/screens/soporte_screen.dart
// SaberPlus — Ayuda y Soporte (quejas/sugerencias) v1.7.0
//
// - Formulario para enviar queja / sugerencia / bug / otro
// - Historial "Mis envíos" con estado y respuesta del equipo
// - Consume crear_queja.php y mis_quejas.php (JWT obligatorio)

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../config/env.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/app_logger.dart';
import '../services/auth_service.dart';

class SoporteScreen extends StatefulWidget {
  const SoporteScreen({super.key});

  @override
  State<SoporteScreen> createState() => _SoporteScreenState();
}

class _SoporteScreenState extends State<SoporteScreen> {
  final TextEditingController _mensajeController = TextEditingController();
  String _tipoSeleccionado = 'sugerencia';
  bool _enviando = false;
  bool _cargandoHistorial = true;

  List<Map<String, dynamic>> _misEnvios = [];

  static const List<Map<String, dynamic>> _tipos = [
    {'valor': 'sugerencia', 'label': 'Sugerencia', 'icon': Icons.lightbulb_rounded},
    {'valor': 'queja', 'label': 'Queja', 'icon': Icons.sentiment_dissatisfied_rounded},
    {'valor': 'bug', 'label': 'Error/Bug', 'icon': Icons.bug_report_rounded},
    {'valor': 'otro', 'label': 'Otro', 'icon': Icons.chat_bubble_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _mensajeController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // API
  // ─────────────────────────────────────────────

  Map<String, String> get _headers {
    final token = context.read<AuthService>().token;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _cargarHistorial() async {
    setState(() => _cargandoHistorial = true);
    try {
      final response = await http
          .post(
            Uri.parse('${Env.apiBaseUrl}/mis_quejas.php'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final body = _limpiarJson(response.body);
        final data = jsonDecode(body);
        if (data['status'] == 'ok' && data['quejas'] is List) {
          _misEnvios = List<Map<String, dynamic>>.from(data['quejas']);
        }
      }
    } catch (e) {
      AppLogger.e('Soporte: error cargando historial', e);
    } finally {
      if (mounted) setState(() => _cargandoHistorial = false);
    }
  }

  Future<void> _enviar() async {
    final mensaje = _mensajeController.text.trim();
    if (mensaje.length < 10) {
      _snack('Cuéntanos un poco más (mínimo 10 caracteres) 🙂');
      return;
    }
    if (_enviando) return;

    setState(() => _enviando = true);
    try {
      final response = await http
          .post(
            Uri.parse('${Env.apiBaseUrl}/crear_queja.php'),
            headers: _headers,
            body: jsonEncode({
              'tipo': _tipoSeleccionado,
              'asunto': _asuntoDe(mensaje),
              'mensaje': mensaje,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final body = _limpiarJson(response.body);
        final data = jsonDecode(body);
        if (data['status'] == 'ok') {
          _mensajeController.clear();
          await _cargarHistorial();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['msg'] ??
                    '¡Gracias por escribirnos! Tu mensaje llegó al equipo.'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
        _snack(data['msg'] ?? 'No pudimos enviar tu mensaje.');
      } else if (response.statusCode == 429) {
        final data = jsonDecode(_limpiarJson(response.body));
        _snack(data['msg'] ?? 'Ya enviaste un mensaje hace poco.');
      } else {
        _snack('No pudimos enviar tu mensaje. Intenta de nuevo.');
      }
    } catch (e) {
      AppLogger.e('Soporte: error enviando', e);
      _snack('Error de conexión. Revisa tu internet.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String _asuntoDe(String mensaje) {
    final primera = mensaje.split(RegExp(r'[.!?\n]')).first.trim();
    if (primera.isEmpty) return '';
    return primera.length > 60 ? primera.substring(0, 60) : primera;
  }

  String _limpiarJson(String raw) {
    if (raw.startsWith('\uFEFF')) raw = raw.substring(1);
    raw = raw.trim();
    final i = raw.indexOf('{');
    if (i > 0) raw = raw.substring(i);
    return raw;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBackground : AppColors.background;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textColor =
        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final subColor =
        isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        title: Text('Ayuda y Soporte',
            style: TextStyle(
                color: textColor, fontWeight: FontWeight.w800, fontSize: 18)),
        iconTheme: IconThemeData(color: textColor),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: AppColors.border, height: 1.0),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _cargarHistorial,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // ── Hero ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.support_agent_rounded,
                        color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Estamos para ayudarte',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cuéntanos qué pasa, qué se te ocurre o qué falla. Leemos TODOS los mensajes y respondemos aquí mismo.',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.white.withOpacity(0.9),
                              height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Selector de tipo ──
            Text('¿Qué quieres enviarnos?',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tipos.map((t) {
                final seleccionado = _tipoSeleccionado == t['valor'];
                return ChoiceChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t['icon'] as IconData,
                          size: 16,
                          color: seleccionado
                              ? Colors.white
                              : (isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary)),
                      const SizedBox(width: 6),
                      Text(t['label'] as String),
                    ],
                  ),
                  selected: seleccionado,
                  onSelected: (_) =>
                      setState(() => _tipoSeleccionado = t['valor'] as String),
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: seleccionado
                        ? Colors.white
                        : (isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.textSecondary),
                  ),
                  backgroundColor:
                      isDark ? AppColors.darkSurfaceVariant : AppColors.surface,
                  side: BorderSide(
                      color: seleccionado
                          ? AppColors.primary
                          : (isDark ? AppColors.darkBorder : AppColors.border),
                      width: 1.2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // ── Mensaje ──
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.border,
                    width: 1.5),
              ),
              child: TextField(
                controller: _mensajeController,
                maxLines: 5,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: textColor, fontSize: 14.5, height: 1.5),
                decoration: InputDecoration(
                  hintText:
                      'Escribe tu sugerencia, queja o describe el error que encontraste...',
                  hintStyle: TextStyle(
                      color: AppColors.textDisabled,
                      fontSize: 13.5,
                      height: 1.5),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Botón enviar ──
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _enviando ? null : _enviar,
                icon: _enviando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(_enviando ? 'Enviando...' : 'Enviar al equipo',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ── Mis envíos ──
            Row(
              children: [
                Icon(Icons.history_rounded, size: 18, color: subColor),
                const SizedBox(width: 6),
                Text('Mis envíos',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: textColor)),
              ],
            ),
            const SizedBox(height: 10),

            if (_cargandoHistorial)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary)),
              )
            else if (_misEnvios.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.border),
                ),
                child: Column(
                  children: [
                    Icon(Icons.mark_email_read_outlined,
                        size: 40, color: AppColors.textDisabled),
                    const SizedBox(height: 10),
                    Text(
                      'Aún no has enviado mensajes.\n¡Tu primera sugerencia es bienvenida! 🚀',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13, color: subColor, height: 1.5),
                    ),
                  ],
                ),
              )
            else
              ..._misEnvios.map(_buildEnvioCard),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildEnvioCard(Map<String, dynamic> envio) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.surface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppColors.darkTextTertiary : AppColors.textTertiary;

    final estado = envio['estado'] as String? ?? 'nuevo';
    Color estadoColor;
    IconData estadoIcon;
    switch (estado) {
      case 'resuelto':
        estadoColor = AppColors.success;
        estadoIcon = Icons.check_circle_rounded;
        break;
      case 'en_proceso':
        estadoColor = AppColors.warning;
        estadoIcon = Icons.hourglass_top_rounded;
        break;
      case 'descartado':
        estadoColor = AppColors.textDisabled;
        estadoIcon = Icons.archive_rounded;
        break;
      default:
        estadoColor = AppColors.primary;
        estadoIcon = Icons.mark_email_unread_rounded;
    }

    final respuesta = envio['respuesta_admin'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: estadoColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(estadoIcon, size: 13, color: estadoColor),
                    const SizedBox(width: 4),
                    Text(
                      envio['estado_texto'] as String? ?? estado,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: estadoColor),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _formatearFecha(envio['creado_en'] as String? ?? ''),
                style: TextStyle(fontSize: 11, color: subColor),
              ),
            ],
          ),
          if ((envio['asunto'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(envio['asunto'] as String,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
          ],
          const SizedBox(height: 6),
          Text(
            envio['mensaje'] as String? ?? '',
            style: TextStyle(
                fontSize: 13, color: subColor, height: 1.5),
          ),
          if (respuesta != null && respuesta.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.support_agent_rounded,
                          size: 15, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text('Respuesta del equipo SaberPlus',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(respuesta,
                      style: TextStyle(
                          fontSize: 13,
                          color: textColor,
                          height: 1.5)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatearFecha(String fechaSql) {
    try {
      final dt = DateTime.parse(fechaSql);
      final meses = [
        'ene', 'feb', 'mar', 'abr', 'may', 'jun',
        'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
      ];
      return '${dt.day} ${meses[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return fechaSql;
    }
  }
}
