// Data models for GitScribe.

/// High-level kind of change for a single path, derived from `git status`.
enum ChangeType {
  added,
  modified,
  deleted,
  renamed,
  copied,
  untracked,
  unknown,
}

/// A single entry parsed from `git status --porcelain=v1 -z`.
class FileChange {
  const FileChange({
    required this.indexStatus,
    required this.workTreeStatus,
    required this.path,
    this.originalPath,
  });

  /// Status in the index (staged area) — a single char, or `' '` if none.
  final String indexStatus;

  /// Status in the working tree — a single char, or `' '` if none.
  final String workTreeStatus;

  /// The (destination) path of the change.
  final String path;

  /// The source path, set only for renames and copies.
  final String? originalPath;

  bool get isUntracked => indexStatus == '?' && workTreeStatus == '?';
  bool get isStaged => indexStatus != ' ' && indexStatus != '?';
  bool get isUnstaged => workTreeStatus != ' ' && workTreeStatus != '?';

  ChangeType get type {
    if (isUntracked) return ChangeType.untracked;
    final s = indexStatus != ' ' ? indexStatus : workTreeStatus;
    switch (s) {
      case 'A':
        return ChangeType.added;
      case 'M':
        return ChangeType.modified;
      case 'D':
        return ChangeType.deleted;
      case 'R':
        return ChangeType.renamed;
      case 'C':
        return ChangeType.copied;
      default:
        return ChangeType.unknown;
    }
  }
}

/// Summary information about a loaded repository.
class RepoInfo {
  const RepoInfo({required this.root, required this.branch});

  final String root;
  final String branch;

  String get name {
    final trimmed = root.replaceAll(RegExp(r'[/\\]+$'), '');
    final i = trimmed.lastIndexOf(RegExp(r'[/\\]'));
    return i == -1 ? trimmed : trimmed.substring(i + 1);
  }
}

/// One commit to be created: a message plus the exact paths to stage.
class CommitUnit {
  const CommitUnit({required this.message, required this.paths});

  final String message;
  final List<String> paths;
}

/// The result of the two-stage commit flow: one or more [CommitUnit]s.
class CommitPlan {
  const CommitPlan(this.units);

  final List<CommitUnit> units;

  bool get isSplit => units.length > 1;
}
