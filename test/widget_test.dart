import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitscribe/main.dart';
import 'package:gitscribe/src/ai_service.dart';
import 'package:gitscribe/src/app_config.dart';
import 'package:gitscribe/src/commit_executor.dart';
import 'package:gitscribe/src/draft_models.dart';
import 'package:gitscribe/src/git_service.dart';
import 'package:gitscribe/src/i18n.dart';
import 'package:gitscribe/src/message_generator.dart';
import 'package:gitscribe/src/models.dart';
import 'package:gitscribe/src/widgets/mode_picker.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await I18nController.instance.load(const Locale('en', 'US'));
  });

  setUp(() {
    I18nController.instance.setLocale(const Locale('en', 'US'));
  });

  // Isolates widget tests from the user's real persisted settings so the
  // auto-load of `lastRepoPath` never spawns a real `git` process.
  AppConfigStore testStore() {
    final file = File(
      '${Directory.systemTemp.path}/gitscribe_widget_test_config.json',
    );
    if (file.existsSync()) file.deleteSync();
    return AppConfigStore(filePath: file.path);
  }

  Future<String> runGit(List<String> args) async {
    final r = await Process.run('git', args);
    return (r.stdout as String).trim();
  }

  test('drafts a feat message for newly added code', () {
    const gen = LocalMessageGenerator();
    final message = gen.generate(const [
      FileChange(
        indexStatus: '?',
        workTreeStatus: '?',
        path: 'lib/auth/login_screen.dart',
      ),
    ]);
    expect(message, startsWith('feat('));
    expect(message, contains('add login screen'));
  });

  test('drafts a docs message for a README edit', () {
    const gen = LocalMessageGenerator();
    final message = gen.generate(const [
      FileChange(
        indexStatus: ' ',
        workTreeStatus: 'M',
        path: 'docs/README.md',
      ),
    ]);
    expect(message, startsWith('docs('));
  });

  test('generates a zh message with gitmoji', () {
    const gen = LocalMessageGenerator();
    final message = gen.generate(
      const [
        FileChange(
          indexStatus: '?',
          workTreeStatus: '?',
          path: 'lib/auth/login_screen.dart',
        ),
      ],
      style: const CommitStyle(language: 'zh', useGitmoji: true),
    );
    expect(message, startsWith('✨ feat('));
    expect(message, contains('添加 login screen'));
  });

  test('generates a plain message without the conventional prefix', () {
    const gen = LocalMessageGenerator();
    final message = gen.generate(
      const [
        FileChange(
          indexStatus: '?',
          workTreeStatus: '?',
          path: 'lib/auth/login_screen.dart',
        ),
      ],
      style: const CommitStyle(useConventionalCommit: false),
    );
    expect(message, startsWith('add login screen'));
    expect(message, isNot(contains('(')));
  });

  test('groupChanges splits by top-level directory', () {
    const gen = LocalMessageGenerator();
    final groups = gen.groupChanges(const [
      FileChange(indexStatus: 'M', workTreeStatus: ' ', path: 'lib/a.dart'),
      FileChange(indexStatus: 'M', workTreeStatus: ' ', path: 'lib/b.dart'),
      FileChange(indexStatus: 'M', workTreeStatus: ' ', path: 'macos/c.swift'),
    ]);
    expect(groups.length, 2);
    expect(groups.expand((g) => g).length, 3);
  });

  test('gitmoji toggle adds and removes a leading emoji', () {
    expect(LocalMessageGenerator.hasGitmoji('feat: add x'), isFalse);
    final withEmoji = LocalMessageGenerator.addGitmoji('feat: add x');
    expect(withEmoji, startsWith('✨'));
    expect(LocalMessageGenerator.hasGitmoji(withEmoji), isTrue);
    expect(LocalMessageGenerator.removeGitmoji(withEmoji), 'feat: add x');
  });

  test('removeGitmoji leaves Chinese text untouched', () {
    expect(LocalMessageGenerator.hasGitmoji('添加 login screen'), isFalse);
    expect(
      LocalMessageGenerator.removeGitmoji('添加 login screen'),
      '添加 login screen',
    );
  });

  test('conventional prefix toggles on and off', () {
    expect(LocalMessageGenerator.extractType('feat(ui): add x'), 'feat');
    expect(
      LocalMessageGenerator.removeConventionalPrefix('feat(ui): add x'),
      'add x',
    );
    expect(
      LocalMessageGenerator.addConventionalPrefix('add x', 'feat'),
      'feat: add x',
    );
    expect(
      LocalMessageGenerator.addConventionalPrefix('fix: y', 'feat'),
      'fix: y',
    );
  });

  test('inferTypeFromPaths maps paths to a type', () {
    expect(LocalMessageGenerator.inferTypeFromPaths(['lib/a.dart']), 'feat');
    expect(LocalMessageGenerator.inferTypeFromPaths(['docs/README.md']), 'docs');
    expect(LocalMessageGenerator.inferTypeFromPaths(['test/a_test.dart']), 'test');
  });

  test('gitmoji and conventional prefix coexist', () {
    // Add conventional after gitmoji keeps the emoji first.
    expect(
      LocalMessageGenerator.addConventionalPrefix('🔧 add x', 'feat'),
      '🔧 feat: add x',
    );
    // Type is detected through the leading emoji.
    expect(LocalMessageGenerator.extractType('🔧 feat: add x'), 'feat');
    expect(LocalMessageGenerator.hasGitmoji('🔧 feat: add x'), isTrue);
    // Removing conventional keeps the emoji.
    expect(
      LocalMessageGenerator.removeConventionalPrefix('🔧 feat: add x'),
      '🔧 add x',
    );
  });

  test('humanize converts identifiers into words', () {
    expect(LocalMessageGenerator.humanize('login_form'), 'login form');
    expect(LocalMessageGenerator.humanize('LoginForm'), 'login form');
    expect(LocalMessageGenerator.humanize(''), 'files');
  });

  test('isAuthFailure detects authentication errors, not clean states', () {
    expect(
      GitService.isAuthFailure(
        'fatal: Authentication failed for https://github.com/foo/bar.git',
      ),
      isTrue,
    );
    expect(
      GitService.isAuthFailure('git@github.com: Permission denied (publickey).'),
      isTrue,
    );
    expect(
      GitService.isAuthFailure('nothing to commit, working tree clean'),
      isFalse,
    );
  });

  test('switches between locales', () {
    final i18n = I18nController.instance;
    expect(i18n.t('commit'), 'Commit');

    i18n.setLocale(const Locale('zh', 'CN'));
    expect(i18n.t('commit'), '提交');
    expect(i18n.t('untrackedNote', {'count': '3'}), contains('3'));
  });

  testWidgets('renders the GitScribe shell', (tester) async {
    await tester.pumpWidget(GitScribeApp(store: testStore()));
    await tester.pump();

    expect(find.text('GitScribe'), findsOneWidget);
    expect(find.text('Pick a repository to get started'), findsOneWidget);
  });

  testWidgets('opens settings from the gear button', (tester) async {
    await tester.pumpWidget(GitScribeApp(store: testStore()));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('AI provider'), findsOneWidget);
  });

  testWidgets('opens settings with the Command+, shortcut', (tester) async {
    await tester.pumpWidget(GitScribeApp(store: testStore()));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('ModePicker hides multi option for a single file', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModePicker(
          fileCount: 1,
          onSingle: () {},
          onMultiAuto: () {},
          onMultiManual: () {},
        ),
      ),
    ));
    expect(find.text('Single commit'), findsOneWidget);
    expect(find.text('Split commits'), findsNothing);
  });

  testWidgets('ModePicker shows multi option for multiple files', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModePicker(
          fileCount: 3,
          onSingle: () {},
          onMultiAuto: () {},
          onMultiManual: () {},
        ),
      ),
    ));
    expect(find.text('Single commit'), findsOneWidget);
    expect(find.text('Split commits'), findsOneWidget);
  });

  testWidgets('ModePicker expands auto/manual after tapping multi', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ModePicker(
          fileCount: 3,
          onSingle: () {},
          onMultiAuto: () {},
          onMultiManual: () {},
        ),
      ),
    ));
    await tester.tap(find.text('Split commits'));
    await tester.pumpAndSettle();
    expect(find.text('Fully automatic'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
  });

  test('parseSplitResponse strips fence and keeps valid files', () {
    final entries = AiService.parseSplitResponse(
      '```json\n'
      '{"commits":['
      '{"message":"feat: a","files":["lib/a.dart","ghost.dart"]},'
      '{"message":"fix: c","files":["macos/c.swift"]}'
      ']}\n```',
      ['lib/a.dart', 'lib/b.dart', 'macos/c.swift'],
    );
    expect(entries.length, 2);
    expect(entries[0].files, ['lib/a.dart']);
    expect(entries[1].files, ['macos/c.swift']);
  });

  test('parseSplitResponse drops commits with empty files or message', () {
    final entries = AiService.parseSplitResponse(
      '{"commits":['
      '{"message":"","files":["lib/a.dart"]},'
      '{"message":"ok","files":[]},'
      '{"message":"real","files":["lib/a.dart"]}'
      ']}',
      ['lib/a.dart'],
    );
    expect(entries.length, 1);
    expect(entries[0].message, 'real');
  });

  test('parseSplitResponse throws on invalid JSON', () {
    expect(
      () => AiService.parseSplitResponse('not json', ['a.dart']),
      throwsA(isA<AiException>().having((e) => e.code, 'code', 'splitFormat')),
    );
  });

  test('parseSplitResponse throws on empty commits', () {
    expect(
      () => AiService.parseSplitResponse('{"commits":[]}', ['a.dart']),
      throwsA(isA<AiException>().having((e) => e.code, 'code', 'splitEmpty')),
    );
  });

  test('executor commits entries in order with --only isolation', () async {
    final dir = await Directory.systemTemp.createTemp('gitscribe_commit_test');
    try {
      final repo = dir.path;
      await runGit(['-C', repo, 'init', '-q']);
      await runGit(['-C', repo, 'config', 'user.name', 'Test']);
      await runGit(['-C', repo, 'config', 'user.email', 'test@example.com']);
      await runGit(['-C', repo, 'config', 'commit.gpgsign', 'false']);
      File('$repo/a.txt').writeAsStringSync('a\n');
      File('$repo/b.txt').writeAsStringSync('b\n');
      File('$repo/c.txt').writeAsStringSync('c\n');
      await runGit(['-C', repo, 'add', 'c.txt']); // staged, but not in session

      final session = DraftSession(mode: CommitMode.multiManual, entries: [
        DraftEntry(id: 'e1', files: ['a.txt'], message: 'feat: add a'),
        DraftEntry(id: 'e2', files: ['b.txt'], message: 'feat: add b'),
      ]);

      final count = await const CommitExecutor().execute(
        repoPath: repo,
        session: session,
        git: const GitService(),
        untrackedPaths: {'a.txt', 'b.txt'},
      );
      expect(count, 2);
      expect(session.entries, isEmpty);

      final log = await runGit(['-C', repo, 'log', '--oneline']);
      expect(log.split('\n').length, 2);

      final firstFiles = await runGit(
        ['-C', repo, 'show', '--name-only', '--pretty=format:', 'HEAD~1'],
      );
      final secondFiles = await runGit(
        ['-C', repo, 'show', '--name-only', '--pretty=format:', 'HEAD'],
      );
      expect(firstFiles, contains('a.txt'));
      expect(firstFiles, isNot(contains('b.txt')));
      expect(secondFiles, contains('b.txt'));
      expect(secondFiles, isNot(contains('a.txt')));

      // c.txt was staged before the session and must remain staged/untouched.
      final staged = await runGit(
        ['-C', repo, 'diff', '--cached', '--name-only'],
      );
      expect(staged, contains('c.txt'));
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
