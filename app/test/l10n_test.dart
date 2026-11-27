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

/// Placeholder names used in a message (`{name}`, also inside plural/select); the texts of select and
/// plural cases (`title{Title}`, after a word) are no placeholders (#124).
Set<String> _placeholders(String message) =>
    RegExp(r'(?<!\w)\{(\w+)[,}]')
        .allMatches(message)
        .map((m) => m.group(1)!)
        .toSet();

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

  testWidgets('#144/AK3 the app tells the platform the language it shows', (
    tester,
  ) async {
    final app = TestApp(Directory.systemTemp.createTempSync('wp_l10n'));
    await tester.pumpWidget(
      WoodshedApp(controller: app.controller, locale: const Locale('de')),
    );
    await tester.pumpAndSettle();
    // in the browser `<html lang>`: test/web/document_language_web_test.dart
    final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(material.builder, showLanguage);
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

  group('#43/AK2, #144/AK4 no UI text fixed in code', () {
    // Literal strings with at least two letters in UI positions. Allowed: language-neutral 'mm:ss' and the app name.
    final pattern = RegExp(
      r'''(Text\(\s*|label:\s*|labelText:\s*|tooltip:\s*|title:\s*|hintText:\s*|helperText:\s*|errorText:\s*|message:\s*|semanticLabel:\s*|semanticsLabel:\s*)['"][^'"$]*[A-Za-zÄÖÜäöü]{2}''',
    );
    // #144/AK4: every Dart file under lib/, without the files gen-l10n writes into lib/l10n.
    final files =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.startsWith('lib/l10n/'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    // Files left out on purpose, with the reason. None at the moment: the command line (#140,
    // lib/app/command_line.dart) stays English, but writes its texts to the terminal, not into UI
    // positions; log and error messages of the code are no UI positions either.
    const excluded = <String, String>{};

    test(
      tags: 'repo', // #60: a check of the repository's files, not on Windows
      '#144/AK4 every folder under lib/ is checked',
      () {
        final folders = Directory('lib')
            .listSync()
            .whereType<Directory>()
            .map((d) => d.path)
            .where((d) => d != 'lib/l10n');
        for (final d in folders) {
          expect(
            files.where((f) => f.path.startsWith('$d/')),
            isNotEmpty,
            reason: d,
          );
        }
        expect(files.map((f) => f.path), contains('lib/main.dart'));
        for (final f in excluded.keys) {
          expect(File(f).existsSync(), isTrue, reason: 'excluded: $f');
        }
      },
    );

    test('#144/AK4 the pattern finds fixed texts in both kinds of quotes', () {
      for (final hit in [
        "Text('Library')",
        'tooltip: "Play"',
        "label:\n    'Rename'",
        "semanticsLabel: 'Close'",
      ]) {
        expect(pattern.hasMatch(hit), isTrue, reason: hit);
      }
      for (final ok in ["Text(l.library)", "Text('\$n')", "title: '–'"]) {
        expect(pattern.hasMatch(ok), isFalse, reason: ok);
      }
    });

    for (final f in files.where((f) => !excluded.containsKey(f.path))) {
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

  group('#144/AK2 iOS and macOS name the languages of the ARB files', () {
    final languages = arbFiles.map((n) => n.substring(4, n.length - 4)).toSet();
    for (final plist in ['ios/Runner/Info.plist', 'macos/Runner/Info.plist']) {
      test(plist, () {
        final text = File(plist).readAsStringSync();
        final list = RegExp(
          r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
          dotAll: true,
        ).firstMatch(text);
        expect(list, isNotNull, reason: 'CFBundleLocalizations missing');
        final named = RegExp(r'<string>([^<]+)</string>')
            .allMatches(list![1]!)
            .map((m) => m[1]!.trim())
            .toList();
        expect(named.toSet(), languages);
        expect(named.length, languages.length, reason: 'named twice');
        expect(named, containsAll(['en', 'de']));
      });
    }
  });

  group('#42/AK4 hints without a track name the way files come in', () {
    for (final locale in const [Locale('en'), Locale('de')]) {
      final l = lookupAppLocalizations(locale);
      test('$locale', () {
        // macOS and iOS keep their texts.
        expect(openFileHint(l, HintPlatform.macOS), l.openFileHintDrop);
        expect(openFileHint(l, HintPlatform.mobile), l.openFileHintFiles);
        expect(emptyLibraryHint(l, HintPlatform.macOS), l.emptyLibraryHintDrop);
        expect(emptyLibraryHint(l, HintPlatform.mobile), l.emptyLibraryHint);
        // #60: Windows and Linux: the file dialog, no dragging and no «Files».
        expect(openFileHint(l, HintPlatform.desktop), l.openFileHintDialog);
        expect(emptyLibraryHint(l, HintPlatform.desktop), l.emptyLibraryHint);
        for (final h in [l.openFileHintDialog, l.emptyLibraryHint]) {
          expect(
            h,
            isNot(contains(locale.languageCode == 'de' ? 'zieh' : 'drag')),
          );
        }
        // The browser: its file picker, neither «Files» nor dragging.
        final hints = [
          openFileHint(l, HintPlatform.browser),
          emptyLibraryHint(l, HintPlatform.browser),
        ];
        for (final h in hints) {
          expect(
            h,
            contains(
              locale.languageCode == 'de'
                  ? 'Dateiauswahl des Browsers'
                  : "browser's file picker",
            ),
          );
          expect(
            h,
            isNot(
              contains(locale.languageCode == 'de' ? '«Dateien»' : '“Files”'),
            ),
          );
          expect(
            h,
            isNot(contains(locale.languageCode == 'de' ? 'zieh' : 'drag')),
          );
        }
      });
    }
  });
}
