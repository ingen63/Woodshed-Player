// #141/AK4, AK12, AK13, AK16: «Export as MP3 …» in the context menu of one or several tracks, the
// progress dialog with «Cancel» and the result. Fake encoder and folder picker; the library and the
// target folder are temporary. German UI (testLocale), widgets found by key.
import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wp_core/wp_types.dart';

import 'home_page_test.dart' as home show pumpApp;
import 'selection_view_test.dart' show clickWith, row;

void main() {
  late Directory out;
  late List<String> encoded;
  Completer<void>? gate;
  var code = WpCode.ok;

  Future<int> encode(
    String input,
    String output, {
    Future<void>? cancel,
    void Function(double fraction)? onProgress,
  }) async {
    encoded.add(input);
    onProgress?.call(0.5);
    if (gate != null) {
      await Future.any([gate!.future, ?cancel]);
      if (!gate!.isCompleted) return WpCode.cancelled;
    }
    if (code == WpCode.ok) {
      File(output).writeAsBytesSync([0xff, 0xfb, 0x90, 0, 1, 2, 3]);
    }
    return code;
  }

  setUp(() {
    out = Directory.systemTemp.createTempSync('wp_export_out');
    encoded = [];
    gate = null;
    code = WpCode.ok;
  });
  tearDown(() => out.deleteSync(recursive: true));

  List<String> written() =>
      [for (final f in out.listSync()) f.uri.pathSegments.last]..sort();

  /// Pumps frames until [done] holds. The export's file work runs in real time, outside the fake
  /// clock, so real time and frames alternate; fails only after [hangGuard] (#78).
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() done,
    String what, {
    Duration hangGuard = const Duration(seconds: 60),
  }) async {
    final watch = Stopwatch()..start();
    while (!done() && watch.elapsed < hangGuard) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(done(), isTrue, reason: 'hang: «$what» not reached');
  }

  /// Waits until the export started by a tap shows its result.
  Future<void> settle(WidgetTester tester) async {
    await pumpUntil(
      tester,
      () => find.byKey(const Key('exportResult')).evaluate().isNotEmpty,
      'the result of the export',
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    '#141: without the encoder (iPhone, iPad, browser) there is no export',
    (tester) async {
      await home.pumpApp(tester);
      await tester.tap(row('Bossa'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exportTracks')), findsNothing);
    },
  );

  testWidgets('#141/AK4: one track: folder, then the file and the result', (
    tester,
  ) async {
    final app = await home.pumpApp(tester, mp3: encode);
    app.files.nextFolder = out.path;
    await tester.tap(row('Bossa'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exportTracks')));
    await settle(tester);
    expect(app.files.folderPrompts, ['Hierhin exportieren']);
    expect(written(), ['Bossa.mp3']);
    expect(encoded, isEmpty); // an MP3 is copied
    expect(find.byKey(const Key('exportResult')), findsOneWidget);
    expect(find.text('1 Titel exportiert.'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exportResult')), findsNothing);
  });

  testWidgets('#141/AK4: several selected tracks are exported together', (
    tester,
  ) async {
    final app = await home.pumpApp(tester, mp3: encode);
    app.files.nextFolder = out.path;
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Bossa');
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Zebra');
    await tester.tap(row('Bossa'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exportTracks')));
    await settle(tester);
    expect(written(), ['Bossa.mp3', 'Zebra.mp3']);
    expect(find.text('2 Titel exportiert.'), findsOneWidget);
  });

  testWidgets('#141: cancelling the folder dialog exports nothing', (
    tester,
  ) async {
    final app = await home.pumpApp(tester, mp3: encode);
    app.files.nextFolder = null;
    await tester.tap(row('Bossa'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exportTracks')));
    await tester.pumpAndSettle();
    expect(app.files.folderPrompts, hasLength(1));
    expect(written(), isEmpty);
    expect(find.byKey(const Key('exportProgress')), findsNothing);
    expect(find.byKey(const Key('exportResult')), findsNothing);
  });

  testWidgets('#141/AK12: progress while encoding, «Cancel» stops', (
    tester,
  ) async {
    final app = await home.pumpApp(
      tester,
      mp3: encode,
      titles: const [],
      files: {'Take.wav': Uint8List.fromList('RIFF wav'.codeUnits)},
    );
    app.files.nextFolder = out.path;
    gate = Completer();
    await tester.tap(row('Take'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exportTracks')));
    await pumpUntil(
      tester,
      () =>
          encoded.isNotEmpty &&
          find.byKey(const Key('exportProgress')).evaluate().isNotEmpty,
      'the progress dialog while encoding',
    );
    expect(find.byKey(const Key('exportProgress')), findsOneWidget);
    expect(find.text('1 von 1: Take'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.5);
    await tester.tap(find.byKey(const Key('exportCancel')));
    await settle(tester);
    expect(find.byKey(const Key('exportProgress')), findsNothing);
    expect(
      find.text('Export abgebrochen. Kein Titel exportiert.'),
      findsOneWidget,
    );
    expect(written(), isEmpty);
  });

  testWidgets('#141/AK13, AK16: a failing track is named with the reason', (
    tester,
  ) async {
    final app = await home.pumpApp(
      tester,
      mp3: encode,
      titles: const ['Bossa'],
      files: {'Take.wav': Uint8List.fromList('RIFF wav'.codeUnits)},
    );
    app.files.nextFolder = out.path;
    code = WpCode.encoderUnavailable;
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Bossa');
    await clickWith(tester, LogicalKeyboardKey.metaLeft, 'Take');
    await tester.tap(row('Take'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exportTracks')));
    await settle(tester);
    expect(written(), ['Bossa.mp3']);
    expect(find.text('1 Titel exportiert.'), findsOneWidget);
    expect(
      find.text('«Take»: MP3 ist nicht verfügbar, der Encoder fehlt.'),
      findsOneWidget,
    );
  });
}
