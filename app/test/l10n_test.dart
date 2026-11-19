// Multilingual UI (#43): ARB files, system language with English fallback, locale formats, no fixed texts.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/main.dart';
import 'package:woodshed_player/ui/messages.dart';

import 'fakes.dart';

Map<String, Object?> _arb(String name) =>
    jsonDecode(File('lib/l10n/$name').readAsStringSync())
        as Map<String, Object?>;

Set<String> _keys(Map<String, Object?> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

/// Placeholder names used in a message (`{name}`, also inside plural/select).
Set<String> _placeholders(String message) =>
    RegExp(r'\{(\w+)[,}]').allMatches(message).map((m) => m.group(1)!).toSet();

void main() {
  final arbFiles =
      Directory('lib/l10n')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.arb'))
          .toList()
        ..sort();
  final en = lookupAppLocalizations(const Locale('en'));

  group('#43/AK1 gen-l10n set up', () {
    test('l10n.yaml with app_en.arb as template, app_de.arb present', () {
      final yaml = File('l10n.yaml').readAsStringSync();
      expect(yaml, contains('arb-dir: lib/l10n'));
      expect(yaml, contains('template-arb-file: app_en.arb'));
      expect(arbFiles, containsAll(['app_en.arb', 'app_de.arb']));
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('flutter_localizations:'));
      expect(pubspec, contains('generate: true'));
    });

    test('supported languages are English and German', () {
      expect(
        AppLocalizations.supportedLocales.map((l) => l.languageCode),
        unorderedEquals(['en', 'de']),
      );
    });
  });

  group('#43/AK5 every key in every ARB file', () {
    final template = _arb('app_en.arb');
    for (final name in arbFiles) {
      test(name, () {
        final arb = _arb(name);
        expect(arb['@@locale'], name.substring(4, name.length - 4));
        final missing = _keys(template).difference(_keys(arb));
        final extra = _keys(arb).difference(_keys(template));
        expect(missing, isEmpty, reason: 'missing in $name');
        expect(extra, isEmpty, reason: 'not in the template: $name');
        for (final k in _keys(template)) {
          expect(
            _placeholders(arb[k]! as String),
            _placeholders(template[k]! as String),
            reason: 'placeholders of «$k» in $name',
          );
          expect(
            (arb[k]! as String).trim(),
            isNotEmpty,
            reason: '«$k» in $name',
          );
        }
      });
    }
  });

  group('#43/AK3 system language, English fallback', () {
    const supported = AppLocalizations.supportedLocales;
    test('resolveLocale', () {
      expect(
        resolveLocale([const Locale('de', 'CH')], supported).languageCode,
        'de',
      );
      expect(
        resolveLocale([const Locale('en', 'GB')], supported).languageCode,
        'en',
      );
      expect(
        resolveLocale([const Locale('fr')], supported),
        const Locale('en'),
      );
      expect(
        resolveLocale([
          const Locale('fr'),
          const Locale('de'),
        ], supported).languageCode,
        'de',
      );
      expect(resolveLocale(null, supported), const Locale('en'));
      expect(resolveLocale(const [], supported), const Locale('en'));
    });

    for (final (system, expected) in [
      (const Locale('de', 'CH'), 'Bibliothek'),
      (const Locale('en', 'US'), 'Library'),
      (const Locale('fr', 'FR'), 'Library'),
    ]) {
      testWidgets('system $system → «$expected»', (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.localesTestValue = [system];
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);
        final app = TestApp(Directory.systemTemp.createTempSync('wp_l10n'));
        await tester.pumpWidget(WoodshedApp(controller: app.controller));
        await tester.pumpAndSettle();
        expect(find.text(expected), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('#43/AK5 the UI renders in both languages', () {
    for (final (locale, texts) in [
      (
        const Locale('en'),
        ['Library', 'No tracks', 'No track selected', 'Open file', 'Add MP3'],
      ),
      (
        const Locale('de'),
        [
          'Bibliothek',
          'Keine Titel',
          'Kein Titel ausgewählt',
          'Datei öffnen',
          'MP3 hinzufügen',
        ],
      ),
    ]) {
      testWidgets('$locale', (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final app = TestApp(Directory.systemTemp.createTempSync('wp_l10n'));
        await tester.pumpWidget(
          WoodshedApp(controller: app.controller, locale: locale),
        );
        await tester.pumpAndSettle();
        for (final t in texts) {
          expect(find.text(t), findsWidgets, reason: '$locale: $t');
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('#43/AK4 numbers and sizes follow the locale', () {
    test('sizes', () {
      expect(formatBytes(1234567890, 'de'), '1,2 GB');
      expect(formatBytes(1234567890, 'en'), '1.2 GB');
      expect(formatBytes(512, 'en'), '512 B');
    });

    test('speed, presets, loop length', () {
      expect(de.rate(0.75), '0,75×');
      expect(en.rate(0.75), '0.75×');
      expect(formatPreset(0.75, 'de'), '0,75');
      expect(formatPreset(1, 'de'), '1,0');
      expect(formatPreset(1, 'en'), '1.0');
      expect(de.loopLength(6), '6,0 s');
      expect(en.loopLength(6), '6.0 s');
    });

    test('plural in both languages', () {
      expect(de.rampSummary(5, 1), '+5 % nach 1 Durchgang');
      expect(de.rampSummary(5, 10), '+5 % nach 10 Durchgängen');
      expect(en.rampSummary(5, 1), '+5% after 1 pass');
      expect(en.rampSummary(5, 10), '+5% after 10 passes');
    });
  });

  group('#43/AK2 no UI text fixed in code', () {
    // Literal strings with at least two letters in UI positions. Allowed: language-neutral 'mm:ss' and the app name.
    final pattern = RegExp(
      r'''(Text\(\s*|label:\s*|tooltip:\s*|title:\s*|hintText:\s*|message:\s*|semanticLabel:\s*)'[^'$]*[A-Za-zÄÖÜäöü]{2}''',
    );
    final files = [
      ...Directory('lib/ui').listSync(),
      ...Directory('lib/metronome').listSync(),
      File('lib/main.dart'),
    ].whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      test(f.path, () {
        final hits = pattern
            .allMatches(f.readAsStringSync())
            .map((m) => m.group(0)!)
            .where(
              (h) => !h.contains("'mm:ss") && !h.contains("'Woodshed Player"),
            )
            .toList();
        expect(hits, isEmpty);
      });
    }
  });
}
