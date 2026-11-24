// #115: the areas Player, Practice and Metronome in the window: tabs, mini bar, Spotify-like controls,
// shortcuts. AKn = n-th acceptance criterion of #115. Language fixed to German (pumpApp), cores are fakes.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/file_store_io.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/player/play_queue.dart';
import 'package:woodshed_player/ui/home_page.dart';
import 'package:woodshed_player/ui/style.dart';

import 'fakes.dart';
import 'home_page_test.dart' show pumpApp, select;

const desktop = Size(1280, 900);
const tablet = Size(820, 1180);
const phone = Size(390, 844);

Finder byKey(String k) => find.byKey(Key(k));

Future<void> tapArea(WidgetTester tester, AppArea a) async {
  await tester.tap(byKey('area:${a.name}'));
  await tester.pumpAndSettle();
}

/// A key with modifiers held (logical keys; on a Mac ⌥S gives the same physical key).
Future<void> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool command = false,
  bool shift = false,
  bool alt = false,
}) async {
  final mods = [
    if (command) LogicalKeyboardKey.controlLeft,
    if (shift) LogicalKeyboardKey.shiftLeft,
    if (alt) LogicalKeyboardKey.altLeft,
  ];
  for (final m in mods) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(key);
  for (final m in mods.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pump();
}

void main() {
  setUp(() => KeyboardPresence.instance.value = false);

  group('#115/AK1 switching the area at any time', () {
    for (final (name, size) in [
      ('desktop', desktop),
      ('tablet', tablet),
      ('phone', phone),
    ]) {
      testWidgets('$name: Player, Practice, Metronome by tab', (tester) async {
        final app = await pumpApp(tester, size: size);
        expect(byKey('layout:$name'), findsOneWidget);
        expect(
          byKey(size == phone ? 'areaTabBar' : 'areaSwitcher'),
          findsOneWidget,
        );
        expect(app.controller.area, AppArea.player);
        await tapArea(tester, AppArea.practice);
        expect(app.controller.area, AppArea.practice);
        expect(byKey('card:empty'), findsOneWidget); // practice without a track
        await tapArea(tester, AppArea.metronome);
        expect(byKey('metronomeScreen'), findsOneWidget);
        await tapArea(tester, AppArea.player);
        expect(
          byKey(size == phone ? 'libraryList' : 'playerScreen'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('desktop: ⌘1, ⌘2, ⌘3 (Ctrl outside Apple)', (tester) async {
      final app = await pumpApp(tester, size: desktop);
      await press(tester, LogicalKeyboardKey.digit2, command: true);
      expect(app.controller.area, AppArea.practice);
      await press(tester, LogicalKeyboardKey.digit3, command: true);
      expect(app.controller.area, AppArea.metronome);
      await press(tester, LogicalKeyboardKey.digit1, command: true);
      expect(app.controller.area, AppArea.player);
    });

    testWidgets('macOS: ⌘2 with the command key', (tester) async {
      final app = await pumpApp(tester, size: desktop);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(app.controller.area, AppArea.practice);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('practice: «Choose another track» goes to the library', (
      tester,
    ) async {
      final app = await pumpApp(tester, size: desktop);
      await select(tester, app, 'Bossa');
      await tester.tap(byKey('chooseTrack'));
      await tester.pump();
      expect(app.controller.area, AppArea.player);
      expect(byKey('track:Bossa'), findsOneWidget);
    });

    testWidgets('tablet: the library drawer in every area', (tester) async {
      final app = await pumpApp(tester, size: tablet);
      await tapArea(tester, AppArea.metronome);
      await tester.tap(byKey('libraryToggle'));
      await tester.pumpAndSettle();
      await tester.tap(byKey('track:Bossa'));
      await tester.pumpAndSettle();
      app.finishLoads(30);
      await tester.pump();
      expect(app.controller.currentTitle, 'Bossa');
      expect(byKey('miniBar:track'), findsOneWidget);
    });
  });

  group('#115/AK2 the area Player', () {
    for (final (name, size) in [('desktop', desktop), ('phone', phone)]) {
      testWidgets(
        '$name: title, play/pause, skip, position, volume; no practice modules',
        (tester) async {
          final app = await pumpApp(tester, size: size);
          app.core.hasWaveform = true;
          await select(tester, app, 'Bossa', area: null);
          app.player.setLoopStart(
            4,
          ); // a loop of the track stays its own, not shown here
          await tester.pump();
          expect(byKey('playerScreen'), findsOneWidget);
          expect(tester.widget<Text>(byKey('playerTitle')).data, 'Bossa');
          for (final k in [
            'playPause',
            'previous',
            'next',
            'shuffle',
            'repeat',
            'playerPosition',
            'playerProgress',
            'playerVolume',
          ]) {
            expect(byKey(k), findsOneWidget, reason: k);
          }
          for (final k in [
            'card:speed',
            'card:ramp',
            'card:loop',
            'card:timeline',
            'module:metronome',
            'thumbBar',
          ]) {
            expect(byKey(k), findsNothing, reason: k);
          }
          await tester.tap(byKey('playPause'));
          await tester.pump();
          expect(app.player.isPlaying, isTrue);
          await tester.tap(byKey('playPause'));
          await tester.pump();
          expect(app.player.isPlaying, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('«From …» names the folder the track plays from', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await select(tester, app, 'Bossa', area: null);
      expect(find.text('Aus «Ohne Ordner»'), findsOneWidget);
      final f = app.library.createFolder('Jazz');
      app.library.moveTracks({app.player.trackId!}, f.id);
      await select(tester, app, 'Bossa', area: null);
      expect(find.text('Aus «Jazz»'), findsOneWidget);
    });

    testWidgets('without a track: a hint to open a file', (tester) async {
      final app = await pumpApp(tester);
      expect(
        tester.widget<Text>(byKey('playerTitle')).data,
        'Kein Titel ausgewählt',
      );
      await tester.tap(byKey('openFile'));
      expect(app.files.picks, 1);
      expect(byKey('playerControls'), findsNothing);
    });

    testWidgets('the volume slider and the speaker (mute)', (tester) async {
      final app = await pumpApp(tester);
      await select(tester, app, 'Bossa', area: null);
      await tester.tap(byKey('mute'));
      await tester.pump();
      expect(app.player.volume, 0);
      await tester.tap(byKey('mute'));
      await tester.pump();
      expect(app.player.volume, 1);
      await tester.tap(
        find.descendant(
          of: byKey('playerVolume'),
          matching: find.byType(Slider),
        ),
      );
      await tester.pump();
      expect(app.player.volume, closeTo(0.5, 0.05));
    });
  });

  testWidgets(
    '#115/AK3 switching the area interrupts neither the track nor the metronome',
    (tester) async {
      final app = await pumpApp(tester, size: desktop);
      await select(tester, app, 'Bossa');
      app.player.setLoopStart(4);
      app.player.setLoopEnd(9);
      app.player.setSpeed(0.8);
      await tester.tap(byKey('playPause'));
      await tester.pump();
      app.core.pos = 5;
      app.tick();
      final calls = app.core.calls.length;
      for (final a in [AppArea.player, AppArea.metronome, AppArea.practice]) {
        await tapArea(tester, a);
        expect(app.player.isPlaying, isTrue, reason: a.name);
      }
      expect(app.core.calls.skip(calls), isNot(contains('pause')));
      expect(app.core.loop, (4.0, 9.0));
      expect(app.player.settings.speed, 0.8);
      expect(app.player.position, 5);
      // the metronome as well
      await tapArea(tester, AppArea.metronome);
      await tester.tap(byKey('metronomeToggle'));
      await tester.pump();
      for (final a in [AppArea.player, AppArea.practice, AppArea.metronome]) {
        await tapArea(tester, a);
        expect(app.metronome.isRunning, isTrue, reason: a.name);
      }
    },
  );

  testWidgets('#115/AK4 the area Metronome has every setting of the module', (
    tester,
  ) async {
    final app = await pumpApp(tester, size: desktop);
    await tapArea(tester, AppArea.metronome);
    for (final k in [
      'card:metronome',
      'metronomeToggle',
      'metronomeBpm',
      'card:meter',
      'card:ramp',
      'rampMode:bars',
      'rampMode:time',
    ]) {
      expect(byKey(k), findsOneWidget, reason: k);
    }
    await tester.tap(find.text('6/8'));
    await tester.pump();
    expect(app.controller.metronome.settings.meter, 6);
    expect(byKey('metronomeSettings'), findsNothing); // no dialog needed
  });

  for (final (name, size) in [
    ('desktop', desktop),
    ('tablet', tablet),
    ('phone', phone),
  ]) {
    testWidgets('#115/AK5 $name: Practice shows no metronome module', (
      tester,
    ) async {
      final app = await pumpApp(tester, size: size);
      await select(tester, app, 'Bossa');
      expect(byKey('card:speed'), findsOneWidget);
      expect(byKey('module:metronome'), findsNothing);
      expect(byKey('card:metronome'), findsNothing);
    });
  }

  group('#115/AK6 never both at once; mini bar', () {
    testWidgets(
      'Metronome: the paused track as a mini bar; playing it stops the metronome',
      (tester) async {
        final app = await pumpApp(tester, size: desktop);
        await select(tester, app, 'Bossa');
        await tester.tap(byKey('playPause'));
        await tester.pump();
        await tapArea(tester, AppArea.metronome);
        expect(byKey('miniBar:track'), findsOneWidget);
        expect(byKey('running:practice'), findsOneWidget);
        await tester.tap(byKey('metronomeToggle'));
        await tester.pump();
        expect(app.metronome.isRunning, isTrue);
        expect(app.player.isPlaying, isFalse);
        expect(find.textContaining('pausiert'), findsOneWidget);
        expect(byKey('running:metronome'), findsOneWidget);
        expect(byKey('running:practice'), findsNothing);
        expect(
          find.byTooltip('Titel abspielen, stoppt das Metronom'),
          findsOneWidget,
        );
        await tester.tap(byKey('miniToggle'));
        await tester.pump();
        expect(app.player.isPlaying, isTrue);
        expect(app.metronome.isRunning, isFalse);
      },
    );

    testWidgets(
      'Player and Practice: the running metronome as a mini bar, stopped by a tap',
      (tester) async {
        final app = await pumpApp(tester, size: phone);
        await tapArea(tester, AppArea.metronome);
        expect(byKey('miniBar:metronome'), findsNothing);
        await tester.tap(byKey('metronomeToggle'));
        await tester.pump();
        for (final a in [AppArea.player, AppArea.practice]) {
          await tapArea(tester, a);
          expect(byKey('miniBar:metronome'), findsOneWidget, reason: a.name);
          expect(find.text('Metronom · 120 BPM'), findsOneWidget);
        }
        await tester.tap(byKey('miniToggle'));
        await tester.pump();
        expect(app.metronome.isRunning, isFalse);
        expect(byKey('miniBar:metronome'), findsNothing);
      },
    );

    testWidgets('a tap on the metronome mini bar opens the area Metronome', (
      tester,
    ) async {
      final app = await pumpApp(tester, size: desktop);
      app.controller.metronome.start();
      await tester.pump();
      await tester.tap(find.text('Metronom · 120 BPM'));
      await tester.pump();
      expect(app.controller.area, AppArea.metronome);
    });
  });

  testWidgets('#115/AK7 after a restart the app opens the area chosen last', (
    tester,
  ) async {
    final app = await pumpApp(tester, size: desktop);
    await tapArea(tester, AppArea.metronome);
    final base = (app.library.store as IoFileStore).base;
    late TestApp again;
    final file = File('${base.path}/${DeviceSettings.fileName}');
    await waitUntil(
      tester,
      () => file.existsSync() && file.readAsStringSync().contains('metronome'),
      'area written',
    );
    await tester.runAsync(() async {
      again = TestApp(base);
      await again.library.load();
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: testLocale,
        localizationsDelegates: testDelegates,
        supportedLocales: testLocales,
        theme: woodshedTheme(Brightness.light),
        home: HomePage(controller: again.controller),
      ),
    );
    await tester.pump();
    expect(byKey('metronomeScreen'), findsOneWidget);
  });

  group('#115/AK8 Shuffle · Previous · Play/Pause · Next · Repeat', () {
    testWidgets('order of the buttons, dot for «on», 1 for the track', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await select(tester, app, 'Bossa', area: null);
      final xs = [
        for (final k in ['shuffle', 'previous', 'playPause', 'next', 'repeat'])
          tester.getCenter(byKey(k)).dx,
      ];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(byKey('shuffle:on'), findsNothing);
      await tester.tap(byKey('shuffle'));
      await tester.pump();
      expect(app.controller.shuffle, isTrue);
      expect(byKey('shuffle:on'), findsOneWidget);
      expect(find.byTooltip('Zufällige Wiedergabe an'), findsOneWidget);
      expect(find.byTooltip('Wiederholen: aus'), findsOneWidget);
      await tester.tap(byKey('repeat'));
      await tester.pump();
      expect(app.controller.repeat, Repeat.list);
      expect(byKey('repeat:on'), findsOneWidget);
      expect(find.byTooltip('Wiederholen: Liste'), findsOneWidget);
      expect(find.text('1'), findsNothing);
      await tester.tap(byKey('repeat'));
      await tester.pump();
      expect(app.controller.repeat, Repeat.track);
      expect(find.byTooltip('Wiederholen: Titel'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      await tester.tap(byKey('repeat'));
      await tester.pump();
      expect(app.controller.repeat, Repeat.off);
      expect(byKey('repeat:on'), findsNothing);
    });

    testWidgets('#115/AK9 Next and Previous move through the folder', (
      tester,
    ) async {
      final app = await pumpApp(tester); // Ärger, Bossa, Zebra
      app.library.sortOrder = TrackSortOrder.alphabetical;
      await select(tester, app, 'Bossa', area: null);
      await tester.tap(byKey('next'));
      await tester.pump();
      app.finishLoads(30);
      await tester.pump();
      expect(app.controller.currentTitle, 'Zebra');
      await tester.tap(byKey('previous'));
      await tester.pump();
      app.finishLoads(30);
      await tester.pump();
      expect(app.controller.currentTitle, 'Bossa');
    });
  });

  group('#115/AK11 shortcuts', () {
    testWidgets('Player: Space, ⌥S, ⌥R, M, ⌘→/⌘←, ⇧⌘→/⇧⌘←, ⌘↑/⌘↓', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      app.library.sortOrder = TrackSortOrder.alphabetical;
      await select(tester, app, 'Bossa', area: null);
      await press(tester, LogicalKeyboardKey.space);
      expect(app.player.isPlaying, isTrue);
      await press(tester, LogicalKeyboardKey.space);
      expect(app.player.isPlaying, isFalse);
      await press(tester, LogicalKeyboardKey.keyS, alt: true);
      expect(app.controller.shuffle, isTrue);
      await press(tester, LogicalKeyboardKey.keyS, alt: true);
      expect(app.controller.shuffle, isFalse);
      await press(tester, LogicalKeyboardKey.keyR, alt: true);
      expect(app.controller.repeat, Repeat.list);
      await press(tester, LogicalKeyboardKey.keyM);
      expect(app.player.volume, 0);
      expect(app.metronome.isRunning, isFalse); // M is not the metronome here
      await press(tester, LogicalKeyboardKey.keyM);
      expect(app.player.volume, 1);
      await press(tester, LogicalKeyboardKey.arrowDown, command: true);
      expect(app.player.volume, closeTo(0.9, 1e-9));
      await press(tester, LogicalKeyboardKey.arrowUp, command: true);
      expect(app.player.volume, closeTo(1, 1e-9));
      await press(
        tester,
        LogicalKeyboardKey.arrowRight,
        command: true,
        shift: true,
      );
      expect(app.core.calls.last, 'seek 15.0');
      await press(
        tester,
        LogicalKeyboardKey.arrowLeft,
        command: true,
        shift: true,
      );
      expect(app.core.calls.last, 'seek 0.0');
      await press(tester, LogicalKeyboardKey.arrowRight, command: true);
      app.finishLoads(30);
      await tester.pump();
      expect(app.controller.currentTitle, 'Zebra');
      await press(tester, LogicalKeyboardKey.arrowLeft, command: true);
      app.finishLoads(30);
      await tester.pump();
      expect(app.controller.currentTitle, 'Bossa');
      // the practice shortcuts do not apply in Player
      await press(tester, LogicalKeyboardKey.keyT);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(app.player.settings.speedEnabled, isFalse);
      expect(app.player.settings.loopEnabled, isFalse);
    });

    testWidgets(
      'Player: ⌘K puts the cursor into the search, typing filters, Esc empties',
      (tester) async {
        await pumpApp(tester);
        await press(tester, LogicalKeyboardKey.keyK, command: true);
        await tester.pump();
        final field = tester.widget<TextField>(byKey('librarySearch'));
        expect(field.focusNode!.hasFocus, isTrue);
        await tester.enterText(byKey('librarySearch'), 'zeb');
        await tester.pump();
        expect(byKey('track:Zebra'), findsOneWidget);
        expect(byKey('track:Bossa'), findsNothing);
        // typing «m» or a space in the search field changes nothing in playback
        await tester.enterText(byKey('librarySearch'), 'xyz m');
        await tester.pump();
        expect(find.text('Keine Treffer'), findsOneWidget);
        await press(tester, LogicalKeyboardKey.escape);
        expect(byKey('track:Bossa'), findsOneWidget);
      },
    );

    testWidgets('phone: ⌘K leaves the full player for the search', (
      tester,
    ) async {
      final app = await pumpApp(tester, size: phone);
      await select(tester, app, 'Bossa', area: null);
      expect(byKey('playerScreen'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.keyK, command: true);
      await tester.pump();
      expect(byKey('librarySearch'), findsOneWidget);
    });

    testWidgets('tablet: ⌘K opens the library drawer with the search', (
      tester,
    ) async {
      await pumpApp(tester, size: tablet);
      await press(tester, LogicalKeyboardKey.keyK, command: true);
      await tester.pumpAndSettle();
      expect(byKey('libraryDrawer'), findsOneWidget);
      final field = tester.widget<TextField>(byKey('librarySearch'));
      expect(field.focusNode!.hasFocus, isTrue);
    });

    testWidgets('Practice: the practice shortcuts (M metronome, ←→ tempo)', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await select(tester, app, 'Bossa');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(app.player.settings.speed, closeTo(1.05, 1e-9));
      await press(tester, LogicalKeyboardKey.keyM);
      expect(app.metronome.isRunning, isTrue);
      await press(tester, LogicalKeyboardKey.keyM);
      await press(tester, LogicalKeyboardKey.keyS, alt: true);
      expect(app.controller.shuffle, isFalse);
    });

    testWidgets(
      'Metronome: Space starts and stops the metronome, ↑ raises the tempo',
      (tester) async {
        final app = await pumpApp(tester);
        await tapArea(tester, AppArea.metronome);
        await press(tester, LogicalKeyboardKey.space);
        expect(app.metronome.isRunning, isTrue);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(app.controller.metronome.settings.bpm, 121);
        await press(tester, LogicalKeyboardKey.space);
        expect(app.metronome.isRunning, isFalse);
      },
    );
  });

  for (final (name, size) in [('desktop', desktop), ('phone', phone)]) {
    testWidgets(
      '#115/AK12 $name: pause in Practice goes back to the loop start or the start',
      (tester) async {
        final app = await pumpApp(tester, size: size);
        await select(tester, app, 'Bossa');
        await tester.tap(byKey('playPause'));
        await tester.pump();
        app.core.pos = 12;
        app.tick();
        await tester.pump();
        await tester.tap(byKey('playPause'));
        await tester.pump();
        expect(app.player.isPlaying, isFalse);
        expect(app.player.position, 0);
        app.player.setLoopStart(5);
        app.player.setLoopEnd(20);
        await tester.tap(byKey('playPause'));
        await tester.pump();
        app.core.pos = 14;
        app.tick();
        await tester.pump();
        await tester.tap(byKey('playPause'));
        await tester.pump();
        expect(app.player.position, 5);
      },
    );
  }

  testWidgets(
    '#115/AK13 stop in the area Metronome: the ramp back to its start',
    (tester) async {
      final app = await pumpApp(tester);
      final m = app.controller.metronome
        ..setRamp(enabled: true, start: 90, target: 140);
      await tapArea(tester, AppArea.metronome);
      await tester.tap(byKey('metronomeToggle'));
      await tester.pump();
      app.metronome.bpm = 112;
      m.sync();
      await tester.pump();
      await tester.tap(byKey('metronomeToggle'));
      await tester.pump();
      expect(m.settings.bpm, 90);
      expect(find.text('90 BPM'), findsOneWidget);
    },
  );

  group('#115 dot at the tab of what plays', () {
    testWidgets(
      'a playing track: at Player or Practice, where it was last shown',
      (tester) async {
        final app = await pumpApp(tester, size: phone);
        await select(tester, app, 'Bossa', area: null);
        app.player.play();
        await tester.pump();
        expect(byKey('running:player'), findsOneWidget);
        await tapArea(tester, AppArea.practice);
        expect(byKey('running:practice'), findsOneWidget);
        expect(byKey('running:player'), findsNothing);
        expect(find.bySemanticsLabel('Üben, läuft'), findsOneWidget);
      },
    );
  });

  test('#115/AK14 the new texts are in English and German', () {
    final en = File('lib/l10n/app_en.arb').readAsStringSync();
    final de = File('lib/l10n/app_de.arb').readAsStringSync();
    for (final k in [
      'areaPlayer',
      'areaPractice',
      'areaMetronome',
      'areaRunning',
      'shuffle',
      'shuffleOn',
      'repeatOff',
      'repeatList',
      'repeatTrack',
      'previousTrack',
      'nextTrack',
      'playingFrom',
      'chooseOtherTrack',
      'miniPaused',
      'miniPlayTrack',
      'miniMetronome',
      'searchLibrary',
      'noSearchResults',
    ]) {
      expect(en, contains('"$k":'), reason: k);
      expect(de, contains('"$k":'), reason: k);
    }
  });

  test('#115/AK15 the feature reference describes the three areas', () {
    // #145: the feature table moved from README.md to docs/FUNKTIONEN.md.
    final readme = File('../docs/FUNKTIONEN.md').readAsStringSync();
    for (final s in [
      'Player',
      'Üben',
      'Metronom',
      'Zufall',
      'Wiederholen',
      '⌘1',
    ]) {
      expect(readme, contains(s), reason: s);
    }
  });
}
