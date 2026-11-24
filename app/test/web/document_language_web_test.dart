// #144/AK3: the web page names the language the app shows (`<html lang>`). Runs in Chrome
// (flutter test --platform chrome, make test-web).
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;
import 'package:woodshed_player/l10n/app_localizations.dart';
import 'package:woodshed_player/main.dart';

String? get _lang => web.document.documentElement?.getAttribute('lang');

Widget _app(Locale? locale) => MaterialApp(
  locale: locale,
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  localeListResolutionCallback: resolveLocale,
  builder: showLanguage,
  home: const SizedBox(),
);

void main() {
  final start = _lang;
  tearDown(
    () => web.document.documentElement?.setAttribute('lang', start ?? 'en'),
  );

  testWidgets('#144/AK3 <html lang> follows the language shown', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const Locale('de')));
    expect(_lang, 'de');
    await tester.pumpWidget(_app(const Locale('en')));
    expect(_lang, 'en');
  });

  testWidgets('#144/AK3 a system language the app lacks shows English', (
    tester,
  ) async {
    tester.platformDispatcher.localesTestValue = [const Locale('fr', 'FR')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(_app(null));
    expect(_lang, 'en');
    tester.platformDispatcher.localesTestValue = [const Locale('de', 'CH')];
    await tester.pumpAndSettle();
    expect(_lang, 'de');
  });
}
