// #146: subfolders in the library list: new subfolder, indentation, open and closed, dragging folders
// (mouse and long press), the question before deleting. Fakes for core, file picker and metronome; the
// library lives in a temporary folder. German UI (testLocale), widgets found by key.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/l10n/app_localizations.dart';
import 'package:woodshed_player/library/library.dart';

import 'fakes.dart';
import 'home_page_test.dart' show dragTo, pumpApp;
import 'selection_view_test.dart' show pumpTouchLibrary;

Finder folder(String name) => find.byKey(Key('folder:$name'));

double left(WidgetTester tester, String name) => tester
    .getTopLeft(find.descendant(of: folder(name), matching: find.text(name)))
    .dx;

Future<void> openMenu(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: folder(name), matching: find.byType(IconButton)),
  );
  await tester.pumpAndSettle();
}

String idOf(TestApp app, String name) =>
    app.library.folders.firstWhere((f) => f.name == name).id;

void main() {
  final de = lookupAppLocalizations(testLocale);

  testWidgets(
    '#146/AK1 «New subfolder» in the menu of a folder puts it inside',
    (tester) async {
      final app = await pumpApp(tester);
      final rec = app.library.createFolder('Recordings');
      await tester.pump();
      await openMenu(tester, 'Recordings');
      await tester.tap(find.byKey(const Key('newSubfolder:Recordings')));
      await tester.pumpAndSettle();
      expect(find.text(de.newSubfolder), findsOneWidget);
      await tester.enterText(find.byKey(const Key('nameField')), '2026-11-25');
      await tester.tap(find.byKey(const Key('nameOk')));
      await tester.pumpAndSettle();
      final day = app.library.folders.firstWhere((f) => f.name == '2026-11-25');
      expect(day.parentId, rec.id);
      expect(folder('2026-11-25'), findsOneWidget);
    },
  );

  testWidgets('#146/AK1 ⇧⌘N still makes a folder on the top level', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('libraryMoreMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('newFolder')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('nameField')), 'Oben');
    await tester.tap(find.byKey(const Key('nameOk')));
    await tester.pumpAndSettle();
    expect(app.library.folders.single.parentId, isNull);
  });

  testWidgets(
    '#146/AK2 subfolders indented under their folder, each opens and closes on its own',
    (tester) async {
      final app = await pumpApp(tester);
      final lib = app.library;
      final a = lib.createFolder('A');
      final b = lib.createFolder('B', parentId: a.id);
      final c = lib.createFolder('C', parentId: b.id);
      lib.moveTracks({
        lib.tracks.firstWhere((t) => t.title == 'Zebra').id,
      }, c.id);
      await tester.pumpAndSettle();
      expect(left(tester, 'B'), greaterThan(left(tester, 'A')));
      expect(left(tester, 'C'), greaterThan(left(tester, 'B')));
      final ys = [
        for (final n in ['A', 'B', 'C']) tester.getTopLeft(folder(n)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      final zebra = find.byKey(const Key('track:Zebra'));
      expect(
        tester
            .getTopLeft(
              find.descendant(of: zebra, matching: find.text('Zebra')),
            )
            .dx,
        greaterThan(left(tester, 'C')),
      );

      // closing B hides C and its tracks; A stays open
      await tester.tap(folder('B'));
      await tester.pumpAndSettle();
      expect(lib.folderClosed(b.id), isTrue);
      expect(folder('C'), findsNothing);
      expect(zebra, findsNothing);
      expect(folder('B'), findsOneWidget);
      // closing C alone, then opening B: C shows, closed
      await tester.tap(folder('B'));
      await tester.pumpAndSettle();
      await tester.tap(folder('C'));
      await tester.pumpAndSettle();
      expect(folder('C'), findsOneWidget);
      expect(zebra, findsNothing);
      expect(lib.folderClosed(c.id), isTrue);
      expect(lib.folderClosed(a.id), isFalse);
    },
  );

  testWidgets(
    '#146/AK3 dragging a folder onto another puts it inside, onto «No folder» on the top level',
    (tester) async {
      final app = await pumpApp(tester);
      final lib = app.library;
      final a = lib.createFolder('A');
      final b = lib.createFolder('B');
      await tester.pump();
      await dragTo(tester, folder('B'), folder('A'));
      expect(lib.folder(b.id)?.parentId, a.id);
      await tester.pumpAndSettle();
      await dragTo(tester, folder('B'), find.byKey(const Key('section:none')));
      expect(lib.folder(b.id)?.parentId, isNull);
    },
  );

  testWidgets('#146/AK3 tracks go into a subfolder by dragging', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    final lib = app.library;
    final a = lib.createFolder('A');
    final b = lib.createFolder('B', parentId: a.id);
    await tester.pump();
    await dragTo(tester, find.byKey(const Key('track:Bossa')), folder('B'));
    expect(lib.tracks.firstWhere((t) => t.title == 'Bossa').folderId, b.id);
  });

  testWidgets('#146/AK3 «Move to folder» lists subfolders too', (tester) async {
    final app = await pumpApp(tester);
    final lib = app.library;
    final a = lib.createFolder('A');
    final b = lib.createFolder('B', parentId: a.id);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu:Bossa')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('moveToFolder')));
    await tester.pumpAndSettle();
    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: find.byKey(const Key('moveTo:B')),
              matching: find.text('B'),
            ),
          )
          .dx,
      greaterThan(
        tester
            .getTopLeft(
              find.descendant(
                of: find.byKey(const Key('moveTo:A')),
                matching: find.text('A'),
              ),
            )
            .dx,
      ),
    );
    await tester.tap(find.byKey(const Key('moveTo:B')));
    await tester.pumpAndSettle();
    expect(lib.tracks.firstWhere((t) => t.title == 'Bossa').folderId, b.id);
  });

  testWidgets(
    '#146/AK3 on iPhone/iPad a folder is dragged after a long press',
    (tester) async {
      final app = await pumpTouchLibrary(tester);
      final lib = app.library;
      final a = lib.createFolder('A');
      final b = lib.createFolder('B');
      await tester.pumpAndSettle();
      // a short drag scrolls, it moves nothing
      await dragTo(tester, folder('B'), folder('A'));
      await tester.pumpAndSettle();
      expect(lib.folder(b.id)?.parentId, isNull);
      final g = await tester.startGesture(tester.getCenter(folder('B')));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await g.moveBy(const Offset(0, 20));
      await tester.pump();
      await g.moveTo(tester.getCenter(folder('A')));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(lib.folder(b.id)?.parentId, a.id);
    },
  );

  testWidgets('#146/AK4 a folder dropped on itself or its subfolder stays', (
    tester,
  ) async {
    final app = await pumpApp(tester);
    final lib = app.library;
    final a = lib.createFolder('A');
    final b = lib.createFolder('B', parentId: a.id);
    await tester.pump();
    await dragTo(tester, folder('A'), folder('B'));
    await tester.pumpAndSettle();
    expect(lib.folder(a.id)?.parentId, isNull);
    expect(lib.folder(b.id)?.parentId, a.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '#146/AK5 deleting a folder with subfolders names the counts and deletes them',
    (tester) async {
      final app = await pumpApp(tester);
      final lib = app.library;
      final a = lib.createFolder('A');
      final b = lib.createFolder('B', parentId: a.id);
      final c = lib.createFolder('C', parentId: b.id);
      lib.moveTracks({
        lib.tracks.firstWhere((t) => t.title == 'Zebra').id,
      }, c.id);
      lib.moveTracks({
        lib.tracks.firstWhere((t) => t.title == 'Bossa').id,
      }, a.id);
      await tester.pumpAndSettle();
      await openMenu(tester, 'A');
      await tester.tap(find.text(de.deleteFolder));
      await tester.pumpAndSettle();
      expect(find.text(de.deleteFolderTreeText(3, 2)), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm')));
      await tester.pumpAndSettle();
      expect(lib.folders, isEmpty);
      expect(lib.tracks, hasLength(3));
    },
  );

  testWidgets(
    '#146/AK5 a folder without subfolders keeps the former question',
    (tester) async {
      final app = await pumpApp(tester);
      app.library.createFolder('A');
      await tester.pumpAndSettle();
      await openMenu(tester, 'A');
      await tester.tap(find.text(de.deleteFolder));
      await tester.pumpAndSettle();
      expect(find.text(de.deleteFolderText), findsOneWidget);
    },
  );

  testWidgets(
    '#146/AK6 folders with the same name in different parents show without a crash',
    (tester) async {
      final app = await pumpApp(tester);
      final lib = app.library;
      final a = lib.createFolder('X');
      final b = lib.createFolder('X');
      lib.createFolder('X', parentId: a.id);
      final d = lib.createFolder('X', parentId: b.id);
      await tester.pumpAndSettle();
      expect(folder('X'), findsNWidgets(4));
      lib.moveFolder(b.id, a.id);
      await tester.pump();
      lib.moveFolder(d.id, null);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(folder('X'), findsNWidgets(4));
      expect(lib.sortOrder, isA<TrackSortOrder>());
    },
  );
}
