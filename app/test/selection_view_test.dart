// #122: several tracks selected in the library list and moved, added or deleted together. Fakes for core,
// file picker and metronome; the library lives in a temporary folder. German UI (testLocale), widgets
// found by key.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/l10n/app_localizations.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/ui/library_view.dart';
import 'package:woodshed_player/ui/style.dart';

import 'fakes.dart';
import 'home_page_test.dart' as home show pumpApp;
import 'home_page_test.dart' show dragTo;
import 'playlist_view_test.dart' show idOf, titles;

/// The app with its library open, the tracks alphabetical: Ärger, Bossa, Zebra.
Future<TestApp> pumpApp(WidgetTester tester) async {
  final app = await home.pumpApp(tester);
  app.library.sortOrder = TrackSortOrder.alphabetical;
  await tester.pumpAndSettle();
  return app;
}

Finder row(String title) => find.byKey(Key('track:$title'));
Finder marked(String title) => find.byKey(Key('marked:$title'));

/// Clicks [title] while [key] is held (⌘, Ctrl or ⇧).
Future<void> clickWith(
  WidgetTester tester,
  LogicalKeyboardKey key,
  String title,
) async {
  await tester.sendKeyDownEvent(key);
  await tester.tap(row(title));
  await tester.sendKeyUpEvent(key);
  await tester.pumpAndSettle();
}

/// The library alone, as on iPhone/iPad (touch), German.
Future<TestApp> pumpTouchLibrary(WidgetTester tester) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dir = Directory.systemTemp.createTempSync('wp_ui_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  final app = TestApp(Directory('${dir.path}/lib'));
  await tester.runAsync(() async {
    await app.library.load();
    final src = Directory('${dir.path}/quelle')..createSync();
    await app.library.importFiles([
      for (final t in ['Ärger', 'Bossa', 'Zebra'])
        (File('${src.path}/$t.mp3')..writeAsStringSync('audio $t')).path,
    ]);
  });
  app.library.sortOrder = TrackSortOrder.alphabetical;
  await tester.pumpWidget(
    MaterialApp(
      locale: testLocale,
      localizationsDelegates: testDelegates,
      supportedLocales: testLocales,
      theme: woodshedTheme(Brightness.light),
      home: Scaffold(
        body: LibraryView(controller: app.controller, touch: true),
      ),
    ),
  );
  await tester.pump();
  return app;
}

void main() {
  testWidgets(
    '#122/AK1 ⌘-click selects and deselects single tracks, marked and counted',
    (tester) async {
      final app = await pumpApp(tester);
      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Ärger');
      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Zebra');
      expect(marked('Ärger'), findsOneWidget);
      expect(marked('Zebra'), findsOneWidget);
      expect(marked('Bossa'), findsNothing);
      expect(find.text(de.selectionCount(2)), findsOneWidget);
      expect(app.player.trackId, isNull, reason: 'selecting does not play');

      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Ärger');
      expect(marked('Ärger'), findsNothing);
      expect(find.text(de.selectionCount(1)), findsOneWidget);
    },
  );

  testWidgets('#122/AK1 Ctrl-click (browser outside Apple) selects too', (
    tester,
  ) async {
    await pumpApp(tester);
    await clickWith(tester, LogicalKeyboardKey.controlLeft, 'Bossa');
    expect(marked('Bossa'), findsOneWidget);
  });

  testWidgets(
    '#122/AK1 ⇧-click selects the range from the track clicked last',
    (tester) async {
      await pumpApp(tester);
      await tester.tap(row('Ärger'));
      await tester.pumpAndSettle();
      await clickWith(tester, LogicalKeyboardKey.shiftLeft, 'Zebra');
      for (final t in ['Ärger', 'Bossa', 'Zebra']) {
        expect(marked(t), findsOneWidget, reason: t);
      }
      expect(find.text(de.selectionCount(3)), findsOneWidget);
    },
  );

  testWidgets('#122/AK1 a plain click plays the track and ends the selection', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Ärger');
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Bossa');
    await tester.tap(row('Zebra'));
    await tester.pump();
    app.finishLoads(30);
    await tester.pumpAndSettle();
    expect(marked('Ärger'), findsNothing);
    expect(find.byKey(const Key('selectionBar')), findsNothing);
    expect(app.player.trackId, idOf(app, 'Zebra'));
  });

  testWidgets(
    '#122/AK2 touch: a long press starts the selection mode with check marks, a tap toggles',
    (tester) async {
      final app = await pumpTouchLibrary(tester);
      expect(find.byKey(const Key('unchecked:Bossa')), findsNothing);
      await tester.longPress(row('Bossa'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('checked:Bossa')), findsOneWidget);
      expect(find.byKey(const Key('unchecked:Zebra')), findsOneWidget);

      await tester.tap(row('Zebra'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('checked:Zebra')), findsOneWidget);
      expect(app.player.trackId, isNull, reason: 'a tap selects, not plays');
      await tester.tap(row('Bossa'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unchecked:Bossa')), findsOneWidget);
      expect(find.text(de.selectionCount(1)), findsOneWidget);

      await tester.tap(find.byKey(const Key('selectionDone')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unchecked:Bossa')), findsNothing);
      expect(find.byKey(const Key('selectionBar')), findsNothing);
    },
  );

  testWidgets('#122/AK2 touch: «Select» in the menu of a track', (
    tester,
  ) async {
    await pumpTouchLibrary(tester);
    await tester.tap(find.byKey(const Key('menu:Zebra')));
    await tester.pumpAndSettle();
    expect(find.text(de.selectTracks), findsOneWidget);
    await tester.tap(find.byKey(const Key('selectTracks')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checked:Zebra')), findsOneWidget);
    expect(find.byKey(const Key('unchecked:Ärger')), findsOneWidget);
  });

  testWidgets('#122/AK2 touch: a long press and a drag still moves the track', (
    tester,
  ) async {
    final app = await pumpTouchLibrary(tester);
    final p = app.library.createPlaylist('Band');
    await tester.pump();
    final g = await tester.startGesture(tester.getCenter(row('Zebra')));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await g.moveBy(const Offset(0, 20));
    await tester.pump();
    await g.moveTo(tester.getCenter(find.byKey(const Key('playlist:Band'))));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(titles(app, p.id), ['Zebra']);
    expect(find.byKey(const Key('selectionBar')), findsNothing);
  });

  testWidgets(
    '#122/AK3 selected tracks dragged onto a playlist go in together, in the order of the list',
    (tester) async {
      final app = await pumpApp(tester);
      final p = app.library.createPlaylist('Band');
      await tester.pump();
      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Zebra');
      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Ärger');
      await dragTo(
        tester,
        row('Zebra'),
        find.byKey(const Key('playlist:Band')),
      );
      expect(titles(app, p.id), ['Ärger', 'Zebra']);
      expect(marked('Ärger'), findsOneWidget, reason: 'the selection stays');
    },
  );

  testWidgets(
    '#122/AK3 «Add to playlist» in the context menu adds all selected tracks in list order',
    (tester) async {
      final app = await pumpApp(tester);
      final p = app.library.createPlaylist('Band');
      await tester.pump();
      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Zebra');
      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Ärger');
      await tester.tap(row('Zebra'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text(de.editTrackEllipsis), findsNothing);
      await tester.tap(find.byKey(const Key('addToPlaylist')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addTo:Band')));
      await tester.pumpAndSettle();
      expect(titles(app, p.id), ['Ärger', 'Zebra']);
    },
  );

  testWidgets('#122/AK3 a new playlist from the menu of the selection bar', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Bossa');
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Ärger');
    await tester.tap(find.byKey(const Key('selectionMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addToPlaylist')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addToNewPlaylist')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('nameField')), 'Solo');
    await tester.tap(find.byKey(const Key('nameOk')));
    await tester.pumpAndSettle();
    expect(titles(app, app.library.playlists.single.id), ['Ärger', 'Bossa']);
  });

  testWidgets('#122/AK4 selected tracks dragged onto a folder move together', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    final f = app.library.createFolder('Jazz');
    await tester.pumpAndSettle();
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Ärger');
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Zebra');
    await dragTo(tester, row('Ärger'), find.byKey(const Key('folder:Jazz')));
    expect(
      [for (final t in app.library.sortedTracksIn(f.id)) t.title],
      ['Ärger', 'Zebra'],
    );
    expect(app.library.track(idOf(app, 'Bossa'))!.folderId, isNull);
  });

  testWidgets(
    '#122/AK4 selected tracks dragged onto a track land before it, together',
    (tester) async {
      final app = await pumpApp(tester);
      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Bossa');
      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Zebra');
      await dragTo(tester, row('Zebra'), row('Ärger'));
      expect(
        [for (final t in app.library.sortedTracksIn(null)) t.title],
        ['Bossa', 'Zebra', 'Ärger'],
      );
    },
  );

  testWidgets(
    '#122/AK4 «Move to folder» in the context menu moves all selected',
    (tester) async {
      final app = await pumpApp(tester);
      final f = app.library.createFolder('Jazz');
      await tester.pumpAndSettle();
      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Bossa');
      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Zebra');
      await tester.tap(row('Bossa'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('moveToFolder')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('moveTo:Jazz')));
      await tester.pumpAndSettle();
      expect(
        [for (final t in app.library.sortedTracksIn(f.id)) t.title],
        ['Bossa', 'Zebra'],
      );

      // back without a folder; «No folder» is greyed out while all are there already
      await tester.tap(row('Bossa'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('moveToFolder')));
      await tester.pumpAndSettle();
      final jazz = tester.widget<MenuItemButton>(
        find.byKey(const Key('moveTo:Jazz')),
      );
      expect(jazz.onPressed, isNull);
      await tester.tap(find.byKey(const Key('moveToNoFolder')));
      await tester.pumpAndSettle();
      expect(app.library.sortedTracksIn(f.id), isEmpty);
    },
  );

  testWidgets(
    '#122/AK4 the selection bar acts on a single selected track too',
    (tester) async {
      final app = await pumpApp(tester);
      final f = app.library.createFolder('Jazz');
      await tester.pumpAndSettle();
      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Zebra');
      await tester.tap(find.byKey(const Key('selectionMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('moveToFolder')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('moveTo:Jazz')));
      await tester.pumpAndSettle();
      expect(
        [for (final t in app.library.sortedTracksIn(f.id)) t.title],
        ['Zebra'],
      );
    },
  );

  testWidgets(
    '#122/AK5 «Delete» for several tracks asks once and names the number',
    (tester) async {
      final app = await pumpApp(tester);
      final p = app.library.createPlaylist('Band');
      app.library.addToPlaylist(p.id, [idOf(app, 'Bossa')]);
      await tester.pump();
      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Bossa');
      await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Zebra');
      await tester.tap(row('Zebra'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteSelected')));
      await tester.pumpAndSettle();
      expect(find.text(de.deleteTracksTitle(2)), findsOneWidget);
      expect(find.text('2 Titel löschen?'), findsOneWidget);
      expect(find.text(de.deleteTracksText), findsOneWidget);

      // cancel keeps everything
      await tester.tap(find.text(de.cancel));
      await tester.pumpAndSettle();
      expect(app.library.tracks, hasLength(3));

      await tester.tap(row('Zebra'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deleteSelected')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing, reason: 'asked once');
      expect([for (final t in app.library.tracks) t.title], ['Ärger']);
      expect(app.library.playlistTracks(p.id), isEmpty);
      expect(find.byKey(const Key('selectionBar')), findsNothing);
    },
  );

  testWidgets('#122/AK5 the question names the number in English as well', (
    tester,
  ) async {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.deleteTracksTitle(1), 'Delete 1 track?');
    expect(en.deleteTracksTitle(3), 'Delete 3 tracks?');
    expect(de.deleteTracksTitle(1), '1 Titel löschen?');
    expect(de.selectionCount(4), '4 ausgewählt');
  });

  testWidgets('#122/AK6 Escape ends the selection', (tester) async {
    await pumpApp(tester);
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Bossa');
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Zebra');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(marked('Bossa'), findsNothing);
    expect(find.byKey(const Key('selectionBar')), findsNothing);
  });

  testWidgets('#122/AK6 a click on an empty area ends the selection', (
    tester,
  ) async {
    await pumpApp(tester);
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Bossa');
    final list = find.byKey(const Key('libraryBackground'));
    await tester.tapAt(tester.getBottomLeft(list) + const Offset(20, -10));
    await tester.pumpAndSettle();
    expect(marked('Bossa'), findsNothing);
  });

  testWidgets('#122/AK6 touch: Escape ends the selection mode as well', (
    tester,
  ) async {
    await pumpTouchLibrary(tester);
    await tester.longPress(row('Bossa'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checked:Bossa')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checked:Bossa')), findsNothing);
    expect(find.byKey(const Key('unchecked:Zebra')), findsNothing);
  });

  test('trackIds: one ID, several, or none for other data', () {
    expect(trackIds('a'), ['a']);
    expect(trackIds(['a', 'b']), ['a', 'b']);
    expect(trackIds(3), isNull);
    expect(trackIds(null), isNull);
  });

  testWidgets('#122 the selected row uses the soft amber of the theme', (
    tester,
  ) async {
    await pumpApp(tester);
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Bossa');
    final m = tester.widget<Material>(marked('Bossa'));
    expect(m.color, WsTheme.of(tester.element(marked('Bossa'))).amberSoft);
  });

  test(
    '#122/AK7 the new texts are in every ARB file, the numbers as ICU plural',
    () {
      final arbs = Directory('lib/l10n')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'))
          .toList();
      expect(arbs.length, greaterThanOrEqualTo(2));
      for (final f in arbs) {
        final arb = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
        for (final k in [
          'selectTracks',
          'selectionCount',
          'selectionActions',
          'selectionDone',
          'deleteTracksTitle',
          'deleteTracksText',
        ]) {
          expect(arb[k], isA<String>(), reason: '$k in ${f.path}');
        }
        for (final k in ['selectionCount', 'deleteTracksTitle']) {
          expect(
            arb[k],
            contains('{count, plural,'),
            reason: '$k in ${f.path}',
          );
        }
      }
    },
  );
}
