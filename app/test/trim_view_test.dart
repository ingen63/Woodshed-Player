// #116: the trim view (context menu, waveform with handles, mm:ss.d fields, listening, question before
// trimming). German texts (testLocale), temporary folders, a fake trimmer; never the real library.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/ui/messages.dart';
import 'package:wp_core/wp_types.dart';

import 'fakes.dart';
import 'home_page_test.dart' show pumpApp;

/// Calls of the fake trimmer.
final cuts = <(double, double)>[];

Future<WpTrimmed> fakeTrim(Uint8List b, double start, double end) async {
  cuts.add((start, end));
  return WpTrimmed(
    Uint8List.fromList([...b, ...utf8.encode('|$start-$end')]),
    start,
    end,
  );
}

/// Opens the trim view of [title] through its context menu and finishes loading it (30 s).
Future<void> openTrim(WidgetTester tester, TestApp app, String title) async {
  app.core.hasWaveform = true;
  await tester.tap(find.byKey(Key('menu:$title')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('trimTrack')));
  await tester.pump();
  app.finishLoads(30);
  await tester.pumpAndSettle();
}

String field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  setUp(cuts.clear);

  testWidgets(
    '#116/AK1 the context menu opens the view with waveform, handles and mm:ss.d fields',
    (tester) async {
      final app = await pumpApp(tester, trimmer: fakeTrim);
      await openTrim(tester, app, 'Zebra');
      expect(find.byKey(const Key('trimView')), findsOneWidget);
      expect(find.text(de.trimTitle('Zebra')), findsOneWidget);
      expect(find.byKey(const Key('trimWaveform')), findsOneWidget);
      expect(find.byKey(const Key('trimStartHandle')), findsOneWidget);
      expect(find.byKey(const Key('trimEndHandle')), findsOneWidget);
      expect(field(tester, 'trimStartField'), '00:00.0');
      expect(field(tester, 'trimEndField'), '00:30.0');
      expect(
        app.player.trackId,
        app.library.tracks.firstWhere((t) => t.title == 'Zebra').id,
      );

      // typed as mm:ss.d
      await tester.enterText(
        find.byKey(const Key('trimStartField')),
        '00:05.5',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.enterText(find.byKey(const Key('trimEndField')), '0:20');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(field(tester, 'trimStartField'), '00:05.5');
      expect(field(tester, 'trimEndField'), '00:20.0');
      expect(find.text(de.trimRemaining('00:14.5')), findsOneWidget);

      // dragged: from the start handle (5.5 s of 30 s) a quarter of the width to the right
      final wave = tester.getRect(find.byKey(const Key('trimWaveform')));
      final from = Offset(wave.left + wave.width * 5.5 / 30, wave.center.dy);
      await tester.dragFrom(from, Offset(wave.width / 4, 0));
      await tester.pump();
      final start = parse(field(tester, 'trimStartField'));
      expect(start, closeTo(5.5 + 7.5, 0.3), reason: 'a quarter of 30 s later');
      expect(field(tester, 'trimEndField'), '00:20.0', reason: 'the end stays');
    },
  );

  testWidgets('#116/AK7 at least 1 s remains, the end lies after the start', (
    tester,
  ) async {
    final app = await pumpApp(tester, trimmer: fakeTrim);
    await openTrim(tester, app, 'Zebra');
    await tester.enterText(find.byKey(const Key('trimEndField')), '00:10.0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    // a start 0.5 s before the end is refused, the field is marked
    await tester.enterText(find.byKey(const Key('trimStartField')), '00:09.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text(de.trimRangeInvalid), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('trimApply'))).onPressed,
      isNull,
    );
    // an end before the start too; nonsense as well
    await tester.enterText(find.byKey(const Key('trimStartField')), '00:04.0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.enterText(find.byKey(const Key('trimEndField')), '00:03.0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text(de.trimRangeInvalid), findsOneWidget);
    await tester.enterText(find.byKey(const Key('trimEndField')), 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text(de.trimRangeInvalid), findsOneWidget);
    // dragging keeps 1 s between the handles: the end dragged onto the start stops 1 s after it
    await tester.enterText(find.byKey(const Key('trimEndField')), '00:20.0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    final wave = tester.getRect(find.byKey(const Key('trimWaveform')));
    await tester.dragFrom(
      Offset(wave.left + wave.width * 20 / 30, wave.center.dy),
      Offset(-wave.width * 0.9, 0),
    );
    await tester.pump();
    expect(field(tester, 'trimEndField'), '00:05.0');
    expect(find.text(de.trimRemaining('00:01.0')), findsOneWidget);
  });

  testWidgets('#116/AK2 the part between the bounds can be heard', (
    tester,
  ) async {
    final app = await pumpApp(tester, trimmer: fakeTrim);
    await openTrim(tester, app, 'Zebra');
    await tester.enterText(find.byKey(const Key('trimStartField')), '00:02.0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.enterText(find.byKey(const Key('trimEndField')), '00:12.0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.byKey(const Key('trimPreview')));
    await tester.pump();
    expect(app.player.preview, (2.0, 12.0));
    expect(app.core.playing, isTrue);
    expect(app.core.pos, 2.0);
    expect(find.text(de.trimStopPreview), findsOneWidget);
    await tester.tap(find.byKey(const Key('trimPreview')));
    await tester.pump();
    expect(app.player.preview, isNull);
    expect(app.core.playing, isFalse);
    // closing the view ends listening too
    await tester.tap(find.byKey(const Key('trimPreview')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('trimClose')));
    await tester.pumpAndSettle();
    expect(app.player.preview, isNull);
    expect(cuts, isEmpty);
  });

  testWidgets(
    '#116/AK3 a question before trimming; Cancel leaves everything unchanged',
    (tester) async {
      final app = await pumpApp(tester, trimmer: fakeTrim);
      final before = jsonEncode(app.library.state.toJson());
      await openTrim(tester, app, 'Zebra');
      await tester.enterText(
        find.byKey(const Key('trimStartField')),
        '00:02.0',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.tap(find.byKey(const Key('trimApply')));
      await tester.pumpAndSettle();
      expect(find.text(de.trimConfirmTitle), findsOneWidget);
      expect(
        find.text(de.trimConfirmText('Zebra', '00:02.0', '00:30.0')),
        findsOneWidget,
      );
      expect(de.trimConfirmText('x', 'a', 'b'), contains('nicht rückgängig'));
      await tester.tap(find.byKey(const Key('trimCancel')));
      await tester.pumpAndSettle();
      expect(cuts, isEmpty);
      expect(find.byKey(const Key('trimView')), findsOneWidget);
      expect(jsonEncode(app.library.state.toJson()), before);

      // confirmed: the file is cut, the view closes, the track (with its title) is loaded again
      final old = app.player.trackId;
      await tester.tap(find.byKey(const Key('trimApply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('trimConfirm')));
      await tester.pump();
      // the cut reads and writes real files; then the trimmed track starts loading
      await waitUntil(
        tester,
        () => app.controller.trimming == null,
        'trimmed and loading again',
      );
      app.finishLoads(28);
      await tester.pumpAndSettle();
      expect(cuts, [(2.0, 30.0)]);
      expect(find.byKey(const Key('trimView')), findsNothing);
      expect(app.player.trackId, isNot(old));
      expect(app.library.track(app.player.trackId!)!.title, 'Zebra');
      expect(app.library.track(old!), isNull);
    },
  );

  testWidgets('#116 M4A: the menu item is greyed out with a hint', (
    tester,
  ) async {
    await pumpApp(
      tester,
      titles: const [],
      files: {'Song.m4a': Uint8List.fromList(utf8.encode('aac'))},
      trimmer: fakeTrim,
    );
    await tester.tap(find.byKey(const Key('menu:Song')));
    await tester.pumpAndSettle();
    final item = tester.widget<MenuItemButton>(
      find.byKey(const Key('trimTrack')),
    );
    expect(item.onPressed, isNull);
    expect(find.text(de.trimUnavailable), findsOneWidget);
  });

  test('#116/AK9 every reason has its own text in English and German', () {
    final en = lookupAppLocalizations(const Locale('en'));
    for (final l in [en, de]) {
      final texts = {
        for (final p in TrimProblem.values)
          libraryMessageText(l, TrimFailed('Song', p)),
      };
      expect(texts.length, TrimProblem.values.length);
      expect(texts.every((t) => t.contains('Song')), isTrue);
    }
    expect(
      libraryMessageText(en, const TrimFailed('Song', TrimProblem.noSpace)),
      contains('storage space'),
    );
  });
}

double parse(String s) {
  final p = s.split(':');
  return int.parse(p[0]) * 60 + double.parse(p[1]);
}
