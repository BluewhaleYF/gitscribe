import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/app_config.dart';
import 'src/home_page.dart';
import 'src/i18n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppConfigStore().load();
  await I18nController.instance.load(_initialLocale(settings.localeCode));
  runApp(const GitScribeApp());
}

Locale _initialLocale(String? savedCode) {
  if (savedCode != null) {
    for (final loc in I18nController.supportedLocales) {
      if ('${loc.languageCode}-${loc.countryCode}' == savedCode) return loc;
    }
  }
  final system =
      WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  return system == 'zh' ? const Locale('zh', 'CN') : const Locale('en', 'US');
}

class GitScribeApp extends StatefulWidget {
  const GitScribeApp({super.key, this.store});

  /// Optional config store; defaults to the user's Application Support file.
  final AppConfigStore? store;

  @override
  State<GitScribeApp> createState() => _GitScribeAppState();
}

class _GitScribeAppState extends State<GitScribeApp> {
  static const _seed = Color(0xFF26A269);

  @override
  void initState() {
    super.initState();
    I18nController.instance.addListener(_handleLocaleChanged);
  }

  @override
  void dispose() {
    I18nController.instance.removeListener(_handleLocaleChanged);
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = I18nController.instance;
    return MaterialApp(
      title: 'GitScribe',
      debugShowCheckedModeBanner: false,
      locale: controller.locale,
      supportedLocales: I18nController.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      builder: (context, child) => I18n(
        locale: controller.locale,
        controller: controller,
        child: child ?? const SizedBox.shrink(),
      ),
      home: HomePage(store: widget.store),
    );
  }
}
