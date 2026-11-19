// Tests der Metronom-Logik in Dart (#3, #23). AKn = n-tes Abnahmekriterium im jeweiligen Issue.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/metronome/metronome_controller.dart';
import 'package:woodshed_player/metronome/metronome_panel.dart';
import 'package:woodshed_player/ui/style.dart';
import 'package:woodshed_player/metronome/metronome_settings.dart';
import 'package:woodshed_player/metronome/practice_session.dart';
import 'package:woodshed_player/metronome/practice_shortcuts.dart';
import 'package:woodshed_player/metronome/repeat_button.dart';
import 'package:woodshed_player/metronome/tap_tempo.dart';

import 'fakes.dart';

/// Attrappe des Audio-Kerns: merkt sich Aufrufe, Steigerung wie im Kern (Einschalten im Stand -> Start-BPM).
class FakeBackend implements MetronomeBackend {
  bool isRunning = false;
  int _bpm = 120;
  int meterValue = 4;
  int subdivisionValue = 1;
  double volumeValue = 0.7;
  bool rampOn = false;
  int rampStart = 100;

  /// Letzte Steigerung: 'bars' oder 'time' mit Werten.
  String? lastRamp;

  @override
  void start() {
    isRunning = true;
    if (rampOn) _bpm = rampStart;
  }

  @override
  void stop() => isRunning = false;
  @override
  bool get running => isRunning;
  @override
  int get bpm => _bpm;
  @override
  set bpm(int v) => _bpm = MetronomeSettings.clampBpm(v);
  @override
  set meter(int v) => meterValue = v;
  @override
  set subdivision(int v) => subdivisionValue = v;
  @override
  set volume(double v) => volumeValue = v;
  @override
  void ramp({
    required bool enabled,
    required int start,
    required int target,
    required int step,
    required int everyBars,
  }) {
    if (enabled && !rampOn && !isRunning) _bpm = start;
    rampOn = enabled;
    rampStart = start;
    lastRamp = 'bars $start-$target +$step/$everyBars';
  }

  @override
  void timedRamp({
    required bool enabled,
    required int start,
    required int target,
    required int seconds,
  }) {
    if (enabled && !rampOn && !isRunning) _bpm = start;
    rampOn = enabled;
    rampStart = start;
    lastRamp = 'time $start-$target ${seconds}s';
  }
}

class FakeTitle implements TitleTransport {
  @override
  bool isPlaying = false;
  @override
  void play() => isPlaying = true;
  @override
  void pause() => isPlaying = false;
}

class MemoryStore implements SettingsStore {
  Object? saved;
  @override
  Future<Object?> load() async => saved;
  @override
  Future<void> save(Object json) async => saved = json;
}

void main() {
  group('MetronomeSettings', () {
    test('#3/AK1 Startwerte', () {
      const s = MetronomeSettings();
      expect([s.bpm, s.meter, s.subdivision, s.volume], [120, 4, 1, 0.7]);
      expect(
        [s.rampEnabled, s.rampStart, s.rampTarget, s.rampStep, s.rampEveryBars],
        [false, 100, 150, 5, 4],
      );
    });

    test('#3/AK2 Tempo wird auf 20–300 begrenzt', () {
      expect(const MetronomeSettings().copyWith(bpm: 5).bpm, 20);
      expect(const MetronomeSettings().copyWith(bpm: 999).bpm, 300);
    });

    test(
      '#3/AK13 Steigerung: Start und Ziel 20–300, Schritte, Intervall 1–20',
      () {
        const base = MetronomeSettings();
        // Start und Ziel werden wie das Tempo begrenzt.
        expect(base.copyWith(rampStart: 5).rampStart, 20);
        expect(base.copyWith(rampTarget: 999).rampTarget, 300);
        // Nur die Schritte +1/+2/+5/+10/+20 sind erlaubt; andere Werte bleiben beim bisherigen Schritt.
        expect(MetronomeSettings.rampSteps, [1, 2, 5, 10, 20]);
        for (final st in MetronomeSettings.rampSteps) {
          expect(base.copyWith(rampStep: st).rampStep, st);
        }
        expect(base.copyWith(rampStep: 3).rampStep, base.rampStep);
        // Intervall in Takten: 1–20.
        expect(base.copyWith(rampEveryBars: 0).rampEveryBars, 1);
        expect(base.copyWith(rampEveryBars: 25).rampEveryBars, 20);
        expect(base.copyWith(rampEveryBars: 7).rampEveryBars, 7);
      },
    );

    test(
      '#3/AK23 JSON hin und zurück ohne Tempo, ungültige Werte begrenzt',
      () {
        const s = MetronomeSettings(
          bpm: 87,
          meter: 6,
          subdivision: 3,
          volume: 0.4,
          rampEnabled: true,
          rampStart: 90,
          rampTarget: 60,
          rampStep: 10,
          rampEveryBars: 8,
        );
        expect(
          s.toJson().containsKey('bpm'),
          isFalse,
        ); // Tempo wird nicht gespeichert
        expect(MetronomeSettings.fromJson(s.toJson()), s.copyWith(bpm: 120));
        final odd = MetronomeSettings.fromJson({
          'bpm': 1000,
          'meter': 5,
          'subdivision': 9,
          'volume': 3,
          'rampStep': 7,
          'x': 'y',
        });
        expect(
          [odd.bpm, odd.meter, odd.subdivision, odd.volume, odd.rampStep],
          [120, 4, 4, 1.0, 5],
        );
        expect(MetronomeSettings.fromJson('kaputt'), const MetronomeSettings());
      },
    );
  });

  group('TapTempo', () {
    late DateTime now;
    late TapTempo tap;
    setUp(() {
      now = DateTime(2026);
      tap = TapTempo(clock: () => now);
    });

    test('#3/AK5 Abstand 500 ms ergibt 120 BPM, erst ab 2 Taps', () {
      expect(tap.tap(), isNull);
      now = now.add(const Duration(milliseconds: 500));
      expect(tap.tap(), 120);
    });

    test('Mittel der letzten bis zu 5 Taps', () {
      final gaps = [
        1000,
        500,
        500,
        500,
        500,
      ]; // erster Abstand fällt nach 6 Taps heraus
      tap.tap();
      int? bpm;
      for (final g in gaps) {
        now = now.add(Duration(milliseconds: g));
        bpm = tap.tap();
      }
      expect(bpm, 120);
    });

    test('nach mehr als 2 s Pause beginnt die Messung neu', () {
      tap.tap();
      now = now.add(const Duration(milliseconds: 400));
      expect(tap.tap(), 150);
      now = now.add(const Duration(milliseconds: 2100));
      expect(tap.tap(), isNull);
      now = now.add(const Duration(milliseconds: 600));
      expect(tap.tap(), 100);
    });
  });

  group('MetronomeController', () {
    late FakeBackend backend;
    late MemoryStore store;
    late MetronomeController c;
    setUp(() {
      backend = FakeBackend();
      store = MemoryStore();
      c = MetronomeController(backend, store: store);
    });

    test('#3/AK23 Einstellungen ausser Tempo bleiben, nach Neustart 120 BPM und gestoppt', () async {
      c.setBpm(90);
      c.setMeter(3);
      c.setSubdivision(2);
      c.setVolume(0.5);
      c.start();
      await Future<void>.delayed(Duration.zero);

      final backend2 = FakeBackend();
      final c2 = MetronomeController(backend2, store: store);
      await c2.restore();
      expect(
        [
          c2.settings.bpm,
          c2.settings.meter,
          c2.settings.subdivision,
          c2.settings.volume,
        ],
        [120, 3, 2, 0.5],
      );
      expect(
        [
          backend2.bpm,
          backend2.meterValue,
          backend2.subdivisionValue,
          backend2.volumeValue,
        ],
        [120, 3, 2, 0.5],
      );
      expect(c2.running, isFalse);
    });

    test('#3/AK3 Tempo ±1 und begrenzt', () {
      c.changeBpm(1);
      expect(c.settings.bpm, 121);
      c.setBpm(299);
      c.changeBpm(10);
      expect(c.settings.bpm, 300);
    });

    test(
      '#3/AK14 Steigerung einschalten im Stand setzt Start-BPM, Start ebenso',
      () {
        c.setRamp(start: 110);
        c.setRamp(enabled: true);
        expect(c.settings.bpm, 110);
        c.setBpm(130);
        c.start();
        expect(c.settings.bpm, 110);
      },
    );

    test('sync übernimmt das Tempo der Steigerung aus dem Kern', () {
      backend.bpm = 135;
      c.sync();
      expect(c.settings.bpm, 135);
    });
  });

  group('#23 Auto-Steigerung nach Zeit', () {
    late FakeBackend backend;
    late MemoryStore store;
    late MetronomeController c;
    setUp(() {
      backend = FakeBackend();
      store = MemoryStore();
      c = MetronomeController(backend, store: store);
    });

    test('#23/AK1, AK4 Standard «Takte», Dauer 4 Minuten, 1–60', () {
      const s = MetronomeSettings();
      expect(s.rampByTime, isFalse);
      expect(s.rampMinutes, 4);
      expect(s.copyWith(rampMinutes: 0).rampMinutes, 1);
      expect(s.copyWith(rampMinutes: 61).rampMinutes, 60);
      expect(s.copyWith(rampMinutes: 17).rampMinutes, 17);
    });

    test('#23/AK2 «Takte» geht wie bisher an den Kern', () {
      c.setRamp(enabled: true, start: 100, target: 150, step: 10, everyBars: 2);
      expect(backend.lastRamp, 'bars 100-150 +10/2');
    });

    test(
      '#23/AK4 «Zeit» gibt Start, Ziel und Dauer in Sekunden an den Kern',
      () {
        c.setRamp(byTime: true, start: 100, target: 110, minutes: 1);
        expect(backend.lastRamp, 'time 100-110 60s');
        c.setRamp(enabled: true);
        expect(c.settings.bpm, 100); // Einschalten im Stand: Start-BPM
        c.setRamp(minutes: 99);
        expect(backend.lastRamp, 'time 100-110 3600s');
        c.setRamp(byTime: false);
        expect(backend.lastRamp, startsWith('bars 100-110'));
      },
    );

    test('#23/AK10 Modus und Dauer bleiben nach einem Neustart erhalten', () async {
      c.setRamp(
        enabled: true,
        byTime: true,
        minutes: 12,
        start: 80,
        target: 95,
      );
      await Future<void>.delayed(Duration.zero);
      final backend2 = FakeBackend();
      final c2 = MetronomeController(backend2, store: store);
      await c2.restore();
      expect(c2.settings.rampByTime, isTrue);
      expect(c2.settings.rampMinutes, 12);
      expect(backend2.lastRamp, 'time 80-95 720s');
      expect(c2.running, isFalse);
      // Ältere gespeicherte Einstellungen ohne die neuen Felder: Standardwerte.
      final old = MetronomeSettings.fromJson({'rampEnabled': true});
      expect([old.rampByTime, old.rampMinutes], [false, 4]);
    });

    Future<void> pumpPanel(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: testLocale,
          localizationsDelegates: testDelegates,
          supportedLocales: testLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: MetronomePanel(controller: c)),
          ),
        ),
      );
    }

    bool selected(WidgetTester tester, String key) =>
        tester.widget<BorderedButton>(find.byKey(Key(key))).selected;

    testWidgets(
      '#23/AK1 Umschalter «Takte» / «Zeit» neben dem Schalter, Standard «Takte»',
      (tester) async {
        await pumpPanel(tester);
        final header = find.ancestor(
          of: find.byKey(const Key('switch:Automatische Tempo-Steigerung')),
          matching: find.byType(CardHeader),
        );
        expect(
          find.descendant(
            of: header,
            matching: find.byKey(const Key('rampMode:bars')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: header,
            matching: find.byKey(const Key('rampMode:time')),
          ),
          findsOneWidget,
        );
        expect(selected(tester, 'rampMode:bars'), isTrue);
        expect(selected(tester, 'rampMode:time'), isFalse);
        await tester.tap(find.byKey(const Key('rampMode:time')));
        await tester.pump();
        expect(c.settings.rampByTime, isTrue);
        expect(selected(tester, 'rampMode:time'), isTrue);
      },
    );

    testWidgets('#23/AK3, AK4 bei «Zeit» nur Start, Ziel und Dauer', (
      tester,
    ) async {
      await pumpPanel(tester);
      expect(find.text('Schritt'), findsOneWidget);
      expect(find.text('Alle … Takte'), findsOneWidget);
      expect(find.text('Dauer (Minuten)'), findsNothing);

      c.setRamp(enabled: true, byTime: true);
      await tester.pump();
      expect(find.text('Start-BPM'), findsOneWidget);
      expect(find.text('Ziel-BPM'), findsOneWidget);
      expect(find.text('Dauer (Minuten)'), findsOneWidget);
      expect(find.text('Schritt'), findsNothing);
      expect(find.text('Alle … Takte'), findsNothing);

      // Dauer per ± in ganzen Minuten, Standard 4.
      final row = find
          .ancestor(
            of: find.text('Dauer (Minuten)'),
            matching: find.byType(Row),
          )
          .first;
      expect(
        find.descendant(of: row, matching: find.text('4')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.add)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(c.settings.rampMinutes, 5);
    });
  });

  group('PracticeShortcuts', () {
    late FakeBackend backend;
    late MetronomeController c;
    late int playPause;

    Future<void> pump(WidgetTester tester, {bool withTextField = false}) async {
      backend = FakeBackend();
      c = MetronomeController(backend);
      playPause = 0;
      await tester.pumpWidget(
        MaterialApp(
          locale: testLocale,
          localizationsDelegates: testDelegates,
          supportedLocales: testLocales,
          home: PracticeShortcuts(
            metronome: c,
            onPlayPause: () => playPause++,
            child: Scaffold(
              body: withTextField
                  ? const TextField(key: Key('feld'))
                  : const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('#3/AK4 M, T, Pfeile (mit Shift ±10) und Leertaste', (
      tester,
    ) async {
      await pump(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      expect(backend.isRunning, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      expect(backend.isRunning, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      expect(c.settings.bpm, 121);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(c.settings.bpm, 111);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(playPause, 1);
      expect(backend.isRunning, isFalse); // Leertaste ist nicht das Metronom

      await tester.sendKeyEvent(
        LogicalKeyboardKey.keyT,
      ); // ein Tap ändert noch nichts
      expect(c.settings.bpm, 111);
    });

    testWidgets('#3/AK4 beim Tippen in Textfeldern sind die Tasten aus', (
      tester,
    ) async {
      await pump(tester, withTextField: true);
      await tester.tap(find.byKey(const Key('feld')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(backend.isRunning, isFalse);
      expect(playPause, 0);
    });
  });

  testWidgets('#3/AK3 gedrückt halten wiederholt den Schritt nach 0,4 s', (
    tester,
  ) async {
    var steps = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: testLocale,
        localizationsDelegates: testDelegates,
        supportedLocales: testLocales,
        home: Scaffold(
          body: Center(
            child: RepeatButton(icon: Icons.add, onStep: () => steps++),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RepeatButton)),
    );
    expect(steps, 1); // sofort ein Schritt
    await tester.pump(const Duration(milliseconds: 350));
    expect(steps, 1); // vor 0,4 s keine Wiederholung
    await tester.pump(const Duration(milliseconds: 100)); // 0,45 s
    await tester.pump(const Duration(milliseconds: 400)); // laufend weiter
    expect(steps, greaterThan(3));
    await gesture.up();
    final after = steps;
    await tester.pump(const Duration(seconds: 1));
    expect(steps, after); // nach dem Loslassen Schluss
  });

  group('#3/AK20 Titel und Metronom nie gleichzeitig', () {
    late FakeBackend backend;
    late FakeTitle title;
    late MetronomeController c;
    late PracticeSession session;
    setUp(() {
      backend = FakeBackend();
      title = FakeTitle();
      c = MetronomeController(backend);
      session = PracticeSession(title, c);
    });

    test('Metronom starten pausiert den Titel', () {
      session.playTitle();
      c.start();
      expect(title.isPlaying, isFalse);
      expect(c.running, isTrue);
    });

    test('Titel starten stoppt das Metronom', () {
      c.toggle();
      session.toggleTitle();
      expect(c.running, isFalse);
      expect(title.isPlaying, isTrue);
    });

    test(
      'Metronom läuft auch ohne Titel, Pause des Titels lässt es stehen',
      () {
        c.start();
        expect(c.running, isTrue);
        session.playTitle();
        session.toggleTitle(); // Titel pausieren
        expect([title.isPlaying, c.running], [false, false]);
      },
    );
  });
}
