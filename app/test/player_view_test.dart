// Übe-Bildschirm (#19, seit #30 im Design «Studio»). AKn = n-tes Abnahmekriterium im jeweiligen Issue.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/ui/player_view.dart';
import 'package:woodshed_player/ui/style.dart';

import 'fakes.dart';

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
        locale: testLocale,
        localizationsDelegates: testDelegates,
        supportedLocales: testLocales,
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
    '#19/AK4, #30/AK4 Reihenfolge Desktop: Zeitleiste, Loop, Module, Aufnahme am Ende',
    (tester) async {
      await pump(
        tester,
        loaded,
        width: 1200,
        extra: [
          const WsCard(
            key: Key('card:recording'),
            children: [Text('Aufnahme')],
          ),
        ],
      );
      final order = [
        'card:timeline',
        'card:loop',
        'card:speed',
        'transportBar',
        'card:recording',
      ];
      for (var i = 1; i < order.length; i++) {
        expect(top(tester, order[i - 1]), lessThan(top(tester, order[i])));
      }
    },
  );

  testWidgets('#19/AK5 Titel, darunter Künstler und Dauer mm:ss', (
    tester,
  ) async {
    await pump(
      tester,
      const PlayerViewState(title: 'Testton', artist: 'Band', duration: 125),
    );
    final title = tester.widget<Text>(find.byKey(const Key('trackTitle')));
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(find.text('Band · 02:05'), findsOneWidget);
    expect(find.byKey(const Key('volume')), findsOneWidget);
  });

  testWidgets('#19/AK6 Wiedergabe: Play/Pause und Zeit mm:ss.d im Kopf', (
    tester,
  ) async {
    await pump(tester, loaded, width: 1200);
    await tester.tap(find.byKey(const Key('playPause')));
    expect(calls, ['playPause']);
    expect(find.text('00:30.0 / 02:05.0', findRichText: true), findsOneWidget);
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
          '0,5',
          '0,75',
          '0,8',
          '1,0',
        ].every((t) => find.text(t).evaluate().isNotEmpty),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('preset:0.5')));
      expect(calls, ['speed 0.5']);
    },
  );

  testWidgets('#19/AK9 Loop: Zeitfelder, S hier, Ganzer Titel', (tester) async {
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
    expect(find.text('00:10.0'), findsOneWidget);
    expect(find.text('00:20.0'), findsOneWidget);
    await tester.tap(find.text('S hier'));
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
        locale: testLocale,
        localizationsDelegates: testDelegates,
        supportedLocales: testLocales,
        theme: woodshedTheme(Brightness.dark),
        home: Scaffold(
          body: PlayerView(state: loaded, actions: actions()),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('card:speed')), findsOneWidget);
  });
}
