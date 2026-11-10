import 'dart:convert';
import 'dart:io';

import 'ai_service.dart';

/// Persisted user settings.
class AppSettings {
  AppSettings({this.lastRepoPath, this.localeCode, this.ai = const AiConfig()});

  final String? lastRepoPath;
  final String? localeCode;
  final AiConfig ai;

  AppSettings copyWith({String? lastRepoPath, String? localeCode, AiConfig? ai}) =>
      AppSettings(
        lastRepoPath: lastRepoPath ?? this.lastRepoPath,
        localeCode: localeCode ?? this.localeCode,
        ai: ai ?? this.ai,
      );

  Map<String, dynamic> toJson() => {
        if (lastRepoPath != null && lastRepoPath!.isNotEmpty)
          'lastRepoPath': lastRepoPath,
        if (localeCode != null && localeCode!.isNotEmpty)
          'localeCode': localeCode,
        'ai': ai.toJson(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        lastRepoPath: json['lastRepoPath'] as String?,
        localeCode: json['localeCode'] as String?,
        ai: AiConfig.fromJson(
          (json['ai'] as Map<String, dynamic>?) ?? const {},
        ),
      );
}

/// Reads and writes [AppSettings] to a JSON file in Application Support.
class AppConfigStore {
  AppConfigStore({String? filePath}) : _filePath = filePath ?? _defaultPath();

  final String _filePath;

  static String _defaultPath() {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return '$home/Library/Application Support/GitScribe/config.json';
  }

  AppSettings load() {
    try {
      final file = File(_filePath);
      if (!file.existsSync()) return AppSettings();
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) return AppSettings();
      return AppSettings.fromJson(decoded);
    } catch (_) {
      return AppSettings();
    }
  }

  void save(AppSettings settings) {
    try {
      final file = File(_filePath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      );
    } catch (_) {
      // Settings persistence is best-effort and must never crash the app.
    }
  }
}
