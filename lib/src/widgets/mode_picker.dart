import 'package:flutter/material.dart';

import '../i18n.dart';

/// The option page shown at `FlowStage.repoLoaded`: pick a single commit or
/// (when more than one file changed) split into multiple commits, then choose
/// automatic or manual splitting.
class ModePicker extends StatefulWidget {
  const ModePicker({
    super.key,
    required this.fileCount,
    required this.onSingle,
    required this.onMultiAuto,
    required this.onMultiManual,
  });

  final int fileCount;
  final VoidCallback onSingle;
  final VoidCallback onMultiAuto;
  final VoidCallback onMultiManual;

  @override
  State<ModePicker> createState() => _ModePickerState();
}

class _ModePickerState extends State<ModePicker> {
  bool _showSplitModes = false;

  @override
  Widget build(BuildContext context) {
    final i18n = I18n.of(context);

    if (widget.fileCount == 0) {
      return Center(
        child: Text(
          i18n.t('noChangesToCommit'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModeCard(
          icon: Icons.crop_square,
          title: i18n.t('singleCommit'),
          subtitle: i18n.t('singleCommitHint'),
          onTap: widget.onSingle,
        ),
        if (widget.fileCount > 1) ...[
          const SizedBox(height: 12),
          if (!_showSplitModes)
            _ModeCard(
              icon: Icons.call_split,
              title: i18n.t('splitCommits'),
              subtitle: i18n.t('multiCommitHint'),
              emphasized: true,
              onTap: () => setState(() => _showSplitModes = true),
            ),
          if (_showSplitModes) ...[
            _ModeCard(
              icon: Icons.auto_awesome,
              title: i18n.t('multiAuto'),
              subtitle: i18n.t('multiAutoHint'),
              emphasized: true,
              onTap: widget.onMultiAuto,
            ),
            const SizedBox(height: 12),
            _ModeCard(
              icon: Icons.check_box_outlined,
              title: i18n.t('multiManual'),
              subtitle: i18n.t('multiManualHint'),
              onTap: widget.onMultiManual,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(() => _showSplitModes = false),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(i18n.t('back')),
            ),
          ],
        ],
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: emphasized
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 28,
                color: emphasized ? scheme.onPrimaryContainer : scheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
