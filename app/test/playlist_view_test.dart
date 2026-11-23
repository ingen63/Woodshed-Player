// #114: playlists in the library list. Fakes for core, file picker and metronome; the library lives in a
// temporary folder. The language is set to German (testLocale), the tests find widgets by key.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/player/play_queue.dart';

import 'fakes.dart';
import 'home_page_test.dart' show dragTo, pumpApp;

String idOf(TestApp app, String title) =>
    app.library.tracks.firstWhere((t) => t.title == title).id;

List<String> titles(TestApp app, String playlistId) => [
  for (final t in app.library.playlistTracks(playlistId)) t.title,
];

/// Opens the «⋯» menu of the playlist [name].
Future<void> openPlaylistMenu(WidgetTester tester, String name) async {
  await tester.tap(
    find.byKey(Key('playlist:$name')),
    buttons: kSecondaryButton,
  );
  await tester.pumpAndSettle();
}

/// Opens the playlist [name] (collapsed at first).
Future<void> openPlaylist(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(Key('playlist:$name')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '#114/AK1 create, rename and delete a playlist in the library; the tracks stay',
    (tester) async {
      final app = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('newPlaylist')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('nameField')), 'Band');
      await tester.tap(find.byKey(const Key('nameOk')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playlist:Band')), findsOneWidget);

      await openPlaylistMenu(tester, 'Band');
      await tester.tap(find.text(de.renameEllipsis));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('nameField')), 'Konzert');
      await tester.tap(find.byKey(const Key('nameOk')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playlist:Konzert')), findsOneWidget);

      await openPlaylistMenu(tester, 'Konzert');
      await tester.tap(find.byKey(const Key('deletePlaylist:Konzert')));
      await tester.pumpAndSettle();
      expect(find.text(de.deletePlaylistText), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('playlist:Konzert')), findsNothing);
      expect(app.library.playlists, isEmpty);
      expect(app.library.tracks, hasLength(3));
    },
  );

  testWidgets(
    '#114/AK2, AK3 add by context menu and by dragging, twice too; remove from the playlist only',
    (tester) async {
      final app = await pumpApp(tester);
      final p = app.library.createPlaylist('Band');
      await tester.pump();

      await tester.tap(find.byKey(const Key('menu:Bossa')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addToPlaylist')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addTo:Band')));
      await tester.pumpAndSettle();
      expect(titles(app, p.id), ['Bossa']);

      await dragTo(
        tester,
        find.byKey(const Key('track:Zebra')),
        find.byKey(const Key('playlist:Band')),
      );
      await dragTo(
        tester,
        find.byKey(const Key('track:Bossa')),
        find.byKey(const Key('playlist:Band')),
      );
      expect(titles(app, p.id), ['Bossa', 'Zebra', 'Bossa']);

      await openPlaylist(tester, 'Band');
      expect(find.byKey(const Key('entry:Band:2')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('entry:Band:1')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('removeFromPlaylist')));
      await tester.pumpAndSettle();
      expect(titles(app, p.id), ['Bossa', 'Bossa']);
      expect(app.library.track(idOf(app, 'Zebra')), isNotNull);
      expect(find.byKey(const Key('track:Zebra')), findsOneWidget);
    },
  );

  testWidgets('#114/AK2 «New playlist …» in the context menu of a track', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('menu:Zebra')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addToPlaylist')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addToNewPlaylist')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('nameField')), 'Solo');
    await tester.tap(find.byKey(const Key('nameOk')));
    await tester.pumpAndSettle();
    final p = app.library.playlists.single;
    expect(p.name, 'Solo');
    expect(titles(app, p.id), ['Zebra']);
  });

  testWidgets('#114/AK4 the order changes by dragging rows of the playlist', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    final p = app.library.createPlaylist('Band');
    app.library.addToPlaylist(p.id, [
      for (final t in ['Ärger', 'Bossa', 'Zebra']) idOf(app, t),
    ]);
    await tester.pump();
    await openPlaylist(tester, 'Band');
    // the last row before the first
    await dragTo(
      tester,
      find.byKey(const Key('entry:Band:2')),
      find.byKey(const Key('entry:Band:0')),
    );
    expect(titles(app, p.id), ['Zebra', 'Ärger', 'Bossa']);
    // a row dropped on the heading goes to the end
    await dragTo(
      tester,
      find.byKey(const Key('entry:Band:0')),
      find.byKey(const Key('playlist:Band')),
    );
    expect(titles(app, p.id), ['Ärger', 'Bossa', 'Zebra']);
    // a row of another playlist is copied
    final q = app.library.createPlaylist('Aufwärmen');
    await tester.pump();
    await dragTo(
      tester,
      find.byKey(const Key('entry:Band:1')),
      find.byKey(const Key('playlist:Aufwärmen')),
    );
    expect(titles(app, q.id), ['Bossa']);
    expect(titles(app, p.id), ['Ärger', 'Bossa', 'Zebra']);
  });

  testWidgets(
    '#124/AK1, AK3 «Sort by» in the playlist menu offers every criterion both ways; dragging goes on',
    (tester) async {
      final app = await pumpApp(tester);
      final p = app.library.createPlaylist('Band');
      app.library.addToPlaylist(p.id, [
        for (final t in ['Bossa', 'Ärger', 'Zebra', 'Bossa']) idOf(app, t),
      ]);
      await tester.pump();
      await openPlaylist(tester, 'Band');

      await openPlaylistMenu(tester, 'Band');
      await tester.tap(find.byKey(const Key('sortPlaylist:Band')));
      await tester.pumpAndSettle();
      expect(find.text(de.sortPlaylistBy), findsOneWidget);
      for (final key in ['title', 'artist', 'duration', 'dateAdded']) {
        for (final (dir, text) in [
          ('asc', 'ascending'),
          ('desc', 'descending'),
        ]) {
          final item = find.byKey(Key('sortBy:$key:$dir'));
          expect(item, findsOneWidget);
          expect(
            find.descendant(
              of: item,
              matching: find.text(de.sortPlaylistOption(key, text)),
            ),
            findsOneWidget,
          );
        }
      }
      expect(
        de.sortPlaylistOption('duration', 'descending'),
        'Dauer, absteigend',
      );
      await tester.tap(find.byKey(const Key('sortBy:title:desc')));
      await tester.pumpAndSettle();
      expect(titles(app, p.id), ['Zebra', 'Bossa', 'Bossa', 'Ärger']);

      await openPlaylistMenu(tester, 'Band');
      await tester.tap(find.byKey(const Key('sortPlaylist:Band')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sortBy:title:asc')));
      await tester.pumpAndSettle();
      expect(titles(app, p.id), ['Ärger', 'Bossa', 'Bossa', 'Zebra']);

      // #124/AK3: the sorted order is the playlist's own and can be dragged further
      await dragTo(
        tester,
        find.byKey(const Key('entry:Band:3')),
        find.byKey(const Key('entry:Band:0')),
      );
      expect(titles(app, p.id), ['Zebra', 'Ärger', 'Bossa', 'Bossa']);
    },
  );

  testWidgets(
    '#114/AK9, AK11 the library shows a cloud or a device per playlist; the menu switches it',
    (tester) async {
      final app = await pumpApp(tester);
      final p = app.library.createPlaylist('Band');
      await tester.pump();
      expect(find.byKey(const Key('shared:Band')), findsOneWidget);
      expect(find.byKey(const Key('local:Band')), findsNothing);

      await openPlaylistMenu(tester, 'Band');
      await tester.tap(find.byKey(const Key('shareLocal:Band')).first);
      await tester.pumpAndSettle();
      expect(app.library.playlists.single.shared, isFalse);
      expect(find.byKey(const Key('local:Band')), findsOneWidget);
      expect(find.byTooltip(de.playlistOnThisDevice), findsOneWidget);

      await openPlaylistMenu(tester, 'Band');
      await tester.tap(find.byKey(const Key('shareAll:Band')).first);
      await tester.pumpAndSettle();
      expect(app.library.playlists.single.shared, isTrue);
      expect(app.library.playlist(p.id), isNull); // a new ID since it was local
      expect(find.byKey(const Key('shared:Band')), findsOneWidget);
    },
  );

  testWidgets(
    '#114/AK5 «Play» starts the playlist; a tap on a row loads it as part of the playlist',
    (tester) async {
      final app = await pumpApp(tester);
      final p = app.library.createPlaylist('Band');
      app.library.addToPlaylist(p.id, [idOf(app, 'Zebra'), idOf(app, 'Bossa')]);
      await tester.pump();

      await tester.tap(find.byKey(const Key('playPlaylist:Band')));
      await tester.pump();
      app.finishLoads(30);
      await tester.pump();
      expect(app.player.trackId, idOf(app, 'Zebra'));
      expect(app.player.isPlaying, isTrue);

      await openPlaylist(tester, 'Band');
      await tester.tap(find.byKey(const Key('entry:Band:1')));
      await tester.pump();
      app.finishLoads(30);
      await tester.pump();
      expect(app.controller.queue, PlayQueue(p.id, 1));
      expect(app.player.trackId, idOf(app, 'Bossa'));
    },
  );
}
