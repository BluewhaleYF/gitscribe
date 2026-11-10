/// The single source of truth for what the main content area shows.
///
/// The UI switches on this only — never on overlapping `showDialog` calls or
/// scattered booleans.
enum FlowStage {
  noRepo,
  repoLoaded,
  splittingAuto,
  splittingManual,
  generating,
  reviewing,
  submitting,
}

/// How a working tree is turned into commits.
enum CommitMode { single, multiAuto, multiManual }

/// One commit in a draft session: a set of files plus an editable message.
class DraftEntry {
  DraftEntry({
    required this.id,
    required this.files,
    required this.message,
    this.enabled = true,
  });

  /// Stable key for list rendering.
  final String id;

  /// Files belonging to this commit.
  final List<String> files;

  /// Editable commit message.
  String message;

  /// Whether this entry will be committed (multi mode can disable one).
  bool enabled;
}

/// The normalized result of any commit mode (single / multiAuto / multiManual).
///
/// Reviewing and committing only consume a [DraftSession]; there is no
/// per-mode UI.
class DraftSession {
  DraftSession({required this.mode, required this.entries});

  final CommitMode mode;
  final List<DraftEntry> entries;
}
