import 'dart:convert';
import 'dart:io';

import 'draft_models.dart';
import 'message_generator.dart';
import 'prompts.dart';

/// Configuration for an OpenAI-compatible chat completions endpoint.
class AiConfig {
  const AiConfig({
    this.baseUrl = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.model = 'gpt-4o-mini',
    this.maxDiffChars = 12000,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxDiffChars;

  bool get isConfigured => apiKey.trim().isNotEmpty;

  AiConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    int? maxDiffChars,
  }) {
    return AiConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      maxDiffChars: maxDiffChars ?? this.maxDiffChars,
    );
  }

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'maxDiffChars': maxDiffChars,
      };

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
        baseUrl: (json['baseUrl'] as String?) ?? 'https://api.openai.com/v1',
        apiKey: (json['apiKey'] as String?) ?? '',
        model: (json['model'] as String?) ?? 'gpt-4o-mini',
        maxDiffChars: (json['maxDiffChars'] as num?)?.toInt() ?? 12000,
      );
}

/// Client for LLM calls over an OpenAI-compatible API.
class AiService {
  /// Generates a single commit message for [files], honoring [opt].
  Future<String> draftMessage({
    required AiConfig config,
    required String diff,
    required List<String> files,
    required CommitStyle opt,
    String? conventionText,
  }) async {
    final text = await _complete(config, [
      {'role': 'system', 'content': draftSystemPrompt},
      {
        'role': 'user',
        'content': buildDraftUserPrompt(
          diff: diff,
          files: files,
          opt: opt,
          conventionText: conventionText,
        ),
      },
    ]);
    return text;
  }

  /// Splits a diff into logical commits. Returns the parsed, validated
  /// [DraftEntry]s (at least one; callers handle the single-entry degradation).
  Future<List<DraftEntry>> split({
    required AiConfig config,
    required String diff,
    required List<String> files,
    required CommitStyle opt,
    String? conventionText,
  }) async {
    final text = await _complete(config, [
      {'role': 'system', 'content': splitSystemPrompt},
      {
        'role': 'user',
        'content': buildSplitUserPrompt(
          diff: diff,
          files: files,
          opt: opt,
          conventionText: conventionText,
        ),
      },
    ]);
    return parseSplitResponse(text, files);
  }

  /// Rewrites [currentMessage] per [intent] (simplify or elaborate).
  Future<String> rewrite({
    required AiConfig config,
    required String currentMessage,
    required RewriteIntent intent,
    String? scopedDiff,
    required CommitStyle opt,
  }) async {
    return _complete(config, [
      {'role': 'system', 'content': rewriteSystemPrompt},
      {
        'role': 'user',
        'content': buildRewriteUserPrompt(
          currentMessage: currentMessage,
          intent: intent,
          scopedDiff: scopedDiff,
          opt: opt,
        ),
      },
    ]);
  }

  /// Parses and validates an LLM split response.
  ///
  /// - Strips a markdown code fence when present.
  /// - Throws [AiException] with code `splitFormat` on invalid JSON/shape and
  ///   `splitEmpty` when there are no commits.
  /// - Drops files not present in [validFiles], and drops commits whose files
  ///   all get discarded.
  static List<DraftEntry> parseSplitResponse(
    String raw,
    List<String> validFiles,
  ) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      final nl = text.indexOf('\n');
      if (nl != -1) text = text.substring(nl + 1);
      final fence = text.lastIndexOf('```');
      if (fence != -1) text = text.substring(0, fence);
      text = text.trim();
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const AiException('', code: 'splitFormat');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AiException('', code: 'splitFormat');
    }

    final commits = decoded['commits'];
    if (commits is! List || commits.isEmpty) {
      throw const AiException('', code: 'splitEmpty');
    }

    final validSet = validFiles.toSet();
    final entries = <DraftEntry>[];
    var i = 0;
    for (final item in commits) {
      if (item is! Map<String, dynamic>) continue;
      final message = (item['message'] as String?)?.trim() ?? '';
      if (message.isEmpty) continue;
      final rawFiles = item['files'];
      final files = <String>[];
      if (rawFiles is List) {
        for (final f in rawFiles) {
          if (f is String && validSet.contains(f)) files.add(f);
        }
      }
      if (files.isEmpty) continue;
      entries.add(DraftEntry(id: 'split-${i++}', files: files, message: message));
    }

    if (entries.isEmpty) {
      throw const AiException('', code: 'splitEmpty');
    }
    return entries;
  }

  Future<String> _complete(
    AiConfig config,
    List<Map<String, String>> messages,
  ) async {
    final base = config.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/chat/completions');

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 60);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${config.apiKey.trim()}',
      );
      request.write(jsonEncode({
        'model': config.model,
        'temperature': 0.2,
        'messages': messages,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiException('HTTP ${response.statusCode}: $body');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const AiException('Unexpected response shape from the API.');
      }
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        throw const AiException('The model returned no completion.');
      }
      final message = (choices.first as Map<String, dynamic>)['message'];
      final content = (message as Map<String, dynamic>)['content'];
      final text = content is String ? content.trim() : '';
      if (text.isEmpty) {
        throw const AiException('The model returned an empty completion.');
      }
      return text;
    } on AiException {
      rethrow;
    } catch (e) {
      throw AiException('Request failed: $e');
    } finally {
      client.close(force: true);
    }
  }
}

class AiException implements Exception {
  const AiException(this.message, {this.code = 'generic'});

  final String message;

  /// Stable machine-readable code: `generic`, `splitFormat`, `splitEmpty`, …
  final String code;

  @override
  String toString() => message;
}
