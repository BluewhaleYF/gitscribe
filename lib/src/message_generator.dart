import 'package:path/path.dart' as p;

import 'models.dart';

/// Options controlling how a commit message is rendered.
class CommitStyle {
  const CommitStyle({
    this.language = 'en',
    this.useGitmoji = false,
    this.useConventionalCommit = true,
  });

  /// Message language: `en` or `zh`. Independent of the app UI language.
  final String language;

  /// Prepend a gitmoji emoji to the subject when true.
  final bool useGitmoji;

  /// Use the `type(scope): subject` prefix when true.
  final bool useConventionalCommit;
}

enum _Category { docs, test, build, style, code }

/// Deterministic, offline commit-message drafter.
///
/// Produces a Conventional Commits message (`type(scope): subject` with a short
/// body) from the set of changed files, optionally localized, with gitmoji,
/// and with or without the conventional prefix.
class LocalMessageGenerator {
  const LocalMessageGenerator();

  String generate(
    List<FileChange> changes, {
    CommitStyle style = const CommitStyle(),
  }) {
    if (changes.isEmpty) {
      return style.useConventionalCommit ? 'chore: no changes' : 'no changes';
    }

    final byCategory = _categorize(changes);
    final type = _pickType(changes, byCategory);
    final scope = _pickScope(changes);
    final noun = _nounFrom(_primaryChange(changes));
    final onlyDeletions = changes.every((c) => c.type == ChangeType.deleted);
    final subject = _subject(type, noun, style.language, onlyDeletions);

    var header = style.useConventionalCommit
        ? (scope.isEmpty ? '$type: $subject' : '$type($scope): $subject')
        : subject;
    if (style.useGitmoji) header = '${_gitmoji(type)} $header';

    final body = _summarize(changes, style.language);
    return body.isEmpty ? header : '$header\n\n$body';
  }

  /// Groups changes into logical units for split commits, keyed by top-level
  /// directory (root-level files share a `root` group).
  List<List<FileChange>> groupChanges(List<FileChange> changes) {
    final map = <String, List<FileChange>>{};
    for (final c in changes) {
      final top = c.path.contains('/') ? c.path.split('/').first : 'root';
      map.putIfAbsent(top, () => <FileChange>[]).add(c);
    }
    final keys = map.keys.toList()..sort();
    return [for (final key in keys) map[key]!];
  }

  Map<_Category, List<FileChange>> _categorize(List<FileChange> changes) {
    final map = <_Category, List<FileChange>>{};
    for (final c in changes) {
      map.putIfAbsent(_categoryOf(c.path), () => <FileChange>[]).add(c);
    }
    return map;
  }

  static _Category _categoryOf(String path) {
    final lower = path.toLowerCase();
    final base = p.basename(path).toLowerCase();

    final isDocs = lower.startsWith('docs/') ||
        lower.startsWith('doc/') ||
        base.endsWith('.md') ||
        base.endsWith('.rst') ||
        base.endsWith('.txt') ||
        base == 'readme' ||
        base == 'readme.md' ||
        base == 'changelog' ||
        base == 'changelog.md' ||
        base == 'contributing.md' ||
        base == 'code_of_conduct.md' ||
        base == 'license';
    if (isDocs) return _Category.docs;

    final isTest = lower.startsWith('test/') ||
        lower.startsWith('tests/') ||
        lower.startsWith('spec/') ||
        lower.contains('/test/') ||
        lower.contains('/tests/') ||
        lower.contains('/spec/') ||
        RegExp(r'(_test|\.test|_spec|\.spec)\.').hasMatch(base);
    if (isTest) return _Category.test;

    final isBuild = lower.startsWith('.github/') ||
        lower.startsWith('.circleci/') ||
        base == 'makefile' ||
        base == 'jenkinsfile' ||
        base == 'dockerfile' ||
        base == 'docker-compose.yml' ||
        base == 'docker-compose.yaml' ||
        base == 'podfile' ||
        base == 'gemfile' ||
        base == 'pubspec.yaml' ||
        base == 'pubspec.lock' ||
        base == 'package.json' ||
        base == 'package-lock.json' ||
        base == 'cargo.toml' ||
        base == 'build.gradle' ||
        base == 'settings.gradle' ||
        base.endsWith('.xcconfig') ||
        ((base.endsWith('.yml') || base.endsWith('.yaml')) &&
            (lower.contains('ci') || lower.contains('workflow')));
    if (isBuild) return _Category.build;

    final isStyle = base.endsWith('.css') ||
        base.endsWith('.scss') ||
        base.endsWith('.less') ||
        base.endsWith('.html') ||
        base.endsWith('.svg');
    if (isStyle) return _Category.style;

    return _Category.code;
  }

  String _pickType(
    List<FileChange> changes,
    Map<_Category, List<FileChange>> byCategory,
  ) {
    final code = byCategory[_Category.code] ?? const <FileChange>[];
    final docs = byCategory[_Category.docs] ?? const <FileChange>[];
    final tests = byCategory[_Category.test] ?? const <FileChange>[];
    final build = byCategory[_Category.build] ?? const <FileChange>[];
    final style = byCategory[_Category.style] ?? const <FileChange>[];

    if (code.isEmpty) {
      if (docs.isNotEmpty && tests.isEmpty && build.isEmpty && style.isEmpty) {
        return 'docs';
      }
      if (tests.isNotEmpty && docs.isEmpty && build.isEmpty && style.isEmpty) {
        return 'test';
      }
      if (build.isNotEmpty && docs.isEmpty && tests.isEmpty && style.isEmpty) {
        return 'chore';
      }
      if (style.length == changes.length) return 'style';
      return 'chore';
    }

    final hasAddedCode = code.any(
      (c) => c.type == ChangeType.added || c.type == ChangeType.untracked,
    );
    if (hasAddedCode) return 'feat';

    final onlyDeletions = changes.every((c) => c.type == ChangeType.deleted);
    if (onlyDeletions) return 'chore';

    if (code.length >= 3) return 'refactor';
    return 'fix';
  }

  String _pickScope(List<FileChange> changes) {
    final topLevel = <String, int>{};
    for (final c in changes) {
      if (c.path.contains('/')) {
        final first = c.path.split('/').first;
        topLevel[first] = (topLevel[first] ?? 0) + 1;
      }
    }
    if (topLevel.isEmpty) return '';
    var best = '';
    var bestCount = -1;
    topLevel.forEach((dir, count) {
      if (count > bestCount) {
        best = dir;
        bestCount = count;
      }
    });
    return best;
  }

  FileChange _primaryChange(List<FileChange> changes) {
    FileChange? added;
    FileChange? modified;
    FileChange? first;
    for (final c in changes) {
      first ??= c;
      if (c.type == ChangeType.added || c.type == ChangeType.untracked) {
        added ??= c;
      } else if (c.type == ChangeType.modified) {
        modified ??= c;
      }
    }
    return added ?? modified ?? first!;
  }

  String _nounFrom(FileChange change) {
    final path = change.originalPath ?? change.path;
    return humanize(p.basenameWithoutExtension(path));
  }

  String _subject(String type, String noun, String lang, bool onlyDeletions) {
    final zh = lang == 'zh';
    if (type == 'chore' && onlyDeletions) {
      return zh ? '移除 $noun' : 'remove $noun';
    }
    switch (type) {
      case 'feat':
        return zh ? '添加 $noun' : 'add $noun';
      case 'fix':
        return zh ? '修复 $noun' : 'fix $noun';
      case 'refactor':
        return zh ? '重构 $noun' : 'refactor $noun';
      case 'docs':
        return zh ? '更新 $noun 文档' : 'update $noun documentation';
      case 'test':
        return zh ? '补充 $noun 测试' : 'add tests for $noun';
      case 'style':
        return zh ? '整理 $noun 格式' : 'tidy $noun formatting';
      default:
        return zh ? '更新 $noun' : 'update $noun';
    }
  }

  String _bulletVerb(ChangeType type, String lang) {
    final zh = lang == 'zh';
    switch (type) {
      case ChangeType.added:
      case ChangeType.untracked:
        return zh ? '新增' : 'add';
      case ChangeType.deleted:
        return zh ? '删除' : 'delete';
      case ChangeType.renamed:
        return zh ? '重命名' : 'rename';
      case ChangeType.copied:
        return zh ? '复制' : 'copy';
      default:
        return zh ? '修改' : 'modify';
    }
  }

  static String _gitmoji(String? type) {
    switch (type) {
      case 'feat':
        return '✨';
      case 'fix':
        return '🐛';
      case 'docs':
        return '📝';
      case 'style':
        return '💄';
      case 'refactor':
        return '♻️';
      case 'test':
        return '✅';
      case 'build':
        return '📦';
      case 'perf':
        return '⚡';
      case 'ci':
        return '👷';
      default:
        return '🔧';
    }
  }

  List<String> _summarize(List<FileChange> changes, String lang) {
    final lines = <String>[];
    for (final c in changes) {
      final verb = _bulletVerb(c.type, lang);
      if (c.type == ChangeType.renamed || c.type == ChangeType.copied) {
        lines.add('- $verb: ${c.originalPath} -> ${c.path}');
      } else {
        lines.add('- $verb: ${c.path}');
      }
    }
    if (lines.length > 12) {
      final shown = lines.sublist(0, 12);
      final remaining = lines.length - 12;
      final more = lang == 'zh' ? '… 及另外 $remaining 个文件' : '… and $remaining more file(s)';
      return [...shown, '- $more'];
    }
    return lines;
  }

  /// Converts an identifier like `login_form` or `LoginForm` into "login form".
  static String humanize(String identifier) {
    if (identifier.isEmpty) return 'files';
    final words = identifier
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        )
        .replaceAll(RegExp(r'[_\-.]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    return words.isEmpty ? 'files' : words;
  }

  // ---- Local message transforms (review quick buttons) ----------------

  /// Common gitmoji emojis, matched by prefix (so CJK text is never confused
  /// with an emoji).
  static const List<String> _gitmojiEmojis = [
    '✨', '🐛', '📝', '💄', '♻️', '✅', '📦', '⚡', '👷', '🔧',
    '🎨', '🚀', '🔥', '🚚', '🎉', '🌐', '💥', '📌', '🔒', '🧪',
  ];

  static final RegExp _conventionalPrefix = RegExp(
    r'^\w+(?:\([^)]*\))?!?:\s*',
  );

  /// Whether [message] already starts with a gitmoji emoji.
  static bool hasGitmoji(String message) {
    final t = message.trimLeft();
    return _gitmojiEmojis.any((e) => t.startsWith(e));
  }

  /// Strips a leading gitmoji emoji (and following space) when present.
  static String removeGitmoji(String message) {
    final t = message.trimLeft();
    for (final e in _gitmojiEmojis) {
      if (t.startsWith(e)) {
        return t.substring(e.length).trimLeft();
      }
    }
    return message;
  }

  /// Prepends a gitmoji (mapped from the conventional type) when absent.
  static String addGitmoji(String message) {
    if (hasGitmoji(message)) return message;
    return '${_gitmoji(extractType(message))} ${message.trimLeft()}';
  }

  /// Splits [message] into `(leadingEmoji, rest)`, where `rest` is trimmed.
  static (String, String) _splitLeadingGitmoji(String message) {
    final t = message.trimLeft();
    for (final e in _gitmojiEmojis) {
      if (t.startsWith(e)) {
        return (t.substring(0, e.length), t.substring(e.length).trimLeft());
      }
    }
    return ('', t);
  }

  /// Extracts the Conventional Commits type token (`feat`, `fix`, …) from the
  /// subject (skipping any leading gitmoji), or `null` when there is no prefix.
  static String? extractType(String message) {
    final (_, rest) = _splitLeadingGitmoji(message);
    final m = RegExp(r'^(\w+)(?:\([^)]*\))?!?:').firstMatch(rest);
    return m?.group(1);
  }

  /// Removes the conventional `type(scope)!:` prefix, keeping any leading
  /// gitmoji in place.
  static String removeConventionalPrefix(String message) {
    final (emoji, rest) = _splitLeadingGitmoji(message);
    final stripped = rest.replaceFirst(_conventionalPrefix, '');
    if (emoji.isEmpty) return stripped;
    return stripped.isEmpty ? emoji : '$emoji $stripped';
  }

  /// Prepends `type: ` (after any leading gitmoji) when there is no
  /// conventional prefix yet.
  static String addConventionalPrefix(String message, String type) {
    if (extractType(message) != null) return message;
    final (emoji, rest) = _splitLeadingGitmoji(message);
    final withPrefix = '$type: $rest';
    return emoji.isEmpty ? withPrefix : '$emoji $withPrefix';
  }

  /// Infers a Conventional Commits type from a set of file paths.
  static String inferTypeFromPaths(List<String> paths) {
    var docs = 0, test = 0, build = 0, code = 0;
    for (final path in paths) {
      switch (_categoryOf(path)) {
        case _Category.docs:
          docs++;
        case _Category.test:
          test++;
        case _Category.build:
          build++;
        case _Category.style:
        case _Category.code:
          code++;
      }
    }
    if (code == 0) {
      if (docs > 0 && test == 0 && build == 0) return 'docs';
      if (test > 0 && docs == 0 && build == 0) return 'test';
      return 'chore';
    }
    return 'feat';
  }
}
