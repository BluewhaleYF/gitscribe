import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../ai_service.dart';
import '../draft_models.dart';
import '../git_service.dart';
import '../i18n.dart';
import '../message_generator.dart';
import '../prompts.dart';

/// The review (fine-tune) view shown at `FlowStage.reviewing`. Each
/// [DraftEntry] is a left/right split card: message + files on the left, and a
/// "调整" panel (format toggles + smart polish) on the right.
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
  Map<String, (int, int)> _numstat = const {};
  String? _busyKey; // '<entryId>:simplify' or '<entryId>:elaborate'

  @override
  void initState() {
    super.initState();
    for (final entry in widget.session.entries) {
      _controllers[entry.id] = TextEditingController(text: entry.message);
    }
    _loadNumstat();
  }

  Future<void> _loadNumstat() async {
    final map = await widget.git.diffNumstat(widget.repoPath);
    if (!mounted) return;
    setState(() => _numstat = map);
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
    setState(() => _busyKey = '${entry.id}:simplify');
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
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _elaborate(DraftEntry entry) async {
    if (!widget.aiConfig.isConfigured) {
      _showSnack(_s('needApiKey'));
      return;
    }
    setState(() => _busyKey = '${entry.id}:elaborate');
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
      if (mounted) setState(() => _busyKey = null);
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

  Widget _statTrailing(I18nController i18n, ColorScheme scheme, String file) {
    final stat = _numstat[file];
    if (stat == null) {
      return Text(
        i18n.t('newFile'),
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '+${stat.$1}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF16A34A),
            ),
          ),
          TextSpan(
            text: ' -${stat.$2}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFileDiff(String file) async {
    final diff = await widget.git.diffForPath(widget.repoPath, file);
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file_outlined,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          file,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Menlo',
                            fontFamilyFallback: ['Monaco', 'Courier New'],
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: diff.isEmpty
                      ? Center(
                          child: Text(
                            I18nController.instance.t('noTextualDiff'),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(diff, style: _mono),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
    final multi = widget.session.mode != CommitMode.single;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.commit, size: 22, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  i18n.t('commitMessageTitle'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildLeft(context, i18n, entry, multi)),
                const SizedBox(width: 12),
                Expanded(child: _buildAdjustPanel(context, i18n, entry)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeft(
    BuildContext context,
    I18nController i18n,
    DraftEntry entry,
    bool multi,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (multi)
          Row(
            children: [
              Checkbox(
                value: entry.enabled,
                onChanged: (v) => setState(() => entry.enabled = v ?? true),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Text(
                i18n.t('enabled'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        TextField(
          controller: _controllers[entry.id],
          minLines: 3,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          style: _mono,
          onChanged: (value) => entry.message = value,
          decoration: const InputDecoration(
            isDense: true,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            dense: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(
              Icons.folder_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            title: Text(
              i18n.t('groupFiles', {'count': '${entry.files.length}'}),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            children: [
              for (final file in entry.files)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.insert_drive_file_outlined,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  title: Text(
                    p.basename(file),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    file,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: _statTrailing(i18n, scheme, file),
                  onTap: () => _showFileDiff(file),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdjustPanel(
    BuildContext context,
    I18nController i18n,
    DraftEntry entry,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final simplifyBusy = _busyKey == '${entry.id}:simplify';
    final elaborateBusy = _busyKey == '${entry.id}:elaborate';
    final busy = simplifyBusy || elaborateBusy;
    final hasGitmoji = LocalMessageGenerator.hasGitmoji(entry.message);
    final hasConventional =
        LocalMessageGenerator.extractType(entry.message) != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 22, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                i18n.t('adjust'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            i18n.t('format'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.emoji_emotions, size: 20),
            title: Text(i18n.t('gitmoji')),
            value: hasGitmoji,
            onChanged: (_) => _toggleGitmoji(entry),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.rule, size: 20),
            title: Text(i18n.t('conventional')),
            value: hasConventional,
            onChanged: (_) => _toggleConventional(entry),
          ),
          const SizedBox(height: 6),
          Text(
            i18n.t('smartPolish'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.short_text, size: 20),
            title: Text(i18n.t('simplify')),
            trailing: simplifyBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right, size: 20),
            onTap: busy ? null : () => _simplify(entry),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.subject, size: 20),
            title: Text(i18n.t('elaborate')),
            trailing: elaborateBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right, size: 20),
            onTap: busy ? null : () => _elaborate(entry),
          ),
        ],
      ),
    );
  }
}
