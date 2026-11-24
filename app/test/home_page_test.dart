// #17: Oberfläche mit Attrappen für Kern, Dateiauswahl und Metronom; Bibliothek in einem temporären Ordner.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/sync/cloud_account.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/sync_service.dart';
import 'package:woodshed_player/time_format.dart';
import 'package:woodshed_player/ui/home_page.dart';
import 'package:woodshed_player/ui/player_view.dart';
import 'package:woodshed_player/ui/style.dart';

import 'fakes.dart';
import 'metadata_test.dart' show apic, id3, text;

const wide = Size(1100, 900);
const phone = Size(390, 844);

/// App mit einer Bibliothek aus [titles] (leere Dateien, Titel = Dateiname) starten.
Future<TestApp> pumpApp(
  WidgetTester tester, {
  Size size = wide,
  List<String> titles = const ['Ärger', 'Bossa', 'Zebra'],
  Map<String, Uint8List> files = const {},
  SyncService? sync,
  CloudAccount Function(Library library)? cloud,
  AudioTrimmer? trimmer,
  bool libraryOpen = true,
  Locale locale = testLocale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dir = Directory.systemTemp.createTempSync('wp_ui_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  final app = TestApp(
    Directory('${dir.path}/lib'),
    sync: sync == null ? null : (_) => sync,
    cloud: cloud,
    trimmer: trimmer,
    libraryOpen: libraryOpen,
  );
  await tester.runAsync(() async {
    await app.library.load();
    final src = Directory('${dir.path}/quelle')..createSync();
    final paths = [
      for (final t in titles)
        (File('${src.path}/$t.mp3')..writeAsStringSync('audio $t')).path,
      for (final e in files.entries)
        (File('${src.path}/${e.key}')..writeAsBytesSync(e.value)).path,
    ];
    await app.library.importFiles(paths);
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: testDelegates,
      supportedLocales: testLocales,
      theme: woodshedTheme(Brightness.light),
      home: HomePage(controller: app.controller),
    ),
  );
  await tester.pump();
  return app;
}

/// Titel in der Liste antippen und das Laden abschliessen. #115: the library is in the area Player; then the
/// area [area] is shown (Practice unless given), where the tests of the practice screen look.
Future<void> select(
  WidgetTester tester,
  TestApp app,
  String title, {
  AppArea? area = AppArea.practice,
}) async {
  if (find.byKey(Key('track:$title')).evaluate().isEmpty) {
    app.controller.setArea(AppArea.player);
    await tester.pump();
    final back = find.byKey(const Key('backToLibrary'));
    if (back.evaluate().isNotEmpty) {
      await tester.tap(back);
      await tester.pump();
    }
    final drawer = find.byKey(const Key('libraryToggle'));
    if (find.byKey(Key('track:$title')).evaluate().isEmpty &&
        drawer.evaluate().isNotEmpty) {
      await tester.tap(drawer);
      await tester.pumpAndSettle();
    }
  }
  await tester.tap(find.byKey(Key('track:$title')));
  await tester.pump();
  app.finishLoads(30);
  await tester.pump();
  if (area != null) {
    app.controller.setArea(area);
    await tester.pump();
  }
}

/// Mit der Maus von [from] nach [to] ziehen (Draggable auf dem Desktop).
Future<void> dragTo(WidgetTester tester, Finder from, Finder to) async {
  final g = await tester.startGesture(
    tester.getCenter(from),
    kind: PointerDeviceKind.mouse,
  );
  await g.moveBy(const Offset(0, 20));
  await tester.pump();
  await g.moveTo(tester.getCenter(to));
  await tester.pump();
  await g.up();
  await tester.pump();
}

void main() {
  group('#17/AK6 Layout (seit #30: Desktop, Tablet, Phone)', () {
    testWidgets('Desktop: Bibliothek links, Player daneben', (tester) async {
      await pumpApp(tester);
      expect(find.byKey(const Key('layout:desktop')), findsOneWidget);
      // the title of the panel and (#123) the section with all tracks
      expect(find.text('Bibliothek'), findsNWidgets(2));
      expect(find.byKey(const Key('track:Bossa')), findsOneWidget);
      expect(
        find.byKey(const Key('playerScreen')),
        findsOneWidget,
      ); // #115: the area Player beside it
      expect(find.byKey(const Key('areaTabBar')), findsNothing);
    });

    testWidgets(
      'iPhone: Bibliothek als eigene Seite; Titel wählen öffnet den Player',
      (tester) async {
        final app = await pumpApp(tester, size: phone);
        expect(find.byKey(const Key('layout:phone')), findsOneWidget);
        expect(find.byKey(const Key('areaTabBar')), findsOneWidget);
        expect(find.byKey(const Key('playerScreen')), findsNothing);
        await select(tester, app, 'Bossa', area: null);
        expect(find.byKey(const Key('playerScreen')), findsOneWidget);
        expect(find.byKey(const Key('track:Bossa')), findsNothing);
        await tester.tap(find.byKey(const Key('backToLibrary')));
        await tester.pump();
        expect(find.byKey(const Key('playerScreen')), findsNothing);
        expect(find.byKey(const Key('track:Bossa')), findsOneWidget);
        // #115: the loaded track stays as a mini bar under the library and opens the player again
        await tester.tap(find.byKey(const Key('openPlayer')));
        await tester.pump();
        expect(find.byKey(const Key('playerScreen')), findsOneWidget);
      },
    );
  });

  group('#17/AK1 Liste', () {
    testWidgets('Ordner als Abschnitte, einklappbar', (tester) async {
      final app = await pumpApp(tester);
      final f = app.library.createFolder('Etüden');
      app.library.moveTracks({
        app.library.tracks.firstWhere((t) => t.title == 'Zebra').id,
      }, f.id);
      await tester.pump();
      expect(find.byKey(const Key('section:none')), findsOneWidget);
      expect(find.byKey(const Key('folder:Etüden')), findsOneWidget);
      expect(find.byKey(const Key('track:Zebra')), findsOneWidget);
      await tester.tap(find.text('Etüden'));
      await tester.pump();
      expect(find.byKey(const Key('track:Zebra')), findsNothing);
    });

    testWidgets('Kontextmenü: Löschen mit Rückfrage', (tester) async {
      final app = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('menu:Bossa')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Originaldatei bleibt unverändert'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('confirm')));
      await tester.pumpAndSettle();
      expect(app.library.tracks.map((t) => t.title), isNot(contains('Bossa')));
      expect(find.byKey(const Key('track:Bossa')), findsNothing);
    });

    testWidgets('Kontextmenü per Rechtsklick: in Ordner verschieben', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      app.library.createFolder('Swing');
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('track:Ärger')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('In Ordner verschieben'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Swing'));
      await tester.pumpAndSettle();
      final t = app.library.tracks.firstWhere((t) => t.title == 'Ärger');
      expect(
        app.library.folders.firstWhere((f) => f.id == t.folderId).name,
        'Swing',
      );
    });

    testWidgets('Ordner anlegen, umbenennen und löschen (Titel bleiben)', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('libraryMoreMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('newFolder')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('nameField')), 'Übungen');
      await tester.tap(find.byKey(const Key('nameOk')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('folder:Übungen')), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('folder:Übungen')),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Umbenennen …'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('nameField')), 'Jazz');
      await tester.tap(find.byKey(const Key('nameOk')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('folder:Jazz')), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('folder:Jazz')),
          matching: find.byType(IconButton),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ordner löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm')));
      await tester.pumpAndSettle();
      expect(app.library.folders, isEmpty);
      expect(app.library.tracks.length, 3);
    });

    testWidgets('Ziehen auf einen Ordner verschiebt hinein', (tester) async {
      final app = await pumpApp(tester);
      app.library.createFolder('Swing');
      await tester.pump();
      await dragTo(
        tester,
        find.byKey(const Key('track:Zebra')),
        find.byKey(const Key('folder:Swing')),
      );
      final t = app.library.tracks.firstWhere((t) => t.title == 'Zebra');
      expect(t.folderId, app.library.folders.single.id);
    });

    testWidgets(
      'Ziehen auf einen Titel sortiert davor ein (eigene Reihenfolge)',
      (tester) async {
        final app = await pumpApp(
          tester,
        ); // Standard: neueste zuerst -> Zebra, Bossa, Ärger
        await dragTo(
          tester,
          find.byKey(const Key('track:Ärger')),
          find.byKey(const Key('track:Zebra')),
        );
        expect(app.library.sortOrder, TrackSortOrder.custom);
        expect(app.library.sortedTracksIn(null).map((t) => t.title), [
          'Ärger',
          'Zebra',
          'Bossa',
        ]);
      },
    );

    testWidgets('Sortierung umstellen', (tester) async {
      final app = await pumpApp(tester, titles: ['b', 'a', 'c']);
      await tester.tap(find.byKey(const Key('sortMenu')));
      await tester.pumpAndSettle();
      // #62: tap the menu entry, not its text; CheckedPopupMenuItem puts its content in an IgnorePointer.
      await tester.tap(find.byKey(const Key('sort-alphabetical')));
      await tester.pumpAndSettle();
      expect(app.library.sortOrder, TrackSortOrder.alphabetical);
      final ys = [
        'a',
        'b',
        'c',
      ].map((t) => tester.getTopLeft(find.byKey(Key('track:$t'))).dy).toList();
      expect(ys, orderedEquals([...ys]..sort()));
    });
  });

  group('#17/AK2 Player', () {
    testWidgets('Cover, Titel, Künstler, ±15 s, Play/Pause, Lautstärke', (
      tester,
    ) async {
      final mp3 = id3(3, [
        ('TIT2', text(0, 'Mit Cover')),
        ('TPE1', text(0, 'Testband')),
        ('APIC', apic(3, Uint8List.fromList([1, 2, 3]))),
      ]);
      final app = await pumpApp(tester, titles: [], files: {'x.mp3': mp3});
      await select(tester, app, 'Mit Cover');
      expect(find.byKey(const Key('trackTitle')), findsOneWidget);
      expect(find.textContaining('Testband'), findsWidgets);
      final art = app.library.artworkPath(app.library.tracks.single)!;
      expect(find.byKey(Key('artwork:$art')), findsWidgets);

      await tester.tap(find.byKey(const Key('playPause')));
      await tester.pump();
      expect(app.player.isPlaying, isTrue);
      await tester.tap(find.byTooltip('15 Sekunden vor'));
      await tester.pump();
      expect(app.core.calls.last, 'seek 15.0');
      await tester.tap(find.byTooltip('15 Sekunden zurück'));
      await tester.pump();
      expect(app.core.calls.last, 'seek 0.0');
      await tester.tap(find.byKey(const Key('playPause')));
      await tester.pump();
      expect(app.player.isPlaying, isFalse);
      expect(find.byKey(const Key('volume')), findsOneWidget);
    });
  });

  group('#17/AK3 Tempo', () {
    testWidgets('Schalter und Schnellwahl', (tester) async {
      final app = await pumpApp(tester);
      await select(tester, app, 'Bossa');
      for (final p in [0.5, 0.75, 0.8, 1.0]) {
        expect(find.byKey(Key('preset:$p')), findsOneWidget);
      }
      final toggle = find.descendant(
        of: find.byKey(const Key('card:speed')),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(app.player.settings.speedEnabled, isTrue);
      await tester.tap(find.byKey(const Key('preset:0.75')));
      await tester.pump();
      expect(app.player.settings.speed, closeTo(0.75, 1e-9));
      expect(app.core.rateValue, closeTo(0.75, 1e-9));
      await tester.tap(toggle); // aus: Originaltempo, Wert bleibt
      await tester.pump();
      expect(app.core.rateValue, 1.0);
      expect(app.player.settings.speed, closeTo(0.75, 1e-9));
    });
  });

  group('#17/AK4 Loop', () {
    testWidgets('Schalter und mm:ss-Felder', (tester) async {
      final app = await pumpApp(tester);
      await select(tester, app, 'Bossa');
      final toggle = find.byKey(const Key('loopToggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(app.core.loop, (0.0, 30.0)); // ohne Grenzen: ganzer Titel
      await tester.enterText(find.byKey(const Key('time:Anfang')), '00:05');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.enterText(find.byKey(const Key('time:Ende')), '00:12.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(app.core.loop, (5.0, 12.5));
      await tester.tap(toggle);
      await tester.pump();
      expect(app.core.loop, isNull);
      expect(app.player.settings.loopStart, 5); // Grenzen bleiben
    });

    testWidgets('«S hier» übernimmt die Wiedergabeposition', (tester) async {
      final app = await pumpApp(tester);
      await select(tester, app, 'Bossa');
      app.player.setLoopEnabled(true);
      app.player.play();
      app.core.pos = 7.5;
      app.tick();
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('here:Anfang')));
      await tester.tap(find.byKey(const Key('here:Anfang')));
      await tester.pump();
      expect(app.player.settings.loopStart, 7.5);
      expect(app.player.settings.loopEnabled, isTrue);
      expect(app.core.loop, (7.5, 30.0));
    });

    testWidgets('Marker ziehen ändert die Grenze, das Zeitfeld geht live mit', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await select(tester, app, 'Bossa');
      app.player.setLoopEnabled(true); // ganzer Titel 0–30 s
      await tester.pump();
      final marker = find.byKey(const Key('loopEndMarker'));
      expect(marker, findsOneWidget);
      final scrubberWidth = tester.getSize(find.byType(ProgressScrubber)).width;
      // Die Marke sitzt am Ende des Balkens; ihre linke Hälfte liegt innerhalb.
      final g = await tester.startGesture(
        tester.getCenter(marker) - const Offset(4, 0),
      );
      await g.moveBy(const Offset(-20, 0)); // über die Ziehschwelle
      await tester.pump();
      await g.moveBy(Offset(-scrubberWidth / 3 + 20, 0));
      await tester.pump();
      final mid = app.player.settings.loopEnd;
      expect(mid, inInclusiveRange(18, 22)); // ein Drittel weniger als 30 s
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('time:Ende')),
          matching: find.byType(TextField),
        ),
      );
      expect(
        field.controller!.text,
        formatTimePrecise(mid),
      ); // live, noch während des Ziehens
      await g.up();
      await tester.pump();
      expect(app.core.loop!.$2, closeTo(mid, 1e-9));
    });
  });

  group('#17/AK5 Tastatur und Dateien', () {
    testWidgets('Leertaste, S, E, ← und →', (tester) async {
      final app = await pumpApp(tester);
      await select(tester, app, 'Bossa');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(app.player.isPlaying, isTrue);
      app.core.pos = 4;
      app.tick();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      app.core.pos = 9;
      app.tick();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.pump();
      expect(app.player.settings.loopEnabled, isTrue);
      expect(app.player.settings.loopStart, 4);
      expect(app.player.settings.loopEnd, 9);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(app.player.settings.speedEnabled, isTrue);
      expect(app.player.settings.speed, closeTo(1.05, 1e-9));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(app.player.settings.speed, closeTo(0.95, 1e-9));
      // Leertaste im Loop: Stopp springt zum Loop-Anfang
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(app.player.isPlaying, isFalse);
      expect(app.player.position, 4);
    });

    testWidgets('Entf löscht den gewählten Titel nach Rückfrage', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await select(tester, app, 'Zebra');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm')));
      await tester.pumpAndSettle();
      expect(app.library.tracks.map((t) => t.title), isNot(contains('Zebra')));
      expect(app.player.hasTrack, isFalse);
    });

    testWidgets('⌘O öffnet die Dateiauswahl, ⇧⌘N einen neuen Ordner', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(app.files.picks, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.text('Neuer Ordner'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('ins Fenster gezogene Dateien erscheinen in der Liste', (
      tester,
    ) async {
      final app = await pumpApp(tester, titles: []);
      final dir = Directory.systemTemp.createTempSync('wp_drop');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/Neu.flac')..writeAsStringSync('audio');
      await tester.runAsync(() async {
        app.files.drop!([f.path]);
      });
      // #78/AK1: wait for the state, a time limit only against a hang
      await waitUntil(
        tester,
        () => app.library.tracks.isNotEmpty,
        'dropped file in the library',
      );
      await tester.pump();
      expect(find.byKey(const Key('track:Neu')), findsOneWidget);
    });
  });
}
