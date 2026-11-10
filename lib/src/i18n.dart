import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart'
    show BuildContext, InheritedWidget, Locale;

/// Holds the loaded translation catalogs and the currently active locale.
///
/// Catalogs are plain JSON files under `assets/i18n/` keyed by camelCase
/// string keys. Text is fetched with [t]; `{name}` placeholders are replaced
/// from an optional [args] map.
class I18nController extends ChangeNotifier {
  I18nController._();

  static final I18nController instance = I18nController._();

  static const List<Locale> supportedLocales = [
    Locale('en', 'US'),
    Locale('zh', 'CN'),
  ];

  final Map<String, Map<String, String>> _catalogs = {};
  Locale _locale = supportedLocales.first;
  Locale get locale => _locale;

  bool get isLoaded => _catalogs.isNotEmpty;

  /// Loads every catalog and sets the initial [locale].
  Future<void> load(Locale locale) async {
    for (final loc in supportedLocales) {
      final code = '${loc.languageCode}-${loc.countryCode}';
      final raw = await rootBundle.loadString('assets/i18n/$code.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _catalogs[loc.languageCode] =
          decoded.map((key, value) => MapEntry(key, value.toString()));
    }
    _locale = _resolve(locale);
    notifyListeners();
  }

  void setLocale(Locale locale) {
    final resolved = _resolve(locale);
    if (resolved == _locale) return;
    _locale = resolved;
    notifyListeners();
  }

  Locale _resolve(Locale locale) {
    for (final supported in supportedLocales) {
      if (supported.languageCode == locale.languageCode) return supported;
    }
    return supportedLocales.first;
  }

  /// Returns the translated string for [key], substituting `{name}` placeholders
  /// from [args]. Falls back to English, then to the key itself.
  String t(String key, [Map<String, String>? args]) {
    var text = _catalogs[_locale.languageCode]?[key] ??
        _catalogs['en']?[key] ??
        key;
    if (args != null) {
      args.forEach((name, value) {
        text = text.replaceAll('{$name}', value);
      });
    }
    return text;
  }
}

/// Exposes an [I18nController] to the widget tree and rebuilds dependents when
/// the locale changes.
class I18n extends InheritedWidget {
  const I18n({
    super.key,
    required this.locale,
    required this.controller,
    required super.child,
  });

  final Locale locale;
  final I18nController controller;

  static I18nController of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<I18n>();
    return widget?.controller ?? I18nController.instance;
  }

  @override
  bool updateShouldNotify(I18n oldWidget) => locale != oldWidget.locale;
}
