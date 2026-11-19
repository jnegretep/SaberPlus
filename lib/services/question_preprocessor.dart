// lib/services/question_preprocessor.dart
// Saber+ — Orquestador de pre-procesamiento de preguntas a AST.
//
// FIX M2 (2026-11-13):
//   Env.apiBaseUrl se lee UNA sola vez en el main thread y se pasa como
//   String plano a parseQuestionBlocks() y a QImage.smartProxy(). Antes
//   se leía dentro del isolate vía QImage.smartProxy → dotenv.env, que
//   lanza NotInitializedError en isolates porque DotEnv no está
//   inicializado allí. Resultado previo: 100% de los lotes con imágenes
//   fallaban y caían a parseo síncrono en main thread.

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../config/env.dart';
import '../models/quiz_block.dart';
import '../models/quiz_question.dart';
import '../parsers/quiz_block_parser.dart';

class QuestionPreprocessor {
  final Map<int, QuestionBlocks> _cache = {};
  int? _currentAttemptId;
  final Set<int> _inProgress = {};
  Future<void>? _backgroundTask;

  /// API base URL resuelta una sola vez en main thread. Ver FIX M2.
  String? _apiBaseUrl;

  QuestionPreprocessor();

  /// Lazy getter: lee `Env.apiBaseUrl` en main thread la primera vez.
  String get _resolvedApiBaseUrl {
    if (_apiBaseUrl == null) {
      _apiBaseUrl = _readApiBaseUrl();
    }
    return _apiBaseUrl!;
  }

  /// Lee `Env.apiBaseUrl` en main thread con fallback seguro.
  static String _readApiBaseUrl() {
    try {
      return Env.apiBaseUrl;
    } catch (e) {
      debugPrint('[QuestionPreprocessor] Env.apiBaseUrl no disponible: $e');
      return '';
    }
  }

  Future<void> preprocessAll(
    List<QuizQuestion> questions,
    int attemptId,
  ) async {
    _currentAttemptId = attemptId;
    _cache.clear();
    _inProgress.clear();

    if (questions.isEmpty) return;

    // Resolver apiBaseUrl AHORA, en main thread. El isolate no puede.
    final apiBaseUrl = _resolvedApiBaseUrl;

    // ── Lote 1: pregunta 1 síncrona (la primera en mostrarse) ──
    try {
      final first = questions.first;
      _cache[first.slot] = parseQuestionBlocks(first, apiBaseUrl: apiBaseUrl);
      _inProgress.add(first.slot);
    } catch (e) {
      debugPrint('[QuestionPreprocessor] Error parseando pregunta 1: $e');
    }

    // ── Lote 2: preguntas 2..N en background (fire-and-forget) ──
    if (questions.length > 1) {
      final rest = questions.skip(1).toList(growable: false);
      _backgroundTask = _preprocessInBackground(rest, attemptId, apiBaseUrl);
    }
  }

  Future<void> _preprocessInBackground(
    List<QuizQuestion> questions,
    int attemptId,
    String apiBaseUrl,
  ) async {
    const batchSize = 10;

    for (int i = 0; i < questions.length; i += batchSize) {
      if (_currentAttemptId != attemptId) {
        debugPrint('[QuestionPreprocessor] Attempt cambió, abortando batch $i');
        return;
      }

      final batch = questions.sublist(
        i,
        (i + batchSize > questions.length) ? questions.length : i + batchSize,
      );

      try {
        // ✅ Pasar apiBaseUrl al isolate vía _BatchInput.
        final results = await compute(
          _parseBatch,
          _BatchInput(questions: batch, apiBaseUrl: apiBaseUrl),
        );

        if (_currentAttemptId != attemptId) {
          debugPrint('[QuestionPreprocessor] Attempt cambió tras compute, descartando');
          return;
        }

        for (int j = 0; j < results.length; j++) {
          final slot = batch[j].slot;
          if (!_cache.containsKey(slot)) {
            _cache[slot] = results[j];
            _inProgress.add(slot);
          }
        }
      } catch (e, st) {
        debugPrint('[QuestionPreprocessor] Error en batch $i: $e\n$st');
        // Fallback: parsear síncrono en main thread (donde Env SÍ funciona).
        for (final q in batch) {
          if (!_cache.containsKey(q.slot)) {
            try {
              _cache[q.slot] = parseQuestionBlocks(q, apiBaseUrl: apiBaseUrl);
              _inProgress.add(q.slot);
            } catch (parseErr) {
              debugPrint('[QuestionPreprocessor] Fallback sync también falló: $parseErr');
            }
          }
        }
      }
    }
  }

  QuestionBlocks? getBlocks(int slot) => _cache[slot];

  QuestionBlocks getBlocksSync(QuizQuestion q) {
    return _cache[q.slot] ??=
        parseQuestionBlocks(q, apiBaseUrl: _resolvedApiBaseUrl);
  }

  bool isReady(int slot) => _cache.containsKey(slot);

  int get readyCount => _cache.length;

  void onPageChanged(QuizQuestion current, QuizQuestion? next) {
    final apiBaseUrl = _resolvedApiBaseUrl;

    if (!_cache.containsKey(current.slot)) {
      _cache[current.slot] = parseQuestionBlocks(current, apiBaseUrl: apiBaseUrl);
    }

    if (next != null && !_cache.containsKey(next.slot)) {
      scheduleMicrotask(() {
        if (!_cache.containsKey(next.slot)) {
          try {
            _cache[next.slot] = parseQuestionBlocks(next, apiBaseUrl: apiBaseUrl);
          } catch (e) {
            debugPrint('[QuestionPreprocessor] Error precargando siguiente: $e');
          }
        }
      });
    }
  }

  List<String> extractImageUrls(QuestionBlocks blocks) {
    final urls = <String>[];
    _collectImageUrls(blocks.questionText, urls);
    for (final opt in blocks.options) {
      _collectImageUrls(opt.label, urls);
    }
    return urls;
  }

  void _collectImageUrls(List<QuizBlock> blocks, List<String> urls) {
    for (final b in blocks) {
      switch (b) {
        case ImageBlock(:final proxiedSrc):
          if (proxiedSrc.isNotEmpty) urls.add(proxiedSrc);
        case TableBlock(:final cells):
          for (final row in cells) {
            for (final cell in row) {
              _collectImageUrls(cell, urls);
            }
          }
        case ListBlock(:final items):
          for (final item in items) {
            _collectImageUrls(item, urls);
          }
        default:
          break;
      }
    }
  }

  void dispose() {
    _currentAttemptId = null;
    _cache.clear();
    _inProgress.clear();
    _apiBaseUrl = null;
  }
}

// ═══════════════════════════════════════════════════════════════════
// Tipos para `compute()`
// ═══════════════════════════════════════════════════════════════════

/// Entrada serializable para el isolate: preguntas + apiBaseUrl.
/// Es una clase simple con campos primitivos/list, por lo que `compute()`
/// la puede enviar entre isolates sin problema.
class _BatchInput {
  final List<QuizQuestion> questions;
  final String apiBaseUrl;

  _BatchInput({required this.questions, required this.apiBaseUrl});
}

/// Parsea un lote de preguntas a AST. Invocada vía `compute()`.
List<QuestionBlocks> _parseBatch(_BatchInput input) {
  return input.questions
      .map((q) => parseQuestionBlocks(q, apiBaseUrl: input.apiBaseUrl))
      .toList(growable: false);
}