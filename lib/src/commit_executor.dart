import 'draft_models.dart';
import 'git_service.dart';

/// Executes a [DraftSession] by committing its enabled entries in order.
class CommitExecutor {
  const CommitExecutor();

  /// Commits enabled entries one by one with `--only`. On the first failure,
  /// throws [CommitFailedException] and leaves [session] holding the remaining
  /// (uncommitted) entries. Returns the number of commits created.
  Future<int> execute({
    required String repoPath,
    required DraftSession session,
    required GitService git,
    required Set<String> untrackedPaths,
  }) async {
    var committed = 0;
    var n = 0;
    for (final entry in List<DraftEntry>.of(session.entries)) {
      if (!entry.enabled) continue;
      n++;
      final untracked = entry.files.where(untrackedPaths.contains).toList();
      final result = await git.commitOnly(
        repoPath,
        entry.message.trim(),
        entry.files,
        untracked: untracked,
      );
      if (!result.success) {
        throw CommitFailedException(n, result.stderr);
      }
      session.entries.remove(entry);
      committed++;
    }
    return committed;
  }
}

class CommitFailedException implements Exception {
  const CommitFailedException(this.index, this.stderr);

  /// 1-based index of the failed commit.
  final int index;

  final String stderr;
}
