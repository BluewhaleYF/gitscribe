import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Thin wrapper around the **system** `git` CLI.
///
/// GitScribe never bundles its own git binary: every operation shells out to
/// the `git` found on `PATH` (the same one the system terminal uses). All
/// commands run with `git -C <repo>`, and git is forced into a non-interactive
/// mode so that an authentication problem fails immediately with a clear error
/// instead of prompting, hanging, or attempting to recover on its own.
class GitService {
  const GitService();

  /// Environment applied to every git invocation to disable interactive
  /// credential/passphrase prompting. A GUI app has no TTY, so prompting would
  /// hang; GitScribe intentionally surfaces the failure to the user instead.
  static const Map<String, String> _nonInteractiveGitEnv = {
    // Disable git's own terminal username/password prompts.
    'GIT_TERMINAL_PROMPT': '0',
    // Do not fall back to askpass helpers.
    'GIT_ASKPASS': '',
    'SSH_ASKPASS': '',
    // Non-interactive SSH: key auth still works, passphrase/password prompts fail.
    'GIT_SSH_COMMAND': 'ssh -oBatchMode=yes',
  };

  /// Detects whether [output] (typically git's stderr) reports an
  /// authentication or authorization failure. Used only to label the error for
  /// the user; GitScribe never retries or resolves credentials itself.
  static bool isAuthFailure(String output) {
    final s = output.toLowerCase();
    const patterns = [
      'authentication failed',
      'could not read username',
      'could not read password',
      'permission denied (publickey',
      'host key verification failed',
      'invalid username or password',
      'http basic: access denied',
      'requested url returned error: 401',
      'requested url returned error: 403',
      'remote: 401',
      'remote: 403',
      'access denied',
      'could not read from remote repository',
      'repository not found',
    ];
    return patterns.any(s.contains);
  }

  Future<ProcessResult> _run(String repoPath, List<String> args) async {
    try {
      return await Process.run(
        'git',
        ['-C', repoPath, ...args],
        environment: _nonInteractiveGitEnv,
      );
    } on ProcessException catch (e) {
      throw GitException('gitNotFound', e.message);
    }
  }

  /// Runs a git command feeding [stdinText] to stdin (used for `-F -`).
  Future<ProcessResult> _runWithStdin(
    String repoPath,
    List<String> args,
    String stdinText,
  ) async {
    final process = await Process.start(
      'git',
      ['-C', repoPath, ...args],
      environment: _nonInteractiveGitEnv,
    );
    process.stdin.write(stdinText);
    await process.stdin.close();
    final stdout = await process.stdout.transform(utf8.decoder).join();
    final stderr = await process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;
    return ProcessResult(process.pid, exitCode, stdout, stderr);
  }

  /// Returns the repository root for [path], or `null` when it is not inside a
  /// git repository.
  Future<String?> findRepoRoot(String path) async {
    final r = await _run(path, ['rev-parse', '--show-toplevel']);
    if (r.exitCode != 0) return null;
    final out = (r.stdout as String).trim();
    return out.isEmpty ? null : out;
  }

  Future<bool> hasCommits(String repoPath) async {
    final r = await _run(repoPath, ['rev-parse', '--verify', 'HEAD']);
    return r.exitCode == 0;
  }

  Future<RepoInfo> repoInfo(String repoPath) async {
    final branchR = await _run(repoPath, ['branch', '--show-current']);
    var branch = (branchR.stdout as String).trim();
    if (branch.isEmpty) {
      final headR = await _run(repoPath, ['rev-parse', '--short', 'HEAD']);
      branch = headR.exitCode == 0
          ? 'detached @ ${(headR.stdout as String).trim()}'
          : 'no commits yet';
    }
    return RepoInfo(root: repoPath, branch: branch);
  }

  Future<List<FileChange>> status(String repoPath) async {
    final r = await _run(repoPath, ['status', '--porcelain=v1', '-z']);
    if (r.exitCode != 0) {
      throw GitException('commandFailed', (r.stderr as String));
    }
    return parseStatusPorcelain(r.stdout as String);
  }

  /// Parses NUL-delimited `git status --porcelain=v1 -z` output into a list.
  ///
  /// Format (with `-z`): `XY <path>\0`, and for renames/copies
  /// `XY <source>\0<destination>\0`.
  List<FileChange> parseStatusPorcelain(String raw) {
    final parts = raw.split('\u0000');
    final changes = <FileChange>[];
    var i = 0;
    while (i < parts.length) {
      final entry = parts[i];
      if (entry.length < 4) {
        i++;
        continue;
      }
      final indexStatus = entry[0];
      final workTreeStatus = entry[1];
      final path = entry.substring(3);
      final hasTarget = indexStatus == 'R' || indexStatus == 'C';
      if (hasTarget && i + 1 < parts.length) {
        changes.add(FileChange(
          indexStatus: indexStatus,
          workTreeStatus: workTreeStatus,
          path: parts[i + 1],
          originalPath: path,
        ));
        i += 2;
      } else {
        changes.add(FileChange(
          indexStatus: indexStatus,
          workTreeStatus: workTreeStatus,
          path: path,
        ));
        i++;
      }
    }
    return changes;
  }

  /// Combined staged + unstaged diff against `HEAD` (or the index when the repo
  /// has no commits yet).
  Future<String> diff(String repoPath) async {
    final has = await hasCommits(repoPath);
    final r = await _run(repoPath, has ? ['diff', 'HEAD'] : ['diff', '--cached']);
    if (r.exitCode != 0) {
      throw GitException('commandFailed', (r.stderr as String));
    }
    return (r.stdout as String).trimRight();
  }

  /// Short `--stat` summary of the same diff.
  Future<String> diffStat(String repoPath) async {
    final has = await hasCommits(repoPath);
    final r = await _run(
      repoPath,
      has ? ['diff', 'HEAD', '--stat'] : ['diff', '--cached', '--stat'],
    );
    if (r.exitCode != 0) return '';
    return (r.stdout as String).trimRight();
  }

  /// Diff scoped to [paths] (against `HEAD`, or the index when there are no
  /// commits yet).
  Future<String> diffForPaths(String repoPath, List<String> paths) async {
    if (paths.isEmpty) return '';
    final has = await hasCommits(repoPath);
    final r = await _run(
      repoPath,
      has
          ? ['diff', 'HEAD', '--', ...paths]
          : ['diff', '--cached', '--', ...paths],
    );
    if (r.exitCode != 0) return '';
    return (r.stdout as String).trimRight();
  }

  /// Per-file added/deleted line counts from `git diff HEAD --numstat` (or the
  /// index when there are no commits). Untracked and binary files are absent.
  Future<Map<String, (int, int)>> diffNumstat(String repoPath) async {
    final has = await hasCommits(repoPath);
    final r = await _run(
      repoPath,
      has ? ['diff', 'HEAD', '--numstat'] : ['diff', '--cached', '--numstat'],
    );
    if (r.exitCode != 0) return const {};
    final map = <String, (int, int)>{};
    for (final line in (r.stdout as String).split('\n')) {
      final parts = line.split('\t');
      if (parts.length < 3) continue;
      final added = int.tryParse(parts[0]);
      final deleted = int.tryParse(parts[1]);
      if (added == null || deleted == null) continue;
      map[parts[2]] = (added, deleted);
    }
    return map;
  }

  /// Diff for a single file; falls back to an untracked-file diff (whole file
  /// as additions) when the path is not tracked yet.
  Future<String> diffForPath(String repoPath, String path) async {
    final has = await hasCommits(repoPath);
    final r = await _run(
      repoPath,
      has ? ['diff', 'HEAD', '--', path] : ['diff', '--cached', '--', path],
    );
    final diff = (r.stdout as String).trim();
    if (diff.isNotEmpty) return diff;
    final u = await _run(
      repoPath,
      ['diff', '--no-index', '--', '/dev/null', path],
    );
    return (u.stdout as String).trim();
  }

  Future<GitIdentity?> identity(String repoPath) async {
    final nameR = await _run(repoPath, ['config', 'user.name']);
    final emailR = await _run(repoPath, ['config', 'user.email']);
    final name = (nameR.stdout as String).trim();
    final email = (emailR.stdout as String).trim();
    if (name.isEmpty && email.isEmpty) return null;
    return GitIdentity(name: name, email: email);
  }

  /// Commits exactly [files] with `git commit --only -F - -- <files>`.
  ///
  /// `--only` commits just those paths without pulling in anything else from
  /// the index. Untracked paths cannot be committed by `--only`, so [untracked]
  /// is staged first with `git add -- <paths>`.
  Future<CommitResult> commitOnly(
    String repoPath,
    String message,
    List<String> files, {
    List<String> untracked = const [],
  }) async {
    if (untracked.isNotEmpty) {
      final add = await _run(repoPath, ['add', '--', ...untracked]);
      if (add.exitCode != 0) {
        return CommitResult(
          exitCode: add.exitCode,
          stdout: (add.stdout as String),
          stderr: (add.stderr as String),
        );
      }
    }
    final r = await _runWithStdin(
      repoPath,
      ['commit', '--only', '-F', '-', '--', ...files],
      message,
    );
    return CommitResult(
      exitCode: r.exitCode,
      stdout: (r.stdout as String),
      stderr: (r.stderr as String),
    );
  }
}

class GitIdentity {
  const GitIdentity({required this.name, required this.email});

  final String name;
  final String email;

  bool get isConfigured => name.isNotEmpty && email.isNotEmpty;
}

class CommitResult {
  const CommitResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get success => exitCode == 0;
}

class GitException implements Exception {
  const GitException(this.code, [this.details = '']);

  /// Stable machine-readable code: `gitNotFound` or `commandFailed`.
  final String code;

  /// Raw git stderr/stdout, kept verbatim for the user.
  final String details;

  @override
  String toString() => details.trim().isEmpty ? code : '$code\n$details';
}
