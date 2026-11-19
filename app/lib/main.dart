// Woodshed Player (Flutter): Bibliothek (#16), Wiedergabe mit Tempo und Loop über den C++-Kern (#15),
// Metronom (#3), Aufnahme des Systemtons (macOS, #4). Oberfläche im Design «Studio» (#30).
// Desktop und Handy nutzen den Kern über FFI, der Browser den WASM-Kern (#34); der bedingte Import wählt.
import 'package:material_ui/material_ui.dart';

import 'app/app_controller.dart';
import 'l10n/app_localizations.dart';
import 'library/library.dart';
import 'app/platform_native.dart'
    if (dart.library.js_interop) 'app/platform_web.dart';
import 'ui/font_licenses.dart';
import 'ui/home_page.dart';
import 'ui/style.dart';

export 'app/platform_native.dart'
    if (dart.library.js_interop) 'app/platform_web.dart'
    show createAppController;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  final controller = await createAppController();
  runApp(
    WoodshedApp(controller: controller, recordingButton: recordingButtonFor),
  );
}

class WoodshedApp extends StatelessWidget {
  const WoodshedApp({
    super.key,
    required this.controller,
    this.recordingButton,
    this.locale,
  });
  final AppController controller;

  /// Fixed UI language (tests); null follows the system language, falling back to English (#43).
  final Locale? locale;

  /// Aufnahme-Knopf, wo es Aufnahme gibt (nur macOS); null sonst.
  final Widget? Function(AppController controller)? recordingButton;

  @override
  Widget build(BuildContext context) {
    // #31: rebuilds when the appearance changes; MaterialApp animates to the new theme.
    return ListenableBuilder(
      listenable: controller.library,
      builder: (context, _) => _app(controller.library.appearance),
    );
  }

  Widget _app(Appearance appearance) {
    return MaterialApp(
      title: 'Woodshed Player',
      locale: locale,
      // Material, Cupertino and widget texts from material_ui (Flutter's own copies are deprecated).
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      localeListResolutionCallback: resolveLocale,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: themeModeFor(appearance),
      home: HomePage(
        controller: controller,
        recordingButton: recordingButton?.call(controller),
      ),
    );
  }
}

final _lightTheme = woodshedTheme(Brightness.light);
final _darkTheme = woodshedTheme(Brightness.dark);

/// #31/AK2, AK3: [Appearance.system] leaves the choice to the platform, also while the app runs.
ThemeMode themeModeFor(Appearance a) => switch (a) {
  Appearance.system => ThemeMode.system,
  Appearance.light => ThemeMode.light,
  Appearance.dark => ThemeMode.dark,
};

/// #43/AK3: the first system language the app has (by language code), otherwise English.
Locale resolveLocale(List<Locale>? preferred, Iterable<Locale> supported) {
  for (final p in preferred ?? const <Locale>[]) {
    for (final s in supported) {
      if (s.languageCode == p.languageCode) return s;
    }
  }
  return const Locale('en');
}
