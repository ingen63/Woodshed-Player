// #121: files dragged in from outside onto playlists and folders of the library list. The native part is
// a fake (FakeFiles.fileDrag), the window finds the target by its real hit test. German UI (testLocale),
// widgets found by key.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/file_drop.dart';
import 'package:woodshed_player/app/file_platform.dart';

import 'fakes.dart';
import 'home_page_test.dart' show pumpApp;
import 'playlist_view_test.dart' show idOf, openPlaylist, titles;

/// The header [key] is lit as a drop target (the colour of a drag within the app).
bool headerLit(WidgetTester tester, String key) => tester
    .widgetList<Material>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(Material),
      ),
    )
    .any((m) => m.type == MaterialType.canvas);

/// The row [key] shows the line where a drop goes in.
bool rowLit(WidgetTester tester, String key) => tester
    .widgetList<Container>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(Container),
      ),
    )
    .any(
      (c) => switch (c.decoration) {
        BoxDecoration(border: Border(:final top)) => top.width == 2,
        _ => false,
      },
    );

void main() {
  late Directory src;
  setUp(() => src = Directory.systemTemp.createTempSync('wp_drop_src'));
  tearDown(() => src.deleteSync(recursive: true));

  String file(String name) =>
      (File('${src.path}/$name')..writeAsStringSync('audio $name')).path;

  Future<void> over(WidgetTester tester, TestApp app, Finder f) async {
    app.files.fileDrag!(FileDragOver(tester.getCenter(f)));
    await tester.pump();
  }

  Future<void> dropOn(
    WidgetTester tester,
    TestApp app,
    Finder f,
    List<String> paths,
    bool Function() done,
  ) async {
    final at = tester.getCenter(f);
    // the import reads real files: started outside the fake clock
    await tester.runAsync(() async {
      app.files.fileDrag!(FileDragDrop(paths, at));
    });
    await waitUntil(tester, () {
      app.finishLoads();
      return done();
    }, 'dropped files imported');
    await tester.pump();
  }

  testWidgets(
    '#121/AK1, AK4 files dropped on a playlist row go in before it; the row is lit while they hover',
    (tester) async {
      final app = await pumpApp(tester);
      final p = app.library.createPlaylist('Band');
      app.library.addToPlaylist(p.id, [idOf(app, 'Bossa'), idOf(app, 'Zebra')]);
      await tester.pump();
      await openPlaylist(tester, 'Band');

      final row = find.byKey(const Key('entry:Band:1'));
      expect(rowLit(tester, 'entry:Band:1'), isFalse);
      await over(tester, app, row);
      expect(app.controller.fileDropHover.value, PlaylistDropTarget(p.id, 1));
      expect(rowLit(tester, 'entry:Band:1'), isTrue);
      expect(rowLit(tester, 'entry:Band:0'), isFalse);
      expect(headerLit(tester, 'playlist:Band'), isFalse);

      await dropOn(tester, app, row, [
        file('b.mp3'),
        file('a.mp3'),
      ], () => app.library.tracks.length == 5);
      expect(titles(app, p.id), ['Bossa', 'b', 'a', 'Zebra']);
      expect(rowLit(tester, 'entry:Band:1'), isFalse);
      expect(app.controller.fileDropHover.value, isNull);
    },
  );

  testWidgets(
    '#121/AK1, AK4 files dropped on a playlist heading go to its end; the heading is lit like a drag within the app',
    (tester) async {
      final app = await pumpApp(tester);
      final p = app.library.createPlaylist('Band');
      app.library.addToPlaylist(p.id, [idOf(app, 'Bossa')]);
      await tester.pump();
      final header = find.byKey(const Key('playlist:Band'));

      // the look of a drag within the app
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('track:Zebra'))),
        kind: PointerDeviceKind.mouse,
      );
      await g.moveBy(const Offset(0, 20));
      await tester.pump();
      await g.moveTo(tester.getCenter(header));
      await tester.pump();
      expect(headerLit(tester, 'playlist:Band'), isTrue);
      await g.moveTo(Offset.zero);
      await g.cancel();
      await tester.pumpAndSettle();
      expect(headerLit(tester, 'playlist:Band'), isFalse);

      await over(tester, app, header);
      expect(headerLit(tester, 'playlist:Band'), isTrue);
      app.files.fileDrag!(const FileDragLeave());
      await tester.pump();
      expect(headerLit(tester, 'playlist:Band'), isFalse);

      await over(tester, app, header);
      await dropOn(tester, app, header, [
        file('a.mp3'),
      ], () => titles(app, p.id).length == 2);
      expect(titles(app, p.id), ['Bossa', 'a']);
      expect(headerLit(tester, 'playlist:Band'), isFalse);
    },
  );

  testWidgets('#121/AK1 files dropped on an empty open playlist go into it', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    final p = app.library.createPlaylist('Band');
    await tester.pump();
    await openPlaylist(tester, 'Band');
    final empty = find.text(de.emptyPlaylist);
    await over(tester, app, empty);
    expect(app.controller.fileDropHover.value, PlaylistDropTarget(p.id));
    await dropOn(tester, app, empty, [
      file('a.mp3'),
    ], () => titles(app, p.id).isNotEmpty);
    expect(titles(app, p.id), ['a']);
  });

  testWidgets(
    '#121/AK3, AK4 files dropped on a folder or its tracks land in it; its heading is lit while they hover',
    (tester) async {
      final app = await pumpApp(tester);
      final f = app.library.createFolder('Etüden');
      app.library.moveTracks({idOf(app, 'Zebra')}, f.id);
      await tester.pump();

      await over(tester, app, find.byKey(const Key('track:Zebra')));
      expect(app.controller.fileDropHover.value, FolderDropTarget(f.id));
      expect(headerLit(tester, 'folder:Etüden'), isTrue);
      expect(headerLit(tester, 'section:none'), isFalse);
      expect(rowLit(tester, 'track:Zebra'), isFalse);

      await over(tester, app, find.byKey(const Key('track:Bossa')));
      expect(app.controller.fileDropHover.value, const FolderDropTarget(null));
      expect(headerLit(tester, 'folder:Etüden'), isFalse);
      expect(headerLit(tester, 'section:none'), isTrue);

      final header = find.byKey(const Key('folder:Etüden'));
      await over(tester, app, header);
      await dropOn(tester, app, header, [
        file('a.mp3'),
      ], () => app.library.tracks.length == 4);
      expect(app.library.sortedTracksIn(f.id).map((t) => t.title), [
        'a',
        'Zebra',
      ]);
      expect(headerLit(tester, 'folder:Etüden'), isFalse);
    },
  );

  testWidgets(
    '#121 files dropped elsewhere only come into the library, as before (#22)',
    (tester) async {
      final app = await pumpApp(tester);
      final f = app.library.createFolder('Etüden');
      await tester.pump();
      await over(tester, app, find.byKey(const Key('playerScreen')));
      expect(app.controller.fileDropHover.value, isNull);
      await dropOn(tester, app, find.byKey(const Key('playerScreen')), [
        file('a.mp3'),
      ], () => app.library.tracks.length == 4);
      expect(app.library.sortedTracksIn(f.id), isEmpty);
      expect(app.library.playlists, isEmpty);
    },
  );
}
