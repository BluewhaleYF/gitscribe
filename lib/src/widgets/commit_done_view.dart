import 'package:flutter/material.dart';

import '../git_service.dart';
import '../i18n.dart';

/// The "commit complete" view shown at `FlowStage.committed`. Shows the result
/// and offers a one-click push with a branch selector.
class CommitDoneView extends StatefulWidget {
  const CommitDoneView({
    super.key,
    required this.repoPath,
    required this.git,
    required this.currentBranch,
    required this.commitCount,
    required this.onDone,
  });

  final String repoPath;
  final GitService git;
  final String currentBranch;
  final int commitCount;
  final VoidCallback onDone;

  @override
  State<CommitDoneView> createState() => _CommitDoneViewState();
}

class _CommitDoneViewState extends State<CommitDoneView> {
  String? _remote;
  List<String> _branches = const [];
  late final TextEditingController _branchController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _branchController = TextEditingController(text: widget.currentBranch);
    _load();
  }

  @override
  void dispose() {
    _branchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final remotes = await widget.git.remotes(widget.repoPath);
    final remote = remotes.isEmpty ? null : remotes.first;
    final branches = remote == null
        ? const <String>[]
        : await widget.git.remoteBranches(widget.repoPath, remote);
    if (!mounted) return;
    setState(() {
      _remote = remote;
      _branches = branches;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _push() async {
    final remote = _remote;
    if (remote == null || _busy) return;
    final branch = _branchController.text.trim();
    if (branch.isEmpty) {
      _snack(I18nController.instance.t('branchRequired'));
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.git.push(
        widget.repoPath,
        remote: remote,
        branch: branch,
      );
      if (!mounted) return;
      if (result.success) {
        _snack(I18nController.instance.t('pushSuccess'));
      } else {
        _snack(_pushError(result.stderr.trim()));
      }
    } on GitException catch (e) {
      if (!mounted) return;
      _snack(_pushError(e.details.trim()));
    } catch (e) {
      if (!mounted) return;
      _snack(_pushError('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _pushError(String detail) {
    final base = I18nController.instance.t('pushFailed');
    return detail.isEmpty ? base : '$base\n$detail';
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.check_circle,
                  size: 72, color: const Color(0xFF16A34A)),
              const SizedBox(height: 16),
              Text(
                i18n.t('commitDoneTitle'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                i18n.t('committedCount', {'count': '${widget.commitCount}'}),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.cloud_upload_outlined,
                            size: 20, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          i18n.t('pushToRemote'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_remote == null)
                      Text(
                        i18n.t('noRemote'),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      )
                    else ...[
                      TextField(
                        controller: _branchController,
                        decoration: InputDecoration(
                          labelText: i18n.t('branch'),
                          hintText: widget.currentBranch,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (_branches.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final b in _branches)
                              ChoiceChip(
                                label: Text(b),
                                selected: _branchController.text == b,
                                onSelected: (_) => setState(
                                    () => _branchController.text = b),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _busy ? null : _push,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_upload),
                        label: Text(i18n.t('push')),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: widget.onDone,
                child: Text(i18n.t('done')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
