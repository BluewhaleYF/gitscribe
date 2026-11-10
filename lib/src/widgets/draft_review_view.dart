import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../ai_service.dart';
import '../draft_models.dart';
import '../git_service.dart';
import '../i18n.dart';
import '../message_generator.dart';
import '../prompts.dart';

/// The review (fine-tune) view shown at `FlowStage.reviewing`. Renders one
/// card per [DraftEntry] with an editable message and quick-rewrite buttons.
class DraftReviewView extends StatefulWidget {
  const DraftReviewView({
    super.key,
    required this.session,
    required this.repoPath,
    required this.git,
    required this.ai,
    required this.aiConfig,
    required this.style,
    required this.onBack,
    required this.onSubmit,
  });

  final DraftSession session;
  final String repoPath;
  final GitService git;
  final AiService ai;
  final AiConfig aiConfig;
  final CommitStyle style;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  @override
  State<DraftReviewView> createState() => _DraftReviewViewState();
}

class _DraftReviewViewState extends State<DraftReviewView> {
  static const _mono = TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: ['Monaco', 'Courier New'],
    fontSize: 12.5,
    height: 1.5,
  );

  final Map<String, TextEditingController> _controllers = {};
  String? _busyId;

  @override
  void initState() {
    super.initState();
    for (final entry in widget.session.entries) {
      _controllers[entry.id] = TextEditingController(text: entry.message);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

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

  void _setMessage(DraftEntry entry, String message) {
    entry.message = message;
    setState(() => _controllers[entry.id]!.text = message);
  }

  Future<void> _simplify(DraftEntry entry) async {
    if (!widget.aiConfig.isConfigured) {
      _showSnack(_s('needApiKey'));
      return;
    }
    setState(() => _busyId = entry.id);
    try {
      final message = await widget.ai.rewrite(
        config: widget.aiConfig,
        currentMessage: entry.message,
        intent: RewriteIntent.simplify,
        opt: widget.style,
      );
      if (!mounted) return;
      _setMessage(entry, message);
    } on AiException catch (e) {
      if (!mounted) return;
      _showSnack(_s('aiDraftFailed', {'error': e.message}));
    } catch (e) {
      if (!mounted) return;
      _showSnack(_s('aiDraftFailed', {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _elaborate(DraftEntry entry) async {
    if (!widget.aiConfig.isConfigured) {
      _showSnack(_s('needApiKey'));
      return;
    }
    setState(() => _busyId = entry.id);
    try {
      final diff = await widget.git.diffForPaths(widget.repoPath, entry.files);
      final message = await widget.ai.rewrite(
        config: widget.aiConfig,
        currentMessage: entry.message,
        intent: RewriteIntent.elaborate,
        scopedDiff: diff,
        opt: widget.style,
      );
      if (!mounted) return;
      _setMessage(entry, message);
    } on AiException catch (e) {
      if (!mounted) return;
      _showSnack(_s('aiDraftFailed', {'error': e.message}));
    } catch (e) {
      if (!mounted) return;
      _showSnack(_s('aiDraftFailed', {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _toggleGitmoji(DraftEntry entry) {
    final message = LocalMessageGenerator.hasGitmoji(entry.message)
        ? LocalMessageGenerator.removeGitmoji(entry.message)
        : LocalMessageGenerator.addGitmoji(entry.message);
    _setMessage(entry, message);
  }

  void _toggleConventional(DraftEntry entry) {
    final message = LocalMessageGenerator.extractType(entry.message) != null
        ? LocalMessageGenerator.removeConventionalPrefix(entry.message)
        : LocalMessageGenerator.addConventionalPrefix(
            entry.message,
            LocalMessageGenerator.inferTypeFromPaths(entry.files),
          );
    _setMessage(entry, message);
  }

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.of(context);
    final anyEnabled = widget.session.entries.any((e) => e.enabled);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: widget.session.entries.length,
            itemBuilder: (context, i) =>
                _buildEntryCard(context, i18n, widget.session.entries[i]),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                label: Text(i18n.t('back')),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: anyEnabled ? widget.onSubmit : null,
                icon: const Icon(Icons.commit),
                label: Text(i18n.t('commitAll')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEntryCard(
    BuildContext context,
    I18nController i18n,
    DraftEntry entry,
  ) {
    final busy = _busyId == entry.id;
    final multi = widget.session.mode != CommitMode.single;
    final hasGitmoji = LocalMessageGenerator.hasGitmoji(entry.message);
    final hasConventional =
        LocalMessageGenerator.extractType(entry.message) != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (multi)
                  Tooltip(
                    message: i18n.t('enabled'),
                    child: Checkbox(
                      value: entry.enabled,
                      onChanged: (v) => setState(() => entry.enabled = v ?? true),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final file in entry.files)
                        Chip(
                          label: Text(p.basename(file)),
                          labelStyle: const TextStyle(fontSize: 12),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controllers[entry.id],
              minLines: 2,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: _mono,
              onChanged: (value) => entry.message = value,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ActionChip(
                  avatar: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.short_text, size: 18),
                  label: Text(i18n.t('simplify')),
                  onPressed: busy ? null : () => _simplify(entry),
                ),
                ActionChip(
                  avatar: const Icon(Icons.subject, size: 18),
                  label: Text(i18n.t('elaborate')),
                  onPressed: busy ? null : () => _elaborate(entry),
                ),
                FilterChip(
                  label: Text(i18n.t('gitmoji')),
                  selected: hasGitmoji,
                  onSelected: (_) => _toggleGitmoji(entry),
                ),
                FilterChip(
                  label: Text(i18n.t('conventional')),
                  selected: hasConventional,
                  onSelected: (_) => _toggleConventional(entry),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
