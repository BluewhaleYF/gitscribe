import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_service.dart';
import 'i18n.dart';

class _LanguageOption {
  const _LanguageOption(this.locale, this.label);

  final Locale locale;
  final String label;
}

// Language names are shown in their own language (native names).
const List<_LanguageOption> _languageOptions = [
  _LanguageOption(Locale('en', 'US'), 'English'),
  _LanguageOption(Locale('zh', 'CN'), '简体中文'),
];

/// Modal settings screen. Pops with the updated [AiConfig] on save, or `null`
/// when cancelled. Language changes are applied immediately via
/// [onLocaleChanged].
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.initial,
    required this.locale,
    required this.onLocaleChanged,
  });

  final AiConfig initial;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _maxDiffChars;
  late Locale _locale;
  String? _error;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(text: widget.initial.baseUrl);
    _apiKey = TextEditingController(text: widget.initial.apiKey);
    _model = TextEditingController(text: widget.initial.model);
    _maxDiffChars = TextEditingController(text: '${widget.initial.maxDiffChars}');
    _locale = widget.locale;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _maxDiffChars.dispose();
    super.dispose();
  }

  void _save() {
    final maxChars = int.tryParse(_maxDiffChars.text.trim());
    if (maxChars == null || maxChars < 0) {
      setState(
        () => _error = I18nController.instance.t('diffLimitInvalid'),
      );
      return;
    }
    final baseUrl = _baseUrl.text.trim();
    final model = _model.text.trim();
    Navigator.of(context).pop(AiConfig(
      baseUrl: baseUrl.isEmpty ? 'https://api.openai.com/v1' : baseUrl,
      apiKey: _apiKey.text.trim(),
      model: model.isEmpty ? 'gpt-4o-mini' : model,
      maxDiffChars: maxChars,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i18n = I18n.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.settings_outlined, size: 22),
          const SizedBox(width: 10),
          Text(i18n.t('settings')),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(context, i18n.t('language')),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: DropdownButton<Locale>(
                  value: _locale,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final option in _languageOptions)
                      DropdownMenuItem(
                        value: option.locale,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _locale = value);
                    widget.onLocaleChanged(value);
                  },
                ),
              ),
              const SizedBox(height: 16),
              _sectionHeader(context, i18n.t('aiProvider')),
              const SizedBox(height: 8),
              TextField(
                controller: _baseUrl,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: i18n.t('baseUrl'),
                  hintText: 'https://api.openai.com/v1',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _apiKey,
                obscureText: true,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: i18n.t('apiKey'),
                  hintText: 'sk-…',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _model,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: i18n.t('model'),
                  hintText: 'gpt-4o-mini',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _maxDiffChars,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: i18n.t('diffLimitLabel'),
                  hintText: '12000',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                i18n.t('settingsFootnote'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(i18n.t('cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(i18n.t('save')),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}
