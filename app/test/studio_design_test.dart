// Design «Studio» (#30). AKn = n-tes Abnahmekriterium im Issue #30.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/main.dart';
import 'package:woodshed_player/ui/home_page.dart';
import 'package:woodshed_player/time_format.dart';
import 'package:woodshed_player/ui/style.dart';
import 'package:woodshed_player/ui/timeline.dart';

import 'fakes.dart';
import 'home_page_test.dart' show pumpApp, select;

const desktop = Size(1280, 900);
const tablet = Size(820, 1180);
const phone = Size(390, 844);

Future<void> setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pump();
}

/// Titel wählen; am Tablet vorher die Bibliothek einblenden.
Future<void> choose(WidgetTester tester, TestApp app, String title) async {
  final toggle = find.byKey(const Key('libraryToggle'));
  if (toggle.evaluate().isNotEmpty) {
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }
  await select(tester, app, title);
  await tester.pumpAndSettle();
}

double top(WidgetTester t, String key) => t.getTopLeft(find.byKey(Key(key))).dy;

void main() {
  setUp(() => KeyboardPresence.instance.value = false);

  group('#30/AK1 Theme an einer Stelle', () {
    test('keine Farbwerte ausserhalb von ui/style.dart', () {
      final offenders = <String>[];
      final colorLiteral = RegExp(r'\bColors\.|\bColor\(|Color\.from');
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('ui/style.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (colorLiteral.hasMatch(lines[i])) {
            offenders.add('${f.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty);
    });

    test('ThemeExtension in beiden Helligkeiten', () {
      for (final b in Brightness.values) {
        expect(woodshedTheme(b).extension<WsTheme>(), isNotNull);
        expect(woodshedTheme(b).textTheme.bodyMedium?.fontFamily, textFont);
      }
    });
  });

  group('#30/AK2 Farben', () {
    test('Dunkel wie im Mockup', () {
      final d = woodshedTheme(Brightness.dark);
      final ws = d.extension<WsTheme>()!;
      expect(ws.bg, const Color(0xFF121214));
      expect(ws.panel, const Color(0xFF1C1C1F));
      expect(ws.border, const Color(0xFF2C2C30));
      expect(ws.amber, const Color(0xFFFF9F0A));
      expect(ws.blue, const Color(0xFF4DA3FF));
      expect(d.scaffoldBackgroundColor, const Color(0xFF121214));
    });

    test('Hell wie im Mockup', () {
      final ws = woodshedTheme(Brightness.light).extension<WsTheme>()!;
      expect(ws.bg, const Color(0xFFECECEF));
      expect(ws.panel, const Color(0xFFFFFFFF));
      expect(ws.border, const Color(0xFFD4D4D9));
      expect(ws.amber, const Color(0xFFA85F00));
      expect(ws.blue, const Color(0xFF0A63C2));
    });

    testWidgets('Hell/Dunkel folgt der Systemeinstellung', (tester) async {
      final app = TestApp(Directory.systemTemp.createTempSync('wp_theme'));
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      // #149: the default is Dark; this test is about the choice System
      app.library.appearance = Appearance.system;
      for (final (b, bg) in [
        (Brightness.dark, const Color(0xFF121214)),
        (Brightness.light, const Color(0xFFECECEF)),
      ]) {
        tester.platformDispatcher.platformBrightnessTestValue = b;
        await tester.pumpWidget(
          WoodshedApp(controller: app.controller, locale: testLocale),
        );
        await tester.pumpAndSettle();
        final ctx = tester.element(find.byType(HomePage));
        expect(Theme.of(ctx).scaffoldBackgroundColor, bg, reason: '$b');
      }
      final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(material.themeMode, ThemeMode.system);
    });
  });

  group('#30/AK3 Schriften', () {
    test('Inter und JetBrains Mono mit Lizenz im Paket', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: Inter'));
      expect(pubspec, contains('family: JetBrains Mono'));
      expect(File('assets/fonts/inter/OFL.txt').existsSync(), isTrue);
      expect(File('assets/fonts/jetbrains-mono/OFL.txt').existsSync(), isTrue);
    });

    testWidgets(
      'Zeiten, Tempo und BPM in JetBrains Mono, gleich breite Ziffern',
      (tester) async {
        final loader = FontLoader(numberFont)
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/jetbrains-mono/JetBrainsMono-Medium.ttf')
                    .readAsBytesSync(),
              ),
            ),
          );
        await loader.load();

        final app = await pumpApp(tester, size: desktop);
        await choose(tester, app, 'Bossa');
        // #115/AK5: the BPM is in the area Metronome
        app.controller.setArea(AppArea.metronome);
        await tester.pump();
        final bpm = tester.widget<Text>(find.byKey(const Key('metronomeBpm')));
        expect(bpm.style?.fontFamily, numberFont);
        app.controller.setArea(AppArea.practice);
        await tester.pump();
        for (final key in ['clock', 'speedValue', 'time:Anfang']) {
          final texts = find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byWidgetPredicate(
              (w) => w is RichText || w is EditableText,
            ),
            matchRoot: true,
          );
          final w = tester.widget(texts.first);
          final style = w is RichText
              ? w.text.style
              : (w as EditableText).style;
          expect(style?.fontFamily, numberFont, reason: key);
          expect(
            style?.fontFeatures,
            contains(const FontFeature.tabularFigures()),
            reason: key,
          );
        }
        // Mit der echten Schrift: «11:11.1» ist so breit wie «00:00.0».
        double width(String s) {
          final p = TextPainter(
            text: TextSpan(text: s, style: WsTheme.dark.number(20)),
            textDirection: TextDirection.ltr,
          )..layout();
          return p.width;
        }

        expect(width('11:11.1'), closeTo(width('00:00.0'), 0.01));
        expect(width('1,00×'), closeTo(width('0,75×'), 0.01));
      },
    );
  });

  group('#30/AK4 Grössen nach Fensterbreite', () {
    test('Grenzen 600 und 1000', () {
      expect(WsSize.forWidth(1001), WsSize.desktop);
      expect(WsSize.forWidth(1000), WsSize.tablet);
      expect(WsSize.forWidth(600), WsSize.tablet);
      expect(WsSize.forWidth(599), WsSize.phone);
    });

    testWidgets(
      'Desktop: feste Bibliothek im Player, Module nebeneinander im Üben',
      (tester) async {
        final app = await pumpApp(tester, size: desktop);
        await choose(tester, app, 'Bossa');
        expect(find.byKey(const Key('layout:desktop')), findsOneWidget);
        final y = top(tester, 'card:speed');
        expect(top(tester, 'card:ramp'), y);
        expect(find.byKey(const Key('module:metronome')), findsNothing);
        // #115: the library stays beside the area Player
        app.controller.setArea(AppArea.player);
        await tester.pump();
        expect(
          tester.getTopLeft(find.byKey(const Key('track:Bossa'))).dx,
          lessThan(tester.getTopLeft(find.byKey(const Key('playerScreen'))).dx),
        );
      },
    );

    testWidgets('Tablet: Bibliothek einblendbar, zwei Spalten', (tester) async {
      final app = await pumpApp(tester, size: tablet);
      expect(find.byKey(const Key('layout:tablet')), findsOneWidget);
      expect(find.byKey(const Key('track:Bossa')), findsNothing);
      await tester.tap(find.byKey(const Key('libraryToggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('track:Bossa')), findsOneWidget);
      await select(tester, app, 'Bossa');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('track:Bossa')), findsNothing); // zu
      final y = top(tester, 'card:speed');
      expect(top(tester, 'card:ramp'), y);
      expect(find.byKey(const Key('module:metronome')), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('card:speed'))).width,
        lessThan(tablet.width / 2),
      );
    });

    testWidgets('Phone: einspaltig, Bibliothek eigene Seite, S/Play/E unten', (
      tester,
    ) async {
      final app = await pumpApp(tester, size: phone);
      expect(find.byKey(const Key('layout:phone')), findsOneWidget);
      expect(find.byKey(const Key('card:speed')), findsNothing);
      await choose(tester, app, 'Bossa');
      expect(find.byKey(const Key('track:Bossa')), findsNothing);
      final bar = tester.getRect(find.byKey(const Key('thumbBar')));
      // #115: directly above the tab bar of the areas
      expect(
        bar.bottom,
        closeTo(tester.getRect(find.byKey(const Key('areaTabBar'))).top, 1),
      );
      for (final k in ['here:Anfang', 'playPause', 'here:Ende']) {
        final r = tester.getRect(find.byKey(Key(k)));
        expect(bar.contains(r.center), isTrue, reason: k);
      }
      final xs = [
        'here:Anfang',
        'playPause',
        'here:Ende',
      ].map((k) => tester.getCenter(find.byKey(Key(k))).dx).toList();
      expect(xs, orderedEquals([...xs]..sort()));
      expect(
        tester.getSize(find.byKey(const Key('card:speed'))).width,
        greaterThan(phone.width - 40),
      );
    });
  });

  testWidgets(
    '#30/AK5 Breitenwechsel über die Grenzen verliert weder Wiedergabe noch Loop',
    (tester) async {
      final app = await pumpApp(tester, size: desktop);
      await choose(tester, app, 'Bossa');
      app.player.setLoopStart(4);
      app.player.setLoopEnd(9);
      await tester.tap(find.byKey(const Key('playPause')));
      await tester.pump();
      expect(app.player.isPlaying, isTrue);
      final calls = app.core.calls.length;
      for (final size in [tablet, phone, tablet, desktop, phone]) {
        await setSize(tester, size);
        app.tick();
        await tester.pump();
        expect(app.player.isPlaying, isTrue, reason: '$size');
        expect(app.core.loop, (4.0, 9.0), reason: '$size');
      }
      expect(app.core.calls.skip(calls), isNot(contains('pause')));
      expect(find.byKey(const Key('layout:phone')), findsOneWidget);
    },
  );

  group('#30/AK6 Loop-Bereich', () {
    testWidgets('Marker S und E ziehbar, Anzeige «Start → Ende» in mm:ss.d', (
      tester,
    ) async {
      final app = await pumpApp(tester, size: desktop);
      app.core.hasWaveform = true;
      await choose(tester, app, 'Bossa');
      app.player.setLoopStart(5);
      app.player.setLoopEnd(12.5);
      await tester.pump();
      expect(find.text('00:05.0'), findsOneWidget);
      expect(find.text('→'), findsOneWidget);
      expect(find.text('00:12.5'), findsOneWidget);

      final detail = tester.getRect(find.byKey(const Key('waveformDetail')));
      final start = find.byKey(const Key('loopStartMarker'));
      expect(start, findsOneWidget);
      final g = await tester.startGesture(tester.getCenter(start));
      await g.moveBy(const Offset(20, 0));
      await tester.pump();
      await g.moveBy(Offset(detail.width / 20, 0));
      await tester.pump();
      final moved = app.player.settings.loopStart;
      expect(moved, greaterThan(5));
      expect(find.text(formatTimePrecise(moved)), findsOneWidget);
      await g.up();
      await tester.pump();
      expect(app.core.loop!.$1, closeTo(moved, 1e-9));

      final end = find.byKey(const Key('loopEndMarker'));
      final g2 = await tester.startGesture(tester.getCenter(end));
      await g2.moveBy(const Offset(-20, 0));
      await tester.pump();
      await g2.moveBy(Offset(-detail.width / 20, 0));
      await tester.pump();
      await g2.up();
      await tester.pump();
      expect(app.player.settings.loopEnd, lessThan(12.5));
    });
  });

  group('#30/AK7 Tempo', () {
    testWidgets('grösstes Zahlenelement, Schnellwahl 0,5 / 0,75 / 0,8 / 1,0', (
      tester,
    ) async {
      for (final size in [desktop, tablet, phone]) {
        final app = await pumpApp(tester, size: size);
        await choose(tester, app, 'Bossa');
        final tempo = tester.widget<Text>(find.byKey(const Key('speedValue')));
        final sizes = tester
            .widgetList<RichText>(find.byType(RichText))
            .map((r) => r.text.style)
            .where((s) => s?.fontFamily == numberFont)
            .map((s) => s!.fontSize ?? 0);
        expect(
          tempo.style!.fontSize,
          sizes.reduce((a, b) => a > b ? a : b),
          reason: '$size',
        );
        expect(
          [
            for (final w in tester.widgetList(
              find.byWidgetPredicate((w) => '${w.key}'.contains("'preset:")),
            ))
              '${w.key}',
          ],
          [
            "[<'preset:0.5'>]",
            "[<'preset:0.75'>]",
            "[<'preset:0.8'>]",
            "[<'preset:1.0'>]",
          ],
        );
        app.player.setSpeedEnabled(true);
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('preset:0.75')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('preset:0.75')));
        await tester.pump();
        expect(app.player.settings.speed, 0.75);
        expect(find.text('0,75×'), findsWidgets);
      }
    });
  });

  group('#30/AK8 Touch-Ziele', () {
    for (final (platform, min) in [
      (TargetPlatform.iOS, 44.0),
      (TargetPlatform.android, 48.0),
    ]) {
      for (final size in [tablet, phone]) {
        testWidgets('${platform.name} ${size.width.round()}: mindestens $min', (
          tester,
        ) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          final app = await pumpApp(tester, size: size, titles: ['Bossa']);
          app.core.hasWaveform = true;
          await choose(tester, app, 'Bossa');
          app.player.setLoopStart(5);
          app.player.setLoopEnd(15);
          app.player.setRamp(enabled: true);
          await tester.pump();
          final targets = find.byWidgetPredicate(
            (w) =>
                w is ButtonStyleButton ||
                w is IconButton ||
                w is Switch ||
                w is DropdownButton ||
                w is LoopMarker,
          );
          expect(targets, findsWidgets);
          final small = <String>[];
          for (final e in targets.evaluate()) {
            final box = e.renderObject as RenderBox?;
            if (box == null || !box.hasSize || !box.attached) continue;
            final s = box.size;
            if (s.width + 0.01 < min || s.height + 0.01 < min) {
              small.add('${e.widget.runtimeType} ${e.widget.key} $s');
            }
          }
          expect(small, isEmpty);
        });
      }
    }
  });

  group('#30/AK9 Kürzel-Badges', () {
    Future<List<String>> badges(WidgetTester tester) async => [
      for (final t in tester.widgetList<Text>(
        find.byKey(const Key('shortcutBadge')),
      ))
        t.data!,
    ];

    testWidgets('macOS: ⌘', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpApp(tester, size: desktop);
      expect(await badges(tester), contains('⌘O'));
    });

    for (final p in [TargetPlatform.windows, TargetPlatform.linux]) {
      testWidgets('${p.name}: Ctrl', (tester) async {
        debugDefaultTargetPlatformOverride = p;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await pumpApp(tester, size: desktop);
        expect(await badges(tester), contains('Ctrl+O'));
        expect((await badges(tester)).join(), isNot(contains('⌘')));
      });
    }

    testWidgets('iPad: keine Badges ohne Tastatur, mit Tastatur ⌘', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final app = await pumpApp(tester, size: tablet);
      await choose(tester, app, 'Bossa');
      expect(await badges(tester), isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      final b = await badges(tester);
      expect(b, containsAll(['S', 'E']));
      app.player.unload();
      await tester.pump();
      expect(await badges(tester), contains('⌘O'));
    });
  });

  group('#30/AK10 Aufnahme-Knopf', () {
    for (final (p, visible) in [
      (TargetPlatform.macOS, true),
      (TargetPlatform.windows, true),
      (TargetPlatform.linux, true),
      (TargetPlatform.iOS, false),
      (TargetPlatform.android, false),
    ]) {
      for (final size in [desktop, tablet]) {
        testWidgets('${p.name} ${size.width.round()}: '
            '${visible ? 'sichtbar' : 'nicht sichtbar'}', (tester) async {
          debugDefaultTargetPlatformOverride = p;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          final app = await pumpApp(tester, size: size);
          await tester.pumpWidget(
            MaterialApp(
              locale: testLocale,
              localizationsDelegates: testDelegates,
              supportedLocales: testLocales,
              theme: woodshedTheme(Brightness.dark),
              home: HomePage(
                controller: app.controller,
                recordingButton: const Text('REC', key: Key('rec')),
              ),
            ),
          );
          expect(
            find.byKey(const Key('rec')),
            visible ? findsOneWidget : findsNothing,
          );
        });
      }
    }
  });

  group('#30/AK11 Wellenform', () {
    testWidgets(
      'mit Daten: Übersicht und Ausschnitt; ohne: Fortschrittsbalken',
      (tester) async {
        final app = await pumpApp(tester, size: desktop);
        await choose(tester, app, 'Bossa');
        expect(find.byKey(const Key('timeline:progress')), findsOneWidget);
        expect(find.byKey(const Key('waveformOverview')), findsNothing);

        app.core.hasWaveform = true;
        app.player.setVolume(0.9); // neu aufbauen
        await tester.pump();
        expect(find.byKey(const Key('timeline:progress')), findsNothing);
        expect(find.byKey(const Key('waveformOverview')), findsOneWidget);
        expect(find.byKey(const Key('waveformDetail')), findsOneWidget);

        // Tippen in die Übersicht springt proportional.
        final o = tester.getRect(find.byKey(const Key('waveformOverview')));
        await tester.tapAt(o.centerLeft + Offset(o.width / 2, 0));
        await tester.pump();
        expect(app.core.pos, closeTo(15, 0.5));
      },
    );
  });

  group('#30/AK12 Stufenleiter und Durchgangszähler', () {
    testWidgets('aktuelle Stufe markiert, «Durchgang n von m» am Loop', (
      tester,
    ) async {
      final app = await pumpApp(tester, size: desktop);
      await choose(tester, app, 'Bossa');
      app.player.setRamp(enabled: true);
      app.player.setSpeedEnabled(true);
      app.player.setSpeed(0.75);
      app.player.setLoopStart(2);
      app.player.setLoopEnd(8);
      app.player.play();
      for (var i = 0; i < 3; i++) {
        app.core.passes++;
        app.tick();
      }
      await tester.pump();
      expect(find.byKey(const Key('rampLadder')), findsOneWidget);
      expect(find.byKey(const Key('ladder:now')), findsOneWidget);
      expect(find.byKey(const Key('ladder:60')), findsOneWidget);
      expect(find.byKey(const Key('ladder:100')), findsOneWidget);
      expect(
        find.text('6,0 s · Durchgang 3 von 10', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('75 % · 3 von 10'), findsOneWidget);
    });
  });

  group('#30/AK13 Rauchtest je Grösse', () {
    for (final (name, size) in [
      ('Desktop', desktop),
      ('Tablet', tablet),
      ('Phone', phone),
    ]) {
      testWidgets('$name: Titel wählen, abspielen, Loop setzen, Metronom', (
        tester,
      ) async {
        final app = await pumpApp(tester, size: size);
        app.core.hasWaveform = true;
        await choose(tester, app, 'Bossa');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('playPause')));
        await tester.pump();
        expect(app.player.isPlaying, isTrue);
        app.core.pos = 3;
        app.tick();
        await tester.pump();
        await tester.ensureVisible(find.byKey(const Key('here:Anfang')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('here:Anfang')));
        app.core.pos = 7;
        app.tick();
        await tester.pump();
        await tester.tap(find.byKey(const Key('here:Ende')));
        await tester.pump();
        expect(app.core.loop, (3.0, 7.0));
        // #115: the metronome is in its own area
        await tester.tap(find.byKey(const Key('area:metronome')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('metronomeToggle')));
        await tester.pump();
        expect(app.metronome.isRunning, isTrue);
        expect(app.player.isPlaying, isFalse); // nie gleichzeitig
        expect(find.byKey(const Key('card:meter')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
