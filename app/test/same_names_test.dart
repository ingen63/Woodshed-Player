// #143: tracks, folders and playlists may share a name; the library list shows all of them. Equal names
// only break the list once rows with them move, so the tests rename one by one and rebuild in between.
// German UI (testLocale), widgets found by key and text.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fakes.dart';
import 'home_page_test.dart' show pumpApp;
import 'playlist_view_test.dart' show idOf;

const five = ['a', 'b', 'c', 'd', 'e'];

/// Renames the tracks one by one (title → new title) and rebuilds after each, so rows move past each other.
Future<void> renameTracks(
  WidgetTester tester,
  TestApp app,
  List<(String, String)> steps,
) async {
  for (final (from, to) in steps) {
    final id = app.library.tracks.firstWhere((t) => t.title == from).id;
    app.library.editMetadata(id, title: to);
    await tester.pump();
  }
}

/// Leaves a, c and e titled «X» on the way; the last two steps move rows past the equal ones.
const shuffle = [
  ('a', 'X'),
  ('c', 'X'),
  ('e', 'X'),
  ('b', 'Y'),
  ('d', 'X'),
  ('X', 'Z'),
  ('X', 'A'),
];

/// Every track shows exactly as often as its title occurs.
void expectAllRows(TestApp app) {
  final counts = <String, int>{};
  for (final t in app.library.tracks) {
    counts[t.title] = (counts[t.title] ?? 0) + 1;
  }
  for (final MapEntry(:key, :value) in counts.entries) {
    expect(find.byKey(Key('track:$key')), findsNWidgets(value), reason: key);
  }
}

void main() {
  testWidgets('#143/AK1 tracks with the same title without folder all show', (
    tester,
  ) async {
    final app = await pumpApp(tester, titles: five);
    await renameTracks(tester, app, shuffle);

    expect(tester.takeException(), isNull);
    expectAllRows(app);
  });

  testWidgets('#143/AK1 tracks with the same title in one folder all show', (
    tester,
  ) async {
    final app = await pumpApp(tester, titles: five);
    final f = app.library.createFolder('Ordner');
    app.library.placeTracks({for (final t in five) idOf(app, t)}, f.id);
    await tester.pump();
    await renameTracks(tester, app, shuffle);

    expect(tester.takeException(), isNull);
    expectAllRows(app);
  });

  testWidgets('#143/AK2 tracks with the same title all show in the search', (
    tester,
  ) async {
    final app = await pumpApp(tester, titles: [for (final t in five) 'm$t']);
    await tester.enterText(find.byKey(const Key('librarySearch')), 'm');
    await tester.pump();
    await renameTracks(tester, app, [
      for (final (from, to) in shuffle) ('m$from', 'm$to'),
    ]);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('searchResults')), findsOneWidget);
    expectAllRows(app);
  });

  testWidgets('#143/AK3 folders with the same name all show their tracks', (
    tester,
  ) async {
    final app = await pumpApp(tester, titles: five);
    final folders = {for (final t in five) t: app.library.createFolder(t)};
    for (final t in five) {
      app.library.placeTracks({idOf(app, t)}, folders[t]!.id);
    }
    await tester.pump();
    for (final t in ['a', 'c', 'e', 'b', 'd']) {
      app.library.renameFolder(folders[t]!.id, t == 'b' ? 'Y' : 'X');
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('folder:X')), findsNWidgets(4));
    expect(find.byKey(const Key('folder:Y')), findsOneWidget);
    for (final t in five) {
      expect(find.byKey(Key('track:$t')), findsOneWidget);
    }
  });

  testWidgets(
    '#143/AK4 open playlists with the same name all show their entries',
    (tester) async {
      final app = await pumpApp(tester, titles: five, libraryOpen: false);
      final lists = {for (final t in five) t: app.library.createPlaylist(t)};
      for (final t in five) {
        app.library.addToPlaylist(lists[t]!.id, [idOf(app, t)]);
      }
      await tester.pump();
      for (final t in five) {
        await tester.tap(find.byKey(Key('playlist:$t')));
        await tester.pumpAndSettle();
      }
      for (final t in ['a', 'c', 'e', 'b', 'd']) {
        app.library.renamePlaylist(lists[t]!.id, t == 'b' ? 'Y' : 'X');
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('playlist:X')), findsNWidgets(4));
      expect(find.byKey(const Key('playlist:Y')), findsOneWidget);
      expect(find.byKey(const Key('entry:X:0')), findsNWidgets(4));
      for (final t in five) {
        expect(find.text(t), findsOneWidget);
      }
    },
  );
}
