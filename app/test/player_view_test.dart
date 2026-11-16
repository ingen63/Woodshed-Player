// Oberfläche des Player-Reiters (#19). AKn = n-tes Abnahmekriterium im Issue #19.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/ui/player_view.dart';
import 'package:woodshed_player/ui/style.dart';

void main() {
  late List<String> calls;

  PlayerViewActions actions() => PlayerViewActions(
    open: () => calls.add('open'),
    playPause: () => calls.add('playPause'),
    seek: (v) => calls.add('seek $v'),
    volume: (v) => calls.add('volume'),
    speedOn: (v) => calls.add('speedOn $v'),
    speed: (v) => calls.add('speed $v'),
    loopOn: (v) => calls.add('loopOn $v'),
    loopStart: (v) => calls.add('loopStart $v'),
    loopEnd: (v) => calls.add('loopEnd $v'),
  );

  Future<void> pump(
    WidgetTester tester,
    PlayerViewState state, {
    double width = 900,
    List<Widget> extra = const [],
  }) async {
    calls = [];
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: woodshedTheme(Brightness.light),
        home: Scaffold(
          body: PlayerView(state: state, actions: actions(), extraCards: extra),
        ),
      ),
    );
  }

  const loaded = PlayerViewState(
    title: 'Testton',
    duration: 125,
    position: 30,
    loopStart: 10,
    loopEnd: 20,
  );

  double top(WidgetTester t, String key) =>
      t.getTopLeft(find.byKey(Key(key))).dy;

  testWidgets(
    '#19/AK4 Reihenfolge der Karten: Titel, Geschwindigkeit, Loop, Aufnahme',
    (tester) async {
      await pump(
        tester,
        loaded,
        extra: [
          const WsCard(
            key: Key('card:recording'),
            children: [Text('Aufnahme')],
          ),
        ],
      );
      final order = [
        'card:nowPlaying',
        'card:speed',
        'card:loop',
        'card:recording',
      ];
      for (var i = 1; i < order.length; i++) {
        expect(top(tester, order[i - 1]), lessThan(top(tester, order[i])));
      }
      expect(find.byKey(const Key('accentBackground')), findsOneWidget);
    },
  );

  testWidgets('#19/AK3 Karten höchstens 760 breit und zentriert', (
    tester,
  ) async {
    await pump(tester, loaded, width: 1200);
    final rect = tester.getRect(find.byKey(const Key('card:speed')));
    expect(rect.width, 760);
    expect(rect.center.dx, closeTo(600, 0.5));
  });

  testWidgets('#19/AK5 Titel fett, Dauer als «Dauer: mm:ss»', (tester) async {
    await pump(tester, loaded);
    final title = tester.widget<Text>(find.byKey(const Key('trackTitle')));
    expect(title.style?.fontWeight, FontWeight.bold);
    expect(find.text('Dauer: 02:05', findRichText: true), findsOneWidget);
    expect(find.byKey(const Key('volume')), findsOneWidget);
  });

  testWidgets('#19/AK6 Wiedergabeleiste: einzeilig breit, zweizeilig schmal', (
    tester,
  ) async {
    await pump(tester, loaded, width: 900);
    final play = tester.getCenter(find.byKey(const Key('playPause'))).dy;
    final bar = tester.getCenter(find.byType(ProgressScrubber)).dy;
    expect((play - bar).abs(), lessThan(4));
    await tester.tap(find.byKey(const Key('playPause')));
    expect(calls, ['playPause']);

    await pump(tester, loaded, width: 390);
    final play2 = tester.getCenter(find.byKey(const Key('playPause'))).dy;
    final bar2 = tester.getCenter(find.byType(ProgressScrubber)).dy;
    expect(play2, greaterThan(bar2 + 10)); // Knöpfe unter der Zeitleiste
    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('02:05'), findsOneWidget);
  });

  testWidgets('#19/AK7 Loop-Bereich und Marker nur bei aktivem Loop', (
    tester,
  ) async {
    await pump(tester, loaded);
    expect(find.byKey(const Key('loopRange')), findsNothing);
    await pump(
      tester,
      const PlayerViewState(
        title: 'Testton',
        duration: 125,
        loopOn: true,
        loopStart: 10,
        loopEnd: 20,
      ),
    );
    expect(find.byKey(const Key('loopRange')), findsOneWidget);
    expect(find.byKey(const Key('loopStartMarker')), findsOneWidget);
    expect(find.byKey(const Key('loopEndMarker')), findsOneWidget);
  });

  testWidgets(
    '#19/AK8 Geschwindigkeit: Wert, Vorwahl, ausgeschaltet abgeblendet',
    (tester) async {
      await pump(tester, loaded);
      final dim = tester.widget<Opacity>(
        find.descendant(
          of: find.byKey(const Key('dim:speed')),
          matching: find.byType(Opacity),
        ),
      );
      expect(dim.opacity, 0.45);
      await tester.tap(
        find.byKey(const Key('preset:0.8')),
        warnIfMissed: false,
      );
      expect(calls, isEmpty); // nicht bedienbar

      await pump(
        tester,
        const PlayerViewState(
          title: 'Testton',
          duration: 125,
          speedOn: true,
          speed: 0.8,
        ),
      );
      expect(find.text('0,80×'), findsWidgets);
      expect(
        [
          '0,50×',
          '0,70×',
          '0,90×',
          '1,00×',
          '1,10×',
        ].every((t) => find.text(t).evaluate().isNotEmpty),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('preset:0.5')));
      expect(calls, ['speed 0.5']);
    },
  );

  testWidgets('#19/AK9 Loop: Zeitfelder, Aktuelle Position, Ganzer Titel', (
    tester,
  ) async {
    await pump(
      tester,
      const PlayerViewState(
        title: 'Testton',
        duration: 125,
        position: 30,
        loopOn: true,
        loopStart: 10,
        loopEnd: 20,
      ),
    );
    expect(find.text('00:10'), findsOneWidget);
    expect(find.text('00:20'), findsOneWidget);
    await tester.tap(find.text('Aktuelle Position').first);
    await tester.tap(find.text('Ganzer Titel'));
    expect(calls, ['loopStart 30.0', 'loopStart 0.0', 'loopEnd 125.0']);

    calls.clear();
    await tester.enterText(find.byKey(const Key('time:Ende')), '01:23.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(calls, ['loopEnd 83.5']);
  });

  testWidgets('#19/AK10 ohne Titel: Hinweis und Knopf zum Öffnen', (
    tester,
  ) async {
    await pump(tester, const PlayerViewState());
    expect(find.text('Kein Titel ausgewählt'), findsOneWidget);
    expect(find.byKey(const Key('card:speed')), findsNothing);
    await tester.tap(find.byKey(const Key('openFile')));
    expect(calls, ['open']);
  });

  testWidgets('#19/AK12 Dunkelmodus baut ohne Fehler', (tester) async {
    calls = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: woodshedTheme(Brightness.dark),
        home: Scaffold(
          body: PlayerView(state: loaded, actions: actions()),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('card:nowPlaying')), findsOneWidget);
  });
}
