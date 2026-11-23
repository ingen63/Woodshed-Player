// #123: the section «Library» (all tracks) in the library list is closed by default, so the playlists show
// without scrolling. Its state is kept per device (`device.json`). German UI (testLocale), widgets found by
// key.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/file_drop.dart';
import 'package:woodshed_player/app/file_platform.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/ui/style.dart';

import 'fakes.dart';
import 'file_drop_view_test.dart' show headerLit;
import 'home_page_test.dart' show phone, pumpApp, wide;
import 'playlist_view_test.dart' show idOf, openPlaylist;

/// Enough tracks to push the playlists below the window while the section is open.
final many = [
  for (var i = 0; i < 40; i++) 'Titel ${i.toString().padLeft(2, '0')}',
];

const section = Key('section:library');

void main() {
  for (final (name, size) in [('desktop', wide), ('phone', phone)]) {
    testWidgets(
      '#123/AK1 first start ($name): the section is closed, the playlists show without scrolling',
      (tester) async {
        final app = await pumpApp(
          tester,
          size: size,
          titles: many,
          libraryOpen: false,
        );
        final p = app.library.createPlaylist('Band');
        app.library.addToPlaylist(p.id, [idOf(app, 'Titel 00')]);
        await tester.pump();

        expect(app.library.libraryOpen, isFalse);
        expect(find.byKey(section), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(section),
            matching: find.text('Bibliothek'),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('track:Titel 00')), findsNothing);
        final header = find.byKey(const Key('playlist:Band'));
        expect(header, findsOneWidget);
        expect(tester.getRect(header).bottom, lessThan(size.height));
        // the count of all tracks stays visible on the closed section
        expect(
          find.descendant(of: find.byKey(section), matching: find.text('40')),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('#123/AK1 open, the many tracks push the playlists below', (
    tester,
  ) async {
    final app = await pumpApp(tester, titles: many);
    app.library.createPlaylist('Band');
    await tester.pump();
    expect(app.library.libraryOpen, isTrue);
    final first = app.library.sortedTracks.first.title;
    expect(find.byKey(Key('track:$first')), findsOneWidget);
    expect(find.byKey(const Key('playlist:Band')), findsNothing); // not built
  });

  testWidgets('#123/AK2 a tap on the section opens it and closes it again', (
    tester,
  ) async {
    final app = await pumpApp(tester, libraryOpen: false);
    expect(find.byKey(const Key('track:Bossa')), findsNothing);
    expect(find.byIcon(WsIcons.chevronRight), findsOneWidget);

    await tester.tap(find.byKey(section));
    await tester.pump();
    expect(app.library.libraryOpen, isTrue);
    expect(find.byKey(const Key('track:Bossa')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(section),
        matching: find.byIcon(WsIcons.chevronDown),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(section));
    await tester.pump();
    expect(app.library.libraryOpen, isFalse);
    expect(find.byKey(const Key('track:Bossa')), findsNothing);
  });

  test('#123/AK3 the state is kept per device after a restart', () async {
    final dir = Directory.systemTemp.createTempSync('wp_library_section');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/${DeviceSettings.fileName}');

    final first = TestApp(dir, libraryOpen: false);
    final Library lib = first.library;
    await lib.load();
    expect(lib.libraryOpen, isFalse);
    var notified = 0;
    lib.addListener(() => notified++);
    await lib.setLibraryOpen(true);
    expect(notified, 1);
    await lib.setLibraryOpen(true); // unchanged: no write, no notice
    expect(notified, 1);
    expect(jsonDecode(file.readAsStringSync())['libraryOpen'], isTrue);

    final again = TestApp(dir);
    await again.library.load();
    expect(again.library.libraryOpen, isTrue);
    await again.library.setLibraryOpen(false);
    expect(file.readAsStringSync(), isNot(contains('libraryOpen')));

    final third = TestApp(dir);
    await third.library.load();
    expect(third.library.libraryOpen, isFalse);
    // device-local: the device ID stays the one of the first start
    expect(third.library.device.deviceId, first.library.device.deviceId);
  });

  test('#123/AK3 device.json: closed unless the value is true', () {
    const d = DeviceSettings(deviceId: '0123456789abcdef');
    expect(d.libraryOpen, isFalse);
    expect(d.toJson().containsKey('libraryOpen'), isFalse);
    final open = d.copyWith(libraryOpen: true);
    expect(open.toJson()['libraryOpen'], isTrue);
    expect(open.copyWith().libraryOpen, isTrue);
    expect(open.copyWith(libraryOpen: false).libraryOpen, isFalse);
  });

  test('#123/AK3 device.json: a wrong value reads as closed', () async {
    for (final (raw, want) in [
      ('true', true),
      ('"true"', false),
      ('1', false),
      ('false', false),
    ]) {
      final store = MemoryFileStore();
      await store.write(
        DeviceSettings.fileName,
        Uint8List.fromList(
          utf8.encode('{"deviceId":"0123456789abcdef","libraryOpen":$raw}'),
        ),
      );
      final d = await DeviceSettings.load(store);
      expect(d.libraryOpen, want, reason: raw);
      expect(d.deviceId, '0123456789abcdef');
    }
  });

  for (final (name, size) in [('desktop', wide), ('phone', phone)]) {
    testWidgets(
      '#123/AK4 ($name) the playing track stays reachable with the section closed',
      (tester) async {
        final app = await pumpApp(tester, size: size, libraryOpen: false);
        final p = app.library.createPlaylist('Band');
        app.library.addToPlaylist(p.id, [idOf(app, 'Bossa')]);
        await tester.pump();
        await tester.tap(find.byKey(const Key('playPlaylist:Band')));
        await tester.pump();
        app.finishLoads();
        await tester.pump();
        expect(app.controller.player.title, 'Bossa');
        expect(find.byKey(const Key('track:Bossa')), findsNothing);

        // in the playlist
        await openPlaylist(tester, 'Band');
        expect(find.byKey(const Key('entry:Band:0')), findsOneWidget);

        // in the player display: beside the list on the desktop, behind the mini bar on the phone
        if (size == phone) {
          await tester.tap(find.byKey(const Key('openPlayer')));
          await tester.pumpAndSettle();
        }
        expect(
          tester.widget<Text>(find.byKey(const Key('playerTitle'))).data,
          'Bossa',
        );
      },
    );
  }

  testWidgets(
    '#123/AK5 files dropped on the closed section go in without a folder; it is lit while they hover',
    (tester) async {
      final app = await pumpApp(tester, libraryOpen: false);
      app.library.createFolder('Ordner');
      await tester.pump();
      final src = Directory.systemTemp.createTempSync('wp_section_src');
      addTearDown(() => src.deleteSync(recursive: true));
      final path = (File('${src.path}/neu.mp3')..writeAsStringSync('a')).path;
      final header = find.byKey(section);

      app.files.fileDrag!(FileDragOver(tester.getCenter(header)));
      await tester.pump();
      expect(app.controller.fileDropHover.value, const FolderDropTarget(null));
      expect(headerLit(tester, 'section:library'), isTrue);

      final at = tester.getCenter(header);
      await tester.runAsync(() async {
        app.files.fileDrag!(FileDragDrop([path], at));
      });
      await waitUntil(tester, () {
        app.finishLoads();
        return app.library.tracks.length == 4;
      }, 'dropped file imported');
      await tester.pump();
      final t = app.library.tracks.firstWhere((t) => t.title == 'neu');
      expect(t.folderId, isNull);
      expect(app.library.libraryOpen, isFalse); // stays closed
      expect(headerLit(tester, 'section:library'), isFalse);
    },
  );

  testWidgets(
    '#123/AK5 with the section closed a playlist heading still takes files',
    (tester) async {
      final app = await pumpApp(tester, libraryOpen: false);
      final p = app.library.createPlaylist('Band');
      await tester.pump();
      final src = Directory.systemTemp.createTempSync('wp_section_src');
      addTearDown(() => src.deleteSync(recursive: true));
      final path = (File('${src.path}/neu.mp3')..writeAsStringSync('a')).path;
      final at = tester.getCenter(find.byKey(const Key('playlist:Band')));
      await tester.runAsync(() async {
        app.files.fileDrag!(FileDragDrop([path], at));
      });
      await waitUntil(tester, () {
        app.finishLoads();
        return app.library.playlistTracks(p.id).length == 1;
      }, 'dropped file in the playlist');
      expect(app.library.playlistTracks(p.id).single.title, 'neu');
    },
  );
}
