// #24: edit title and artist of a track. Temporary folders and in-memory stores only, never the real
// library.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/file_store_io.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/library/metadata.dart';

import 'fakes.dart';
import 'home_page_test.dart' show pumpApp, select;
import 'metadata_test.dart' show id3, text;

late Directory tmp;

Library open(FileStore store) => Library(
  store,
  probe: (_) => 2.5,
  readSource: readLocalFile,
  saveDelay: Duration.zero,
  random: Random(7),
);

Future<Library> loaded(FileStore store) async {
  final l = open(store);
  await l.load();
  await l.hashing;
  return l;
}

/// Source file with ID3 tags (title «Tag title», artist «Tag artist»).
File taggedSource() {
  final f = File('${tmp.path}/src/tagged.mp3')..createSync(recursive: true);
  f.writeAsBytesSync(
    id3(3, [('TIT2', text(0, 'Tag title')), ('TPE1', text(0, 'Tag artist'))]),
  );
  return f;
}

Map<String, Object?> indexTrack(Directory base, String id) {
  final j = jsonDecode(File('${base.path}/library.json').readAsStringSync());
  return ((j as Map)['tracks'] as List)
      .cast<Map<String, Object?>>()
      .firstWhere((t) => t['id'] == id);
}

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_track_edit'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('#24 library', () {
    test('#24/AK2 change title and artist', () async {
      final l = await loaded(IoFileStore(Directory('${tmp.path}/lib')));
      final t = (await l.importFiles([taggedSource().path])).imported.single;
      var notified = 0;
      l.addListener(() => notified++);
      expect(
        l.editMetadata(t.id, title: '  New title ', artist: ' New artist '),
        isTrue,
      );
      expect(l.track(t.id)!.title, 'New title');
      expect(l.track(t.id)!.artist, 'New artist');
      expect(notified, greaterThan(0));
    });

    test('#24/AK3 saved in library.json and kept after reload', () async {
      final base = Directory('${tmp.path}/lib');
      final l = await loaded(IoFileStore(base));
      final t = (await l.importFiles([taggedSource().path])).imported.single;
      l.editMetadata(t.id, title: 'New title', artist: 'New artist');
      await l.save();
      final json = indexTrack(base, t.id);
      expect(json['title'], 'New title');
      expect(json['artist'], 'New artist');

      final again = await loaded(IoFileStore(base));
      expect(again.track(t.id)!.title, 'New title');
      expect(again.track(t.id)!.artist, 'New artist');
    });

    test('#24/AK3 also in the browser store (OPFS model)', () async {
      final store = MemoryFileStore();
      store.files['picked'] = taggedSource().readAsBytesSync();
      Library web() => Library(
        store,
        probe: (_) => null,
        readSource: (s) async => store.files[s],
        saveDelay: Duration.zero,
      );
      final w = web();
      await w.load();
      final t = (await w.importFiles(['picked'])).imported.single;
      w.editMetadata(t.id, title: 'Web title', artist: '');
      await w.save();
      final again = web();
      await again.load();
      expect(again.track(t.id)!.title, 'Web title');
      expect(again.track(t.id)!.artist, isNull);
    });

    test('#24/AK4 audio file, tags and contentHash unchanged', () async {
      final base = Directory('${tmp.path}/lib');
      final l = await loaded(IoFileStore(base));
      final t = (await l.importFiles([taggedSource().path])).imported.single;
      final file = File('${base.path}/Tracks/${t.fileName}');
      final before = file.readAsBytesSync();
      final modified = file.lastModifiedSync();
      l.editMetadata(t.id, title: 'New title', artist: 'New artist');
      await l.save();
      expect(file.readAsBytesSync(), before);
      expect(file.lastModifiedSync(), modified);
      final tags = readMetadata(file.readAsBytesSync());
      expect(tags.title, 'Tag title');
      expect(tags.artist, 'Tag artist');
      expect(l.track(t.id)!.contentHash, t.contentHash);
      expect(indexTrack(base, t.id)['contentHash'], t.contentHash);
      expect(l.track(t.id)!.fileName, t.fileName);
    });

    test('#24/AK5 blank title rejected, blank artist allowed', () async {
      final base = Directory('${tmp.path}/lib');
      final l = await loaded(IoFileStore(base));
      final t = (await l.importFiles([taggedSource().path])).imported.single;
      expect(l.editMetadata(t.id, title: '   ', artist: 'X'), isFalse);
      expect(l.editMetadata(t.id, title: '', artist: 'X'), isFalse);
      expect(l.track(t.id)!.title, 'Tag title');
      expect(l.track(t.id)!.artist, 'Tag artist');

      expect(l.editMetadata(t.id, title: 'Only title', artist: '  '), isTrue);
      expect(l.track(t.id)!.artist, isNull);
      await l.save();
      expect(indexTrack(base, t.id).containsKey('artist'), isFalse);
    });

    test('#24/AK6 alphabetical sorting uses the new title', () async {
      final l = await loaded(IoFileStore(Directory('${tmp.path}/lib')));
      Future<Track> add(String name) async {
        final f = File('${tmp.path}/src/$name.mp3')
          ..createSync(recursive: true)
          ..writeAsStringSync('audio $name');
        return (await l.importFiles([f.path])).imported.single;
      }

      final a = await add('Alpha');
      await add('Beta');
      await add('Gamma');
      l.sortOrder = TrackSortOrder.alphabetical;
      expect(l.sortedTracks.map((t) => t.title), ['Alpha', 'Beta', 'Gamma']);
      l.editMetadata(a.id, title: 'Zulu', artist: null);
      expect(l.sortedTracks.map((t) => t.title), ['Beta', 'Gamma', 'Zulu']);
    });
  });

  group('#24 dialog', () {
    testWidgets('#24/AK1 #24/AK2 edit via context menu, library and player '
        'update', (tester) async {
      final app = await pumpApp(tester);
      await select(tester, app, 'Bossa');
      await tester.tap(
        find.byKey(const Key('track:Bossa')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(de.editTrackEllipsis));
      await tester.pumpAndSettle();
      expect(find.text(de.editTrackTitle), findsOneWidget);
      await tester.enterText(find.byKey(const Key('titleField')), 'Samba');
      await tester.enterText(find.byKey(const Key('artistField')), 'Duo');
      await tester.tap(find.byKey(const Key('editSave')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('track:Samba')), findsOneWidget);
      expect(find.byKey(const Key('track:Bossa')), findsNothing);
      final title = tester.widget<Text>(find.byKey(const Key('trackTitle')));
      expect(title.data, 'Samba');
      expect(find.text('Duo'), findsWidgets);
      final t = app.library.track(app.player.trackId!)!;
      expect((t.title, t.artist), ('Samba', 'Duo'));
    });

    testWidgets('#24/AK2 cancel changes nothing', (tester) async {
      final app = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('menu:Zebra')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editTrack')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('titleField')), 'Other');
      await tester.enterText(find.byKey(const Key('artistField')), 'Someone');
      await tester.tap(find.byKey(const Key('editCancel')));
      await tester.pumpAndSettle();
      final t = app.library.tracks.singleWhere((t) => t.title == 'Zebra');
      expect(t.artist, isNull);
      expect(find.byKey(const Key('track:Zebra')), findsOneWidget);
    });

    testWidgets('#24/AK5 Save disabled while the title is blank', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await tester.tap(find.byKey(const Key('menu:Zebra')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editTrack')));
      await tester.pumpAndSettle();
      TextButton save() =>
          tester.widget<TextButton>(find.byKey(const Key('editSave')));
      expect(save().onPressed, isNotNull);
      await tester.enterText(find.byKey(const Key('titleField')), '   ');
      await tester.pump();
      expect(save().onPressed, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editSave')), findsOneWidget); // still open
      await tester.enterText(find.byKey(const Key('titleField')), 'Zed');
      await tester.enterText(find.byKey(const Key('artistField')), '');
      await tester.pump();
      expect(save().onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('editSave')));
      await tester.pumpAndSettle();
      final t = app.library.tracks.singleWhere((t) => t.title == 'Zed');
      expect(t.artist, isNull);
    });
  });
}
