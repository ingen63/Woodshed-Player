// #148: the help in the app (page with contents and sections) and the overview of the keyboard shortcuts
// (dialog), opened from the Help menu of the Mac, the menu «⋯» of the library and the key «?». AKn = n-th
// acceptance criterion of #148 (20 in all; AK19 is this file). Language fixed (German unless the test is about the language), cores are
// fakes, widgets found by key.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/track_export.dart';
import 'package:woodshed_player/l10n/app_localizations.dart';
import 'package:woodshed_player/main.dart';
import 'package:woodshed_player/ui/help_page.dart';
import 'package:woodshed_player/ui/home_page.dart';
import 'package:woodshed_player/ui/shortcut_table.dart';
import 'package:woodshed_player/ui/style.dart';

import 'fakes.dart';

const desktop = Size(1280, 900);
const tablet = Size(820, 1180);
const phone = Size(390, 844);

Finder byKey(String k) => find.byKey(Key(k));

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);
final _iOS = TargetPlatformVariant.only(TargetPlatform.iOS);

/// The window with three tracks. [plainApp]: without the default shortcuts of MaterialApp (focus moves
/// with Tab and arrows), so that a handled key is one of the app's.
Future<TestApp> pumpHelp(
  WidgetTester tester, {
  Size size = desktop,
  Locale locale = testLocale,
  bool menuBar = false,
  Mp3Encode? mp3,
  String? socket,
  Widget? recordingButton,
  bool plainApp = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dir = Directory.systemTemp.createTempSync('wp_help_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  final app = TestApp(Directory('${dir.path}/lib'), mp3: mp3);
  app.files
    ..hasMenuBar = menuBar
    ..socket = socket;
  await tester.runAsync(() async {
    await app.library.load();
    final src = Directory('${dir.path}/quelle')..createSync();
    await app.library.importFiles([
      for (final t in ['Ärger', 'Bossa', 'Zebra'])
        (File('${src.path}/$t.mp3')..writeAsStringSync('audio $t')).path,
    ]);
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: testDelegates,
      supportedLocales: testLocales,
      theme: woodshedTheme(Brightness.light),
      shortcuts: plainApp ? const <ShortcutActivator, Intent>{} : null,
      home: HomePage(
        controller: app.controller,
        recordingButton: recordingButton,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return app;
}

/// The menus sent to the platform, the last one first (as in menu_bar_test.dart).
List<List<Map<Object?, Object?>>> captureMenus(WidgetTester tester) {
  final sent = <List<Map<Object?, Object?>>>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.menu,
    (call) async {
      if (call.method == 'Menu.setMenus') {
        final menus = (call.arguments as Map<Object?, Object?>)['0']!;
        sent.insert(0, (menus as List).cast<Map<Object?, Object?>>());
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.menu,
      null,
    ),
  );
  return sent;
}

Future<void> selectMenu(WidgetTester tester, Map<Object?, Object?> item) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.menu.name,
    SystemChannels.menu.codec.encodeMethodCall(
      MethodCall('Menu.selectedCallback', item['id']),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

/// Presses «?» as an English keyboard types it (⇧/) or a German one (⇧ß), with [command] held.
Future<bool> pressQuestionMark(
  WidgetTester tester, {
  bool german = false,
  bool command = false,
}) async {
  final cmd = isApplePlatform(defaultTargetPlatform)
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  if (command) await tester.sendKeyDownEvent(cmd);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  final key = german
      ? const LogicalKeyboardKey(0xdf)
      : LogicalKeyboardKey.slash;
  final physical = german
      ? PhysicalKeyboardKey.minus
      : PhysicalKeyboardKey.slash;
  final handled = await tester.sendKeyDownEvent(
    key,
    character: '?',
    physicalKey: physical,
  );
  await tester.sendKeyUpEvent(key, physicalKey: physical);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (command) await tester.sendKeyUpEvent(cmd);
  await tester.pumpAndSettle();
  return handled;
}

Future<void> openMore(WidgetTester tester) async {
  await tester.tap(byKey('libraryMoreMenu'));
  await tester.pumpAndSettle();
}

/// Opens the help through the menu «⋯» of the library.
Future<void> openHelp(WidgetTester tester) async {
  await openMore(tester);
  await tester.tap(byKey('helpButton'));
  await tester.pumpAndSettle();
}

/// The sections the help shows in its contents.
List<String> shownSections() => [
  for (final s in HelpSection.values)
    if (byKey('helpTopic:${s.name}').evaluate().isNotEmpty) s.name,
];

final de = lookupAppLocalizations(const Locale('de'));
final en = lookupAppLocalizations(const Locale('en'));

void main() {
  setUp(() => KeyboardPresence.instance.value = false);

  group('#148/AK1 Help menu on the Mac', () {
    for (final locale in const [Locale('de'), Locale('en')]) {
      testWidgets('items with ⌘? and the search field ($locale)', (
        tester,
      ) async {
        final sent = captureMenus(tester);
        final app = await pumpHelp(tester, locale: locale, menuBar: true);
        final l = lookupAppLocalizations(locale);
        final help = sent.first.last;
        expect(help['label'], l.menuHelp);
        final items = (help['children'] as List).cast<Map<Object?, Object?>>();
        expect(items.map((i) => i['label']), [
          l.helpTitle,
          l.helpShortcutsTitle,
        ]);
        // ⌘? whatever key types «?» (a character, not a key)
        expect(items.first['shortcutCharacter'], '?');
        expect(items.first['shortcutModifiers'], 1 << 0); // meta
        // the native side still makes it the Help menu, where macOS puts its search field
        expect(app.files.menuTitles!['helpMenu'], l.menuHelp);

        await selectMenu(tester, items.first);
        expect(byKey('helpPage'), findsOneWidget);
        expect(find.text(l.helpTitle), findsOneWidget);
        await tester.tap(byKey('helpClose'));
        await tester.pumpAndSettle();
        expect(byKey('helpPage'), findsNothing);

        await selectMenu(tester, items.last);
        expect(byKey('shortcutsDialog'), findsOneWidget);
        await tester.tap(byKey('shortcutsClose'));
        await tester.pumpAndSettle();
        expect(byKey('shortcutsDialog'), findsNothing);
      }, variant: _mac);
    }

    testWidgets('⌘? belongs to the menu on the Mac, in the app elsewhere', (
      tester,
    ) async {
      await pumpHelp(tester, menuBar: true);
      // the menu answers ⌘? natively; the window does not open the help a second time
      expect(await pressQuestionMark(tester, command: true), isFalse);
      expect(byKey('helpPage'), findsNothing);
    }, variant: _mac);
  });

  group('#148/AK2 without a menu bar: «⋯» of the library', () {
    for (final (name, size) in [
      ('desktop', desktop),
      ('tablet', tablet),
      ('phone', phone),
    ]) {
      testWidgets('$name: help always, shortcuts only with a keyboard', (
        tester,
      ) async {
        await pumpHelp(tester, size: size);
        if (size == tablet) {
          await tester.tap(byKey('libraryToggle'));
          await tester.pumpAndSettle();
        }
        await openMore(tester);
        expect(byKey('helpButton'), findsOneWidget);
        expect(
          byKey('shortcutsButton'),
          findsNothing,
        ); // iPad without a key yet
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        await openHelp(tester);
        expect(byKey('helpPage'), findsOneWidget);
        await tester.tap(byKey('helpClose'));
        await tester.pumpAndSettle();

        KeyboardPresence.instance.value =
            true; // a key came: a keyboard is there
        await openMore(tester);
        await tester.tap(byKey('shortcutsButton'));
        await tester.pumpAndSettle();
        expect(byKey('shortcutsDialog'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, variant: _iOS);
    }

    testWidgets('desktop: the shortcuts are there from the start', (
      tester,
    ) async {
      await pumpHelp(tester);
      await openMore(tester);
      expect(byKey('helpButton'), findsOneWidget);
      expect(byKey('shortcutsButton'), findsOneWidget);
    }, variant: _mac);

    testWidgets('Ctrl+? opens the help where there is no menu bar', (
      tester,
    ) async {
      await pumpHelp(tester);
      expect(await pressQuestionMark(tester, command: true), isTrue);
      expect(byKey('helpPage'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  group('#148/AK3 the key «?» opens the shortcuts', () {
    for (final german in [false, true]) {
      testWidgets('${german ? 'German' : 'English'} keyboard, every area', (
        tester,
      ) async {
        final app = await pumpHelp(tester);
        for (final area in AppArea.values) {
          app.controller.setArea(area);
          await tester.pumpAndSettle();
          expect(await pressQuestionMark(tester, german: german), isTrue);
          expect(byKey('shortcutsDialog'), findsOneWidget, reason: '$area');
          await tester.tap(byKey('shortcutsClose'));
          await tester.pumpAndSettle();
        }
      }, variant: _mac);
    }

    testWidgets('not while typing in a text field', (tester) async {
      await pumpHelp(tester);
      await tester.tap(byKey('librarySearch'));
      await tester.pumpAndSettle();
      await pressQuestionMark(tester);
      expect(byKey('shortcutsDialog'), findsNothing);
      await pressQuestionMark(tester, german: true);
      expect(byKey('shortcutsDialog'), findsNothing);
    }, variant: _mac);

    testWidgets('Escape and the close button close help and overview', (
      tester,
    ) async {
      await pumpHelp(tester);
      await pressQuestionMark(tester);
      expect(byKey('shortcutsDialog'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(byKey('shortcutsDialog'), findsNothing);
      await openHelp(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(byKey('helpPage'), findsNothing);
    }, variant: _mac);
  });

  group('#148/AK4–AK12 content of the help (German)', () {
    /// The text of [s] as the page shows it, after a tap on its entry in the contents.
    Future<String> sectionText(WidgetTester tester, HelpSection s) async {
      await tester.tap(byKey('helpTopic:${s.name}'));
      await tester.pumpAndSettle();
      final texts = tester
          .widgetList<SelectableText>(
            find.descendant(
              of: byKey('helpSection:${s.name}'),
              matching: find.byType(SelectableText),
            ),
          )
          .map((t) => t.data!);
      return texts.join('\n\n');
    }

    testWidgets('every section, with the words the criteria ask for', (
      tester,
    ) async {
      await pumpHelp(
        tester,
        mp3: (_, _, {cancel, onProgress}) async => 0,
        socket: '/tmp/wp.sock',
        recordingButton: const SizedBox(key: Key('rec')),
      );
      KeyboardPresence.instance.value = true;
      await openHelp(tester);
      final expected = {
        // AK4
        HelpSection.areas: ['Player', 'Üben', 'Metronom', 'Gewechselt'],
        // AK5
        HelpSection.player: [
          'Zufall',
          'Zurück',
          'Weiter',
          'Wiederholen',
          'Lautstärke',
        ],
        // AK6
        HelpSection.library: [
          'ziehst',
          'Ordner',
          'Unterordner',
          'Sortieren',
          'Suchfeld',
          'Titel und Artist',
          'Mehrere Titel',
          'löscht',
          'Playlists',
        ],
        // AK7
        HelpSection.practice: [
          'Wellenform',
          'Marker S und E',
          'Tonhöhe bleibt gleich',
          'Anfang und Ende abschneiden',
        ],
        // AK8
        HelpSection.metronome: [
          'Taktart',
          'Unterteilung',
          'Tap',
          'nach Zeit',
          'nach Durchgängen',
        ],
        // AK9
        HelpSection.sync: [
          'gekoppelten Geräten',
          'Google Drive',
          'Ohne Konto und ohne gekoppelte Geräte',
        ],
        // AK10
        HelpSection.appearance: ['Hell', 'Dunkel', 'System', 'Sprache'],
        // AK11
        HelpSection.recording: ['Systemton', 'Mikrofon', 'Scharf'],
        HelpSection.export: ['MP3'],
        HelpSection.commandLine: ['woodshed'],
        HelpSection.shortcuts: ['?'],
      };
      for (final MapEntry(key: s, value: words) in expected.entries) {
        final text = await sectionText(tester, s);
        expect(text, helpSectionBody(de, s));
        for (final w in words) {
          expect(text, contains(w), reason: '${s.name}: $w');
        }
      }
      // the section «Shortcuts» opens the overview
      await tester.tap(byKey('helpShowShortcuts'));
      await tester.pumpAndSettle();
      expect(byKey('shortcutsDialog'), findsOneWidget);
    }, variant: _mac);

    testWidgets('AK12 web: install, offline start, audio cache', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: testLocale,
          localizationsDelegates: testDelegates,
          supportedLocales: testLocales,
          home: const HelpPage(topics: HelpTopics(web: true)),
        ),
      );
      await tester.tap(byKey('helpTopic:web'));
      await tester.pumpAndSettle();
      final body = helpSectionBody(de, HelpSection.web);
      for (final w in ['Home-Bildschirm', 'offline', 'Audio-Cache']) {
        expect(body, contains(w));
      }
      expect(find.text(body.split('\n\n').first), findsOneWidget);
    });

    testWidgets('phone: the contents as a list, a tap opens the section', (
      tester,
    ) async {
      await pumpHelp(tester, size: phone);
      await openHelp(tester);
      expect(byKey('helpContents'), findsOneWidget);
      expect(byKey('helpSection:areas'), findsNothing);
      await tester.tap(byKey('helpTopic:metronome'));
      await tester.pumpAndSettle();
      expect(byKey('helpSection:metronome'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(byKey('helpContents'), findsOneWidget);
    }, variant: _iOS);
  });

  group('#148/AK13 sections only where the platform has the feature', () {
    testWidgets('Mac: recording, export and command line, no web', (
      tester,
    ) async {
      await pumpHelp(
        tester,
        mp3: (_, _, {cancel, onProgress}) async => 0,
        socket: '/tmp/wp.sock',
        recordingButton: const SizedBox(key: Key('rec')),
      );
      await openHelp(tester);
      expect(shownSections(), [
        for (final s in HelpSection.values)
          if (s != HelpSection.web) s.name,
      ]);
    }, variant: _mac);

    testWidgets('iPhone/iPad: none of the Mac, no shortcuts without keyboard', (
      tester,
    ) async {
      // the app hands over no recording button, no MP3 encoder and no socket there
      await pumpHelp(tester, size: phone);
      await openHelp(tester);
      expect(shownSections(), [
        'areas',
        'player',
        'library',
        'practice',
        'metronome',
        'sync',
        'appearance',
      ]);
    }, variant: _iOS);

    test('the rules of HelpTopics', () {
      expect(const HelpTopics().sections, [
        HelpSection.areas,
        HelpSection.player,
        HelpSection.library,
        HelpSection.practice,
        HelpSection.metronome,
        HelpSection.sync,
        HelpSection.appearance,
      ]);
      expect(const HelpTopics(web: true, keyboard: true).sections, [
        ...const HelpTopics().sections,
        HelpSection.web,
        HelpSection.shortcuts,
      ]);
      for (final (topics, section) in const [
        (HelpTopics(recording: true), HelpSection.recording),
        (HelpTopics(export: true), HelpSection.export),
        (HelpTopics(commandLine: true), HelpSection.commandLine),
      ]) {
        expect(topics.sections, contains(section));
        expect(topics.sections.length, 8);
      }
    });
  });

  group('#166 command line on Windows and Linux', () {
    Future<String> commandLineText(WidgetTester tester, Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: testDelegates,
          supportedLocales: testLocales,
          home: const HelpPage(topics: HelpTopics(commandLine: true)),
        ),
      );
      await tester.tap(byKey('helpTopic:commandLine'));
      await tester.pumpAndSettle();
      final l = lookupAppLocalizations(locale);
      final body = helpSectionBody(l, HelpSection.commandLine);
      for (final p in body.split('\n\n')) {
        expect(find.text(p), findsOneWidget);
      }
      return body;
    }

    for (final (platform, command, key) in [
      (TargetPlatform.windows, 'WoodshedPlayer play --title', 'Windows'),
      (TargetPlatform.linux, './woodshed-player play --title', 'Linux'),
    ]) {
      for (final locale in testLocales) {
        testWidgets(
          '#166/AK1 #166/AK2 ${platform.name}: the command of the platform and only play '
          '(${locale.languageCode})',
          (tester) async {
            final body = await commandLineText(tester, locale);
            final l = lookupAppLocalizations(locale);
            expect(
              body,
              key == 'Windows'
                  ? l.helpCommandLineBodyWindows
                  : l.helpCommandLineBodyLinux,
            );
            expect(body, contains(command));
            for (final w in ['record', 'tools/woodshed', 'Mac', '~/bin']) {
              expect(body, isNot(contains(w)), reason: w);
            }
          },
          variant: TargetPlatformVariant.only(platform),
        );
      }
    }

    testWidgets('#166 the Mac keeps its text', (tester) async {
      final body = await commandLineText(tester, testLocale);
      expect(body, de.helpCommandLineBody);
      expect(body, contains('tools/woodshed'));
      expect(body, contains('woodshed record'));
    }, variant: _mac);
  });

  group('#148/AK14 overview of the shortcuts', () {
    for (final (platform, command) in [
      (TargetPlatform.macOS, '⌘'),
      (TargetPlatform.iOS, '⌘'),
      (TargetPlatform.windows, 'Ctrl+'),
      (TargetPlatform.android, 'Ctrl+'),
    ]) {
      testWidgets('every row, grouped, with $command on ${platform.name}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            locale: testLocale,
            localizationsDelegates: testDelegates,
            supportedLocales: testLocales,
            theme: woodshedTheme(Brightness.light),
            home: const Scaffold(body: ShortcutsDialog()),
          ),
        );
        for (final g in ShortcutGroup.values) {
          expect(byKey('shortcutGroup:${g.name}'), findsOneWidget);
        }
        for (final row in shortcutTable) {
          final line = byKey('shortcut:${row.action.name}');
          expect(line, findsOneWidget, reason: row.action.name);
          expect(
            find.descendant(
              of: line,
              matching: find.text(shortcutActionLabel(de, row.action)),
            ),
            findsOneWidget,
          );
        }
        String keys(ShortcutAction a) => tester
            .widget<Text>(
              find
                  .descendant(
                    of: byKey('shortcut:${a.name}'),
                    matching: find.byType(Text),
                  )
                  .first,
            )
            .data!;
        final apple = command == '⌘';
        expect(keys(ShortcutAction.open), '${command}O');
        expect(
          keys(ShortcutAction.switchArea),
          '${command}1 / ${command}2 / ${command}3',
        );
        expect(keys(ShortcutAction.newFolder), apple ? '⇧⌘N' : 'Ctrl+Shift+N');
        expect(keys(ShortcutAction.search), '${command}K');
        expect(keys(ShortcutAction.help), '$command?');
        expect(keys(ShortcutAction.shortcuts), '?');
        expect(keys(ShortcutAction.shuffle), apple ? '⌥S' : 'Alt+S');
        expect(keys(ShortcutAction.repeat), apple ? '⌥R' : 'Alt+R');
        expect(keys(ShortcutAction.playerPlayPause), 'Leertaste');
        expect(keys(ShortcutAction.mute), 'M');
        expect(keys(ShortcutAction.previousNext), '$command← / $command→');
        expect(
          keys(ShortcutAction.seek),
          apple ? '⇧⌘← / ⇧⌘→' : 'Ctrl+Shift+← / Ctrl+Shift+→',
        );
        expect(keys(ShortcutAction.volume), '$command↑ / $command↓');
        expect(keys(ShortcutAction.speed), '← / →');
        expect(keys(ShortcutAction.bpm), '↑ / ↓');
        expect(
          keys(ShortcutAction.bpm10),
          apple ? '⇧↑ / ⇧↓' : 'Shift+↑ / Shift+↓',
        );
        expect(keys(ShortcutAction.deleteTrack), 'Entf / Rücktaste');
        expect(keys(ShortcutAction.endSelection), 'Esc');
        expect(keys(ShortcutAction.deleteSelection), 'Entf / Rücktaste');
        expect(
          keys(ShortcutAction.rangeClick),
          apple ? '⇧-Klick' : 'Shift+Klick',
        );
        expect(
          keys(ShortcutAction.toggleClick),
          apple ? '⌘-Klick' : 'Ctrl+Klick',
        );
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(platform));
    }

    test('the overview names what the issue asks for, by group', () {
      Set<ShortcutAction> group(ShortcutGroup g) => {
        for (final r in shortcutTable)
          if (r.group == g) r.action,
      };
      expect(
        group(ShortcutGroup.general),
        containsAll(const [
          ShortcutAction.switchArea,
          ShortcutAction.open,
          ShortcutAction.newFolder,
          ShortcutAction.search,
        ]),
      );
      expect(group(ShortcutGroup.player), const {
        ShortcutAction.playerPlayPause,
        ShortcutAction.shuffle,
        ShortcutAction.repeat,
        ShortcutAction.mute,
        ShortcutAction.previousNext,
        ShortcutAction.seek,
        ShortcutAction.volume,
      });
      expect(group(ShortcutGroup.practice), const {
        ShortcutAction.practicePlayPause,
        ShortcutAction.metronome,
        ShortcutAction.tap,
        ShortcutAction.speed,
        ShortcutAction.bpm,
        ShortcutAction.bpm10,
        ShortcutAction.loopStart,
        ShortcutAction.loopEnd,
        ShortcutAction.deleteTrack,
      });
      expect(group(ShortcutGroup.library), const {
        ShortcutAction.endSelection,
        ShortcutAction.deleteSelection,
        ShortcutAction.rangeClick,
        ShortcutAction.toggleClick,
      });
    });
  });

  group('#148/AK15 the overview and the keys that work agree', () {
    /// Keys pressed in every area: letters, digits and the keys of the table and around them.
    List<(LogicalKeyboardKey, String?, PhysicalKeyboardKey?)> keys() => [
      for (var c = 0x61; c <= 0x7a; c++)
        (LogicalKeyboardKey(c), null, null), // a–z
      for (var c = 0x30; c <= 0x39; c++)
        (LogicalKeyboardKey(c), null, null), // 0–9
      (LogicalKeyboardKey.space, null, null),
      (LogicalKeyboardKey.arrowLeft, null, null),
      (LogicalKeyboardKey.arrowRight, null, null),
      (LogicalKeyboardKey.arrowUp, null, null),
      (LogicalKeyboardKey.arrowDown, null, null),
      (LogicalKeyboardKey.escape, null, null),
      (LogicalKeyboardKey.delete, null, null),
      (LogicalKeyboardKey.backspace, null, null),
      (LogicalKeyboardKey.enter, null, null),
      (LogicalKeyboardKey.tab, null, null),
      (LogicalKeyboardKey.home, null, null),
      (LogicalKeyboardKey.end, null, null),
      (LogicalKeyboardKey.pageUp, null, null),
      (LogicalKeyboardKey.pageDown, null, null),
      (LogicalKeyboardKey.f1, null, null),
      (LogicalKeyboardKey.slash, '/', PhysicalKeyboardKey.slash),
      (LogicalKeyboardKey.comma, ',', PhysicalKeyboardKey.comma),
      (LogicalKeyboardKey.period, '.', PhysicalKeyboardKey.period),
      // «?» on an English keyboard, and on a German one where the test can simulate its key (macOS)
      (LogicalKeyboardKey.slash, '?', PhysicalKeyboardKey.slash),
      if (defaultTargetPlatform == TargetPlatform.macOS)
        (const LogicalKeyboardKey(0xdf), '?', PhysicalKeyboardKey.minus),
    ];
    const modifiers = [
      (command: false, shift: false, alt: false),
      (command: false, shift: true, alt: false),
      (command: false, shift: false, alt: true),
      (command: false, shift: true, alt: true),
      (command: true, shift: false, alt: false),
      (command: true, shift: true, alt: false),
      (command: true, shift: false, alt: true),
    ];

    String describe(
      LogicalKeyboardKey key,
      String? character,
      ({bool command, bool shift, bool alt}) m,
    ) =>
        '${m.command ? 'cmd+' : ''}${m.shift ? 'shift+' : ''}${m.alt ? 'alt+' : ''}'
        '${character == null ? key.keyLabel : '$character (${key.keyLabel})'}';

    bool listed(
      Iterable<ShortcutGroup> groups,
      LogicalKeyboardKey key,
      String? character,
      ({bool command, bool shift, bool alt}) m,
    ) => shortcutTable
        .where((r) => groups.contains(r.group))
        .expand((r) => r.keys)
        .any(
          (k) =>
              !k.isClick &&
              (k.character != null
                  ? k.character == character
                  : k.trigger == key && character != '?') &&
              k.command == m.command &&
              (k.shift == null || k.shift == m.shift) &&
              (k.alt == null || k.alt == m.alt),
        );

    /// Presses every key with every modifier in [area] and returns the ones the app handled; after each,
    /// dialogs close and area, focus and metronome go back.
    Future<Set<String>> handledIn(
      WidgetTester tester,
      TestApp app,
      AppArea area, {
      required FocusNode Function() focus,
      Future<void> Function()? reset,
    }) async {
      final c = app.controller;
      final handled = <String>{};
      final command = isApplePlatform(defaultTargetPlatform)
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      Future<void> restore() async {
        await tester.pumpAndSettle();
        final home = find.byKey(const Key('shortcuts'), skipOffstage: false);
        Navigator.of(tester.element(home)).popUntil((r) => r.isFirst);
        await tester.pumpAndSettle();
        if (c.metronome.running) c.metronome.toggle();
        c.setArea(area);
        await tester.pumpAndSettle();
        await reset?.call();
        focus().requestFocus();
        await tester.pump();
      }

      await restore();
      for (final (key, character, physical) in keys()) {
        for (final m in modifiers) {
          final mods = [
            if (m.command) command,
            if (m.shift) LogicalKeyboardKey.shiftLeft,
            if (m.alt) LogicalKeyboardKey.altLeft,
          ];
          for (final k in mods) {
            await tester.sendKeyDownEvent(k);
          }
          final ok = await tester.sendKeyDownEvent(
            key,
            character: character,
            physicalKey: physical,
          );
          await tester.sendKeyUpEvent(key, physicalKey: physical);
          for (final k in mods.reversed) {
            await tester.sendKeyUpEvent(k);
          }
          if (ok) {
            handled.add(describe(key, character, m));
            await restore();
          }
        }
      }
      return handled;
    }

    Set<String> expectedIn(Iterable<ShortcutGroup> groups) => {
      for (final (key, character, _) in keys())
        for (final m in modifiers)
          if (listed(groups, key, character, m)) describe(key, character, m),
    };

    FocusNode shortcutsNode(WidgetTester tester) => Focus.of(
      tester.element(
        find
            .descendant(of: byKey('shortcuts'), matching: find.byType(Scaffold))
            .first,
      ),
    );

    for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
      testWidgets('Player, Practice, Metronome on ${platform.name}', (
        tester,
      ) async {
        final app = await pumpHelp(tester, plainApp: true);
        for (final (area, group) in const [
          (AppArea.player, ShortcutGroup.player),
          (AppArea.practice, ShortcutGroup.practice),
          (AppArea.metronome, ShortcutGroup.practice),
        ]) {
          final handled = await handledIn(
            tester,
            app,
            area,
            focus: () => shortcutsNode(tester),
          );
          final expected = expectedIn([ShortcutGroup.general, group]);
          expect(
            handled.difference(expected),
            isEmpty,
            reason: '$area: works, but missing in the overview',
          );
          expect(
            expected.difference(handled),
            isEmpty,
            reason: '$area: in the overview, but does not work',
          );
        }
      }, variant: TargetPlatformVariant.only(platform));
    }

    testWidgets('library with a selection', (tester) async {
      final app = await pumpHelp(tester, plainApp: true);
      Future<void> selectOne() async {
        if (find.text(de.selectionCount(1)).evaluate().isNotEmpty) return;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.tap(byKey('track:Bossa'));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();
      }

      FocusNode? library;
      final handled = await handledIn(
        tester,
        app,
        AppArea.player,
        focus: () => library!,
        reset: () async {
          final before = find.text(de.selectionCount(1)).evaluate().isEmpty;
          await selectOne();
          if (before) library = FocusManager.instance.primaryFocus;
        },
      );
      final expected = expectedIn(const [
        ShortcutGroup.general,
        ShortcutGroup.player,
        ShortcutGroup.library,
      ]);
      expect(handled.difference(expected), isEmpty);
      expect(expected.difference(handled), isEmpty);
    }, variant: _mac);

    testWidgets('⇧-click and ⌘-click select in the library', (tester) async {
      await pumpHelp(tester);
      Future<void> clickWith(LogicalKeyboardKey key, String title) async {
        await tester.sendKeyDownEvent(key);
        await tester.tap(byKey('track:$title'));
        await tester.sendKeyUpEvent(key);
        await tester.pumpAndSettle();
      }

      await clickWith(LogicalKeyboardKey.metaLeft, 'Ärger');
      expect(find.text(de.selectionCount(1)), findsOneWidget);
      await clickWith(LogicalKeyboardKey.shiftLeft, 'Zebra');
      expect(find.text(de.selectionCount(3)), findsOneWidget);
    }, variant: _mac);
  });

  group('#148/AK16 every ARB file has every help text', () {
    Map<String, Object?> arb(String name) =>
        jsonDecode(File('lib/l10n/$name').readAsStringSync())
            as Map<String, Object?>;
    final template = arb('app_en.arb');
    final helpKeys = template.keys.where((k) => k.startsWith('help')).toSet();
    final files =
        Directory('lib/l10n')
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where((n) => n.endsWith('.arb'))
            .toList()
          ..sort();

    test('the help has its texts in the template', () {
      for (final s in HelpSection.values) {
        expect(helpKeys, contains('help${_cap(s.name)}Title'));
        expect(helpKeys, contains('help${_cap(s.name)}Body'));
      }
      expect(helpKeys.length, greaterThan(40));
    });

    for (final name in files) {
      test(name, () {
        final texts = arb(name);
        for (final k in helpKeys) {
          expect(texts[k], isA<String>(), reason: '$name: $k');
          expect((texts[k]! as String).trim(), isNotEmpty, reason: k);
        }
      });
    }

    test('German and English differ in every section', () {
      for (final s in HelpSection.values) {
        expect(helpSectionBody(de, s), isNot(helpSectionBody(en, s)));
      }
    });
  });

  group('#148/AK17 the help in the UI language', () {
    for (final (system, title) in [
      (const Locale('de', 'CH'), 'Woodshed Player-Hilfe'),
      (const Locale('en', 'US'), 'Woodshed Player Help'),
      (const Locale('fr', 'FR'), 'Woodshed Player Help'),
    ]) {
      testWidgets('system $system', (tester) async {
        tester.platformDispatcher.localesTestValue = [system];
        addTearDown(tester.platformDispatcher.clearLocalesTestValue);
        tester.view.physicalSize = desktop;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final dir = Directory.systemTemp.createTempSync('wp_help_lang');
        addTearDown(() => dir.deleteSync(recursive: true));
        final app = TestApp(Directory('${dir.path}/lib'));
        await tester.runAsync(app.library.load);
        await tester.pumpWidget(WoodshedApp(controller: app.controller));
        await tester.pumpAndSettle();
        await openHelp(tester);
        expect(find.text(title), findsOneWidget);
      });
    }
  });

  test('#148/AK18 the help loads nothing from the network', () {
    for (final f in ['lib/ui/help_page.dart', 'lib/ui/shortcut_table.dart']) {
      final source = File(f).readAsStringSync();
      for (final banned in [
        'http',
        'dart:io',
        'url_launcher',
        'Image.network',
        'NetworkImage',
        'openUrl',
        'rootBundle',
      ]) {
        expect(source, isNot(contains(banned)), reason: '$f: $banned');
      }
    }
  });

  test('#148/AK20 FUNKTIONEN.md and both READMEs name the help', () {
    final functions = File('../docs/FUNKTIONEN.md').readAsStringSync();
    final practice = functions
        .split('\n')
        .firstWhere((l) => l.startsWith('| Üben und Metronom'));
    expect(practice, contains('Entf'));
    expect(practice, contains('Rücktaste'));
    expect(functions, contains('#148'));
    expect(File('../README.md').readAsStringSync(), contains('built-in help'));
    expect(
      File('../README.de.md').readAsStringSync(),
      contains('eingebaute Hilfe'),
    );
  });
}

String _cap(String s) => s[0].toUpperCase() + s.substring(1);
