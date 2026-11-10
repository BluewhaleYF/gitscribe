import 'message_generator.dart';

/// Prompt templates for LLM calls, kept separate from the client so they are
/// easy to review and version.

const String splitSystemPrompt = '''
You are GitScribe, an expert at splitting a working-tree diff into a small
number of logically independent git commits.

Return ONLY a JSON object with this exact shape. No markdown fences, no
commentary, no extra text:

{
  "commits": [
    { "message": "feat(ui): add repo picker", "files": ["lib/features/home/home_page.dart"] },
    { "message": "chore: update pubspec", "files": ["pubspec.yaml"] }
  ]
}

Rules:
- Use only paths from the "Changed files" list; never invent paths.
- Every changed file must appear in exactly one commit; do not duplicate or
  split a single file across commits.
- Group files into the smallest number of commits that keeps each commit
  coherent.
''';

const String draftSystemPrompt = '''
You are GitScribe, an expert at writing concise git commit messages for a given
set of changed files and a diff.

Write a single commit message. Keep the subject under 72 characters and use the
imperative mood. Use a short bulleted body only when helpful.

Reply with ONLY the commit message. No code fences, no explanations, no leading
or trailing blank lines.
''';

/// Shared style instructions derived from [CommitStyle].
String buildStyleInstructions(CommitStyle opt) {
  final language = opt.language == 'zh' ? 'Chinese' : 'English';
  final gitmoji = opt.useGitmoji
      ? 'prefix each subject with a gitmoji emoji'
      : 'no gitmoji';
  final conventional = opt.useConventionalCommit
      ? 'use the `type(scope): subject` prefix'
      : 'plain subject, no type/scope prefix';
  return 'Message language: $language.\n'
      'Gitmoji: $gitmoji.\n'
      'Conventional Commits: $conventional.';
}

String buildSplitUserPrompt({
  required String diff,
  required List<String> files,
  required CommitStyle opt,
  String? conventionText,
}) {
  return _buildUserPrompt(
    diff: diff,
    files: files,
    opt: opt,
    conventionText: conventionText,
  );
}

String buildDraftUserPrompt({
  required String diff,
  required List<String> files,
  required CommitStyle opt,
  String? conventionText,
}) {
  return _buildUserPrompt(
    diff: diff,
    files: files,
    opt: opt,
    conventionText: conventionText,
  );
}

String _buildUserPrompt({
  required String diff,
  required List<String> files,
  required CommitStyle opt,
  String? conventionText,
}) {
  final filesText = files.map((f) => '  $f').join('\n');
  final convention = (conventionText != null && conventionText.isNotEmpty)
      ? '\n\nConvention:\n$conventionText'
      : '';
  final d = diff.trim().isEmpty ? '(no textual diff)' : diff.trim();
  return '''
Changed files:
$filesText

Diff:
$d

${buildStyleInstructions(opt)}$convention
''';
}

/// The intents supported by [AiService.rewrite]. Only `simplify` and
/// `elaborate` go through the LLM; gitmoji / conventional toggles are handled
/// locally.
enum RewriteIntent { simplify, elaborate }

const String rewriteSystemPrompt = '''
You are GitScribe. Rewrite the given commit message according to the
instruction.

Reply with ONLY the rewritten commit message. No code fences, no explanations,
no leading or trailing blank lines.
''';

String buildRewriteUserPrompt({
  required String currentMessage,
  required RewriteIntent intent,
  String? scopedDiff,
  required CommitStyle opt,
}) {
  final instruction = intent == RewriteIntent.simplify
      ? 'Make it shorter: a single one-line subject. Keep any type/scope '
          'prefix and any gitmoji.'
      : 'Keep the subject line as-is, and add a short body explaining the '
          'motivation and impact.';
  final diffSection =
      (intent == RewriteIntent.elaborate &&
              scopedDiff != null &&
              scopedDiff.trim().isNotEmpty)
          ? '\n\nRelevant diff:\n${scopedDiff.trim()}'
          : '';
  return '''
Current message:
$currentMessage

Instruction:
$instruction$diffSection

${buildStyleInstructions(opt)}
''';
}
