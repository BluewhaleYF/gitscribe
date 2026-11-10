import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../ai_service.dart';
import '../draft_models.dart';
import '../git_service.dart';
import '../i18n.dart';
import '../message_generator.dart';
import '../models.dart';
import 'change_status_badge.dart';

/// Stage C: manually group changed files into commits.
///
/// Files are checked off, then a message is generated for the selection
/// ("generate this commit") or for all remaining files ("generate all").
/// Grouped files grey out and can't be selected again. When every file is
/// grouped, [onDone] hands the accumulated [DraftEntry]s back.
class ManualSplitView extends StatefulWidget {
  const ManualSplitView({
    super.key,
    required this.changes,
    required this.repoPath,
    required this.git,
    required this.ai,
    required this.aiConfig,
    required this.style,
    required this.onBack,
    required this.onDone,
  });

  final List<FileChange> changes;
  final String repoPath;
  final GitService git;
  final AiService ai;
  final AiConfig aiConfig;
  final CommitStyle style;
  final VoidCallback onBack;
  final ValueChanged<List<DraftEntry>> onDone;

  @override
  State<ManualSplitView> createState() => _ManualSplitViewState();
}

class _ManualSplitViewState extends State<ManualSplitView> {
  final Set<String> _selected = {};
  final Set<String> _grouped = {};
  final List<DraftEntry> _entries = [];
  int _nextId = 0;
  bool _busy = false;

  int get _total => widget.changes.length;
  int get _remaining => _total - _grouped.length;
  bool get _allGrouped => _grouped.length == _total;

  String _s(String key, [Map<String, String>? args]) =>
      I18nController.instance.t(key, args);

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _toggle(String path) {
    setState(() {
      if (!_selected.remove(path)) _selected.add(path);
    });
  }

  Future<void> _generateSelected() async {
    if (_selected.isEmpty) {
      _showSnack(_s('noFilesSelected'));
      return;
    }
    if (!widget.aiConfig.isConfigured) {
      _showSnack(_s('needApiKey'));
      return;
    }
    final paths = _selected.toList()..sort();

    setState(() => _busy = true);
    try {
      final diff = await widget.git.diffForPaths(widget.repoPath, paths);
      final message = await widget.ai.draftMessage(
        config: widget.aiConfig,
        diff: diff,
        files: paths,
        opt: widget.style,
      );
      if (!mounted) return;
      setState(() {
        _entries.add(
          DraftEntry(id: 'manual-${_nextId++}', files: paths, message: message),
        );
        _grouped.addAll(paths);
        _selected.clear();
      });
    } on AiException catch (e) {
      if (!mounted) return;
      _showSnack(_s('aiDraftFailed', {'error': e.message}));
    } catch (e) {
      if (!mounted) return;
      _showSnack(_s('aiDraftFailed', {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateAll() async {
    if (!widget.aiConfig.isConfigured) {
      _showSnack(_s('needApiKey'));
      return;
    }
    final remaining =
        widget.changes.where((c) => !_grouped.contains(c.path)).toList();
    if (remaining.isEmpty) {
      _showSnack(_s('noRemainingFiles'));
      return;
    }
    final paths = [for (final c in remaining) c.path]..sort();

    setState(() => _busy = true);
    try {
      final diff = await widget.git.diffForPaths(widget.repoPath, paths);
      final splitEntries = await widget.ai.split(
        config: widget.aiConfig,
        diff: diff,
        files: paths,
        opt: widget.style,
      );
      if (!mounted) return;
      setState(() {
        for (final e in splitEntries) {
          _entries.add(DraftEntry(
            id: 'manual-${_nextId++}',
            files: e.files,
            message: e.message,
          ));
        }
        _grouped.addAll(paths);
        _selected.clear();
      });
    } on AiException catch (e) {
      if (!mounted) return;
      _showSnack(_splitError(e));
    } catch (e) {
      if (!mounted) return;
      _showSnack(_s('aiDraftFailed', {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _splitError(AiException e) {
    switch (e.code) {
      case 'splitFormat':
        return _s('splitFormatError');
      case 'splitEmpty':
        return _s('splitEmptyError');
      default:
        return _s('aiDraftFailed', {'error': e.message});
    }
  }

  void _goReview() {
    if (!_allGrouped || _entries.isEmpty) return;
    widget.onDone(List.of(_entries));
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  i18n.t('manualSplitTitle'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                i18n.t('groupedProgress', {
                  'grouped': '${_grouped.length}',
                  'total': '$_total',
                }),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          flex: 3,
          child: ListView.builder(
            itemCount: widget.changes.length,
            itemBuilder: (context, i) => _buildFileTile(context, widget.changes[i]),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          flex: 2,
          child: _entries.isEmpty
              ? Center(
                  child: Text(
                    i18n.t('noGeneratedGroups'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _entries.length,
                  itemBuilder: (context, i) => _buildGroupTile(context, i18n, _entries[i]),
                ),
        ),
        const Divider(height: 1),
        _buildBottomBar(context),
      ],
    );
  }

  Widget _buildFileTile(BuildContext context, FileChange change) {
    final scheme = Theme.of(context).colorScheme;
    final isGrouped = _grouped.contains(change.path);
    final checked = _selected.contains(change.path);
    return CheckboxListTile(
      dense: true,
      value: isGrouped || checked,
      onChanged: isGrouped ? null : (_) => _toggle(change.path),
      controlAffinity: ListTileControlAffinity.leading,
      secondary: ChangeStatusBadge(type: change.type),
      title: Text(
        p.basename(change.path),
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          color: isGrouped ? scheme.outline : null,
        ),
      ),
      subtitle: Text(
        isGrouped ? I18nController.instance.t('alreadyGrouped') : change.path,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          color: isGrouped ? scheme.outline : scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildGroupTile(
    BuildContext context,
    I18nController i18n,
    DraftEntry entry,
  ) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.commit, size: 20),
      title: Text(
        entry.message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        i18n.t('groupFiles', {'count': '${entry.files.length}'}),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final i18n = I18n.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back),
            label: Text(i18n.t('back')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _remaining == 0
                ? const SizedBox.shrink()
                : Text(
                    i18n.t('remainingUngrouped', {'count': '$_remaining'}),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonalIcon(
            onPressed: (_busy || _selected.isEmpty) ? null : _generateSelected,
            icon: const Icon(Icons.add_comment_outlined),
            label: Text(i18n.t('generateThis')),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: (_busy || _remaining == 0) ? null : _generateAll,
            icon: const Icon(Icons.auto_fix_high),
            label: Text(i18n.t('generateAll')),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: (_busy || !_allGrouped || _entries.isEmpty) ? null : _goReview,
            icon: const Icon(Icons.rate_review_outlined),
            label: Text(i18n.t('goReview')),
          ),
        ],
      ),
    );
  }
}
