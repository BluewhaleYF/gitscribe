import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'ai_service.dart';
import 'app_config.dart';
import 'commit_executor.dart';
import 'draft_models.dart';
import 'git_service.dart';
import 'i18n.dart';
import 'message_generator.dart';
import 'models.dart';
import 'settings_dialog.dart';
import 'widgets/change_status_badge.dart';
import 'widgets/draft_review_view.dart';
import 'widgets/manual_split_view.dart';
import 'widgets/mode_picker.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.store});

  /// Optional config store; defaults to the user's Application Support file.
  final AppConfigStore? store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GitService _git = const GitService();
  final LocalMessageGenerator _generator = const LocalMessageGenerator();
  final AiService _ai = AiService();
  final CommitExecutor _executor = const CommitExecutor();

  late final AppConfigStore _store;
  late AppSettings _settings;

  final TextEditingController _pathController = TextEditingController();

  String? _repoPath;
  RepoInfo? _repoInfo;
  List<FileChange> _changes = const [];

  bool _loading = false;
  String? _error;

  FlowStage _stage = FlowStage.noRepo;
  DraftSession? _session;
  int _nextDraftId = 0;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? AppConfigStore();
    _settings = _store.load();

    final last = _settings.lastRepoPath;
    if (last != null && last.isNotEmpty) {
      _pathController.text = last;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadRepo(last));
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  /// Singleton lookup for strings used outside `build` (snackbars, errors).
  String _s(String key, [Map<String, String>? args]) =>
      I18nController.instance.t(key, args);

  String _defaultCommitLanguage() =>
      I18nController.instance.locale.languageCode == 'zh' ? 'zh' : 'en';

  CommitStyle _commitStyle() =>
      CommitStyle(language: _defaultCommitLanguage());

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  Future<void> _browse() async {
    final dir = await getDirectoryPath(confirmButtonText: _s('chooseRepository'));
    if (dir == null) return;
    await _loadRepo(dir);
  }

  Future<void> _loadRepo(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final root = await _git.findRepoRoot(trimmed);
      if (root == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = _s('notARepository', {'path': trimmed});
        });
        return;
      }
      _repoPath = root;
      _pathController.text = root;
      final ok = await _refreshData();
      if (!ok || !mounted) return;
      setState(() {
        _session = null;
        _stage = FlowStage.repoLoaded;
      });
      _settings = _settings.copyWith(lastRepoPath: root);
      _store.save(_settings);
    } on GitException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _describeError(_gitExceptionText(e));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _describeError(_s('failedToLoadRepository', {'error': '$e'}));
      });
    }
  }

  Future<void> _refresh() async {
    final rp = _repoPath;
    if (rp == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _refreshData();
  }

  /// Returns true when repo info and status were read successfully.
  Future<bool> _refreshData() async {
    final rp = _repoPath;
    if (rp == null) return false;
    try {
      final info = await _git.repoInfo(rp);
      final changes = await _git.status(rp);
      if (!mounted) return false;
      setState(() {
        _repoInfo = info;
        _changes = changes;
        _loading = false;
      });
      return true;
    } on GitException catch (e) {
      if (!mounted) return false;
      setState(() {
        _loading = false;
        _error = _describeError(_gitExceptionText(e));
      });
      return false;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _loading = false;
        _error = _describeError(_s('failedToReadRepository', {'error': '$e'}));
      });
      return false;
    }
  }

  Future<void> _startSingle() async {
    final rp = _repoPath;
    if (rp == null) return;

    final identity = await _git.identity(rp);
    if (!mounted) return;
    if (identity == null || !identity.isConfigured) {
      _showSnack(_s('missingGitIdentity'));
      return;
    }

    final entry = DraftEntry(
      id: 'draft-${_nextDraftId++}',
      files: [for (final c in _changes) c.path],
      message: _generator.generate(_changes, style: _commitStyle()),
    );
    setState(() {
      _session = DraftSession(mode: CommitMode.single, entries: [entry]);
      _stage = FlowStage.reviewing;
    });
  }

  void _startMultiManual() {
    setState(() => _stage = FlowStage.splittingManual);
  }

  void _onManualDone(List<DraftEntry> entries) {
    setState(() {
      _session = DraftSession(mode: CommitMode.multiManual, entries: entries);
      _stage = FlowStage.reviewing;
    });
  }

  Future<void> _startMultiAuto() async {
    final rp = _repoPath;
    if (rp == null) return;

    if (!_settings.ai.isConfigured) {
      _showSnack(_s('needApiKey'));
      return;
    }

    setState(() => _stage = FlowStage.splittingAuto);
    try {
      final files = [for (final c in _changes) c.path];
      final diff = await _git.diff(rp);
      final entries = await _ai.split(
        config: _settings.ai,
        diff: diff,
        files: files,
        opt: _commitStyle(),
      );
      if (!mounted) return;

      if (entries.length == 1) {
        setState(() {
          _session = DraftSession(mode: CommitMode.single, entries: entries);
          _stage = FlowStage.reviewing;
        });
        _showSnack(_s('splitDegradedToSingle'));
      } else {
        setState(() {
          _session = DraftSession(mode: CommitMode.multiAuto, entries: entries);
          _stage = FlowStage.reviewing;
        });
      }
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() => _stage = FlowStage.repoLoaded);
      _showSnack(_describeSplitError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _stage = FlowStage.repoLoaded);
      _showSnack(_s('aiDraftFailed', {'error': '$e'}));
    }
  }

  String _describeSplitError(AiException e) {
    switch (e.code) {
      case 'splitFormat':
        return _s('splitFormatError');
      case 'splitEmpty':
        return _s('splitEmptyError');
      default:
        return _s('aiDraftFailed', {'error': e.message});
    }
  }

  void _backToOptions() {
    setState(() {
      _session = null;
      _stage = FlowStage.repoLoaded;
    });
  }

  Future<void> _submitSession() async {
    final rp = _repoPath;
    final session = _session;
    if (rp == null || session == null) return;

    if (!session.entries.any((e) => e.enabled)) return;

    final untracked = {
      for (final c in _changes)
        if (c.isUntracked) c.path,
    };

    setState(() => _stage = FlowStage.submitting);
    try {
      final count = await _executor.execute(
        repoPath: rp,
        session: session,
        git: _git,
        untrackedPaths: untracked,
      );
      if (!mounted) return;
      _session = null;
      await _refresh();
      if (!mounted) return;
      setState(() => _stage = FlowStage.repoLoaded);
      _showSnack(
        session.mode == CommitMode.single
            ? _s('committedSuccessfully')
            : _s('committedSplit', {'count': '$count'}),
      );
    } on CommitFailedException catch (e) {
      if (!mounted) return;
      setState(() => _stage = FlowStage.reviewing);
      final base = _s('commitFailedAtIndex', {'index': '${e.index}'});
      final detail = e.stderr.trim();
      _showSnack(_describeError(detail.isEmpty ? base : '$base\n$detail'));
    } on GitException catch (e) {
      if (!mounted) return;
      setState(() => _stage = FlowStage.reviewing);
      _showSnack(_describeError(_gitExceptionText(e)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _stage = FlowStage.reviewing);
      _showSnack(_describeError(_s('commitFailedDetail', {'detail': '$e'})));
    }
  }

  Future<void> _openSettings() async {
    final updated = await showDialog<AiConfig>(
      context: context,
      builder: (_) => SettingsDialog(
        initial: _settings.ai,
        locale: I18nController.instance.locale,
        onLocaleChanged: _applyLocale,
      ),
    );
    if (updated == null || !mounted) return;
    setState(() => _settings = _settings.copyWith(ai: updated));
    _store.save(_settings);
    _showSnack(_s('settingsSaved'));
  }

  void _applyLocale(Locale locale) {
    I18nController.instance.setLocale(locale);
    final code = '${locale.languageCode}-${locale.countryCode}';
    if (_settings.localeCode == code) return;
    _settings = _settings.copyWith(localeCode: code);
    _store.save(_settings);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          width: 480,
        ),
      );
  }

  /// Labels authentication failures with a clear hint while leaving the raw
  /// git output intact. No retries or credential handling are attempted.
  String _describeError(String message) {
    if (GitService.isAuthFailure(message)) {
      return '${_s('authFailed')}\n$message';
    }
    return message;
  }

  String _gitExceptionText(GitException e) {
    final base =
        e.code == 'gitNotFound' ? _s('gitNotFound') : _s('gitCommandFailed');
    final details = e.details.trim();
    return details.isEmpty ? base : '$base\n$details';
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.comma, meta: true):
            _openSettings,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(context),
                const Divider(height: 1),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                if (_error != null) _buildErrorBanner(context, _error!),
                Expanded(child: _buildBody(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The main content area, switched solely on [FlowStage].
  Widget _buildBody(BuildContext context) {
    switch (_stage) {
      case FlowStage.noRepo:
        return _buildEmptyState(context);
      case FlowStage.repoLoaded:
        return _buildOptionPage(context);
      case FlowStage.reviewing:
        final session = _session;
        final rp = _repoPath;
        if (session == null || rp == null) return _buildOptionPage(context);
        return DraftReviewView(
          session: session,
          repoPath: rp,
          git: _git,
          ai: _ai,
          aiConfig: _settings.ai,
          style: _commitStyle(),
          onBack: _backToOptions,
          onSubmit: _submitSession,
        );
      case FlowStage.splittingAuto:
        return _buildBusy(context, 'splitting');
      case FlowStage.generating:
        return _buildBusy(context, 'generating');
      case FlowStage.submitting:
        return _buildBusy(context, 'submitting');
      case FlowStage.splittingManual:
        final rp = _repoPath;
        if (rp == null) return _buildOptionPage(context);
        return ManualSplitView(
          changes: _changes,
          repoPath: rp,
          git: _git,
          ai: _ai,
          aiConfig: _settings.ai,
          style: _commitStyle(),
          onBack: () => setState(() => _stage = FlowStage.repoLoaded),
          onDone: _onManualDone,
        );
    }
  }

  Widget _buildHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i18n = I18n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Icon(Icons.commit_rounded, size: 28, color: scheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GitScribe',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
              ),
              Text(
                i18n.t('appSubtitle'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Expanded(
            child: TextField(
              controller: _pathController,
              onSubmitted: _loadRepo,
              decoration: InputDecoration(
                isDense: true,
                hintText: i18n.t('pathHint'),
                prefixIcon: const Icon(Icons.folder_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _browse,
            icon: const Icon(Icons.folder_open),
            label: Text(i18n.t('browse')),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _repoPath == null ? null : _refresh,
            tooltip: i18n.t('refresh'),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _openSettings,
            tooltip: i18n.t('settingsTooltip'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i18n = I18n.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.difference_outlined, size: 72, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              i18n.t('emptyTitle'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              i18n.t('emptyBody'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _browse,
              icon: const Icon(Icons.folder_open),
              label: Text(i18n.t('chooseRepository')),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Full-page option page (repoLoaded) -----------------------------

  Widget _buildOptionPage(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRepoBar(context),
        const Divider(height: 1),
        Expanded(child: _buildFileList(context)),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: ModePicker(
            fileCount: _changes.length,
            onSingle: _startSingle,
            onMultiAuto: _startMultiAuto,
            onMultiManual: _startMultiManual,
          ),
        ),
      ],
    );
  }

  Widget _buildRepoBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = _repoInfo;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, size: 22, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  repo?.name ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (repo != null)
                  Text(
                    repo.branch,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontFamily: 'Menlo',
                          fontFamilyFallback: const ['Monaco', 'Courier New'],
                        ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _refresh,
            tooltip: I18n.of(context).t('refresh'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i18n = I18n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  i18n.t('changes'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                '${_changes.length}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _changes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 40, color: scheme.primary),
                        const SizedBox(height: 8),
                        Text(
                          i18n.t('workingTreeClean'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _changes.length,
                  itemBuilder: (context, i) =>
                      _buildChangeTile(context, _changes[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildChangeTile(BuildContext context, FileChange change) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = change.type == ChangeType.renamed ||
            change.type == ChangeType.copied
        ? '${change.originalPath} → ${change.path}'
        : change.path;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: SizedBox(
        width: 22,
        child: Center(child: ChangeStatusBadge(type: change.type)),
      ),
      title: Text(
        p.basename(change.path),
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        subtitle,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildBusy(BuildContext context, String textKey) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(I18n.of(context).t(textKey)),
        ],
      ),
    );
  }
}
