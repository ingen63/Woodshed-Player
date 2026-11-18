// #29: Steigerung der Titel-Geschwindigkeit nach Loop-Durchgängen. AKn = n-tes Abnahmekriterium.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/library/playback_settings.dart';
import 'package:woodshed_player/metronome/loop_ramp.dart';
import 'package:woodshed_player/ui/player_view.dart';
import 'package:woodshed_player/ui/style.dart';

PlaybackSettings at(
  int percent, {
  int target = 100,
  int step = 5,
  int passes = 10,
}) => PlaybackSettings(
  speedEnabled: true,
  speed: percent / 100,
  rampEnabled: true,
  rampStart: 60,
  rampTarget: target,
  rampStep: step,
  rampPasses: passes,
);

void main() {
  group('#29/AK1 Einstellungen', () {
    test('Standard 60 %, 100 %, 5 %, 10 Durchgänge, aus', () {
      const s = PlaybackSettings();
      expect(s.rampEnabled, isFalse);
      expect(s.rampStart, 60);
      expect(s.rampTarget, 100);
      expect(s.rampStep, 5);
      expect(s.rampPasses, 10);
    });

    test('Werte werden begrenzt', () {
      final s = const PlaybackSettings().copyWith(
        rampStart: 1,
        rampTarget: 500,
        rampStep: 7,
        rampPasses: 0,
      );
      expect(s.rampStart, PlaybackSettings.minRampPercent);
      expect(s.rampTarget, PlaybackSettings.maxRampPercent);
      expect(s.rampStep, 5); // ungültige Schrittweite: bleibt
      expect(s.rampPasses, 1);
    });
  });

  group('#29/AK3 Stufenwechsel', () {
    test('nach 10 Durchgängen eine Stufe höher, Zähler wieder 0', () {
      final r = LoopRamp();
      expect(r.addPasses(9, at(60)), isNull);
      expect(r.passes, 9);
      expect(r.addPasses(1, at(60)), 0.65);
      expect(r.passes, 0);
    });

    test('mehrere Durchgänge auf einmal: Rest zählt auf der neuen Stufe', () {
      final r = LoopRamp();
      expect(r.addPasses(13, at(60)), 0.65);
      expect(r.passes, 3);
    });

    test('Schrittweite und Durchgänge pro Stufe gelten', () {
      final r = LoopRamp();
      expect(r.addPasses(2, at(70, step: 10, passes: 3)), isNull);
      expect(r.addPasses(1, at(70, step: 10, passes: 3)), 0.8);
    });
  });

  group('#29/AK4 Zielstufe', () {
    test('Schritt über das Ziel hinaus endet am Ziel', () {
      final r = LoopRamp();
      expect(r.addPasses(10, at(98)), 1.0);
    });

    test('am Ziel bleibt die Geschwindigkeit, der Zähler läuft weiter', () {
      final r = LoopRamp();
      expect(r.addPasses(25, at(100)), isNull);
      expect(r.passes, 25);
      expect(LoopRamp.atTarget(at(100)), isTrue);
    });

    test('ganzer Durchlauf 60 → 100 % in 8 Stufen', () {
      final r = LoopRamp();
      var s = at(60);
      final seen = <int>[];
      for (var i = 0; i < 100; i++) {
        final next = r.addPasses(1, s);
        if (next != null) {
          s = s.copyWith(speed: next);
          seen.add(s.speedPercent);
        }
      }
      expect(seen, [65, 70, 75, 80, 85, 90, 95, 100]);
      expect(r.passes, 100 - 80);
    });
  });

  test('#29/AK5 reset setzt den Zähler auf 0', () {
    final r = LoopRamp()..addPasses(7, at(60));
    r.reset();
    expect(r.passes, 0);
  });

  group('#29/AK8 Anzeige', () {
    test('«75 % · 7 von 10»', () {
      final r = LoopRamp()..addPasses(7, at(75));
      expect(r.label(at(75)), '75 % · 7 von 10');
    });

    test('an der Zielstufe mit Zahl der Durchgänge', () {
      final r = LoopRamp()..addPasses(14, at(100));
      expect(r.label(at(100)), '100 % · Ziel erreicht · 14 Durchgänge');
    });

    testWidgets('Karte zeigt Stufe und Durchgänge, Knöpfe ändern die Werte', (
      tester,
    ) async {
      final calls = <String>[];
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: woodshedTheme(Brightness.light),
          home: Scaffold(
            body: PlayerView(
              state: PlayerViewState(
                title: 'Testton',
                duration: 60,
                speedOn: true,
                speed: 0.75,
                loopOn: true,
                loopStart: 5,
                loopEnd: 15,
                ramp: at(75),
                rampLabel: '75 % · 7 von 10',
              ),
              actions: PlayerViewActions(
                open: () {},
                playPause: () {},
                seek: (_) {},
                volume: (_) {},
                speedOn: (_) {},
                speed: (_) {},
                loopOn: (_) {},
                loopStart: (_) {},
                loopEnd: (_) {},
                ramp: ({enabled, start, target, step, passes}) =>
                    calls.add([enabled, start, target, step, passes].join(',')),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('card:ramp')), findsOneWidget);
      expect(find.text('75 % · 7 von 10'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('rampSettings')),
      ); // #30: eingeklappt
      await tester.pump();
      expect(find.text('60 %'), findsOneWidget);
      expect(find.text('100 %'), findsOneWidget);
      expect(find.text('+5 %'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ramp:start:+')));
      await tester.tap(find.byKey(const Key('ramp:passes:-')));
      await tester.pump(const Duration(seconds: 1));
      expect(calls, ['null,65,null,null,null', 'null,null,null,null,9']);
    });
  });

  group('#29/AK7 Speichern', () {
    test('JSON hin und zurück', () {
      final s = const PlaybackSettings().copyWith(
        rampEnabled: true,
        rampStart: 50,
        rampTarget: 90,
        rampStep: 10,
        rampPasses: 4,
      );
      expect(PlaybackSettings.fromJson(s.toJson()), s);
    });

    test('ohne Steigerung bleibt das JSON wie bisher', () {
      expect(const PlaybackSettings().toJson().keys, [
        'loopEnabled',
        'loopEnd',
        'loopStart',
        'speed',
        'speedEnabled',
      ]);
      expect(
        PlaybackSettings.fromJson({'speed': 0.8}),
        const PlaybackSettings(speed: 0.8),
      );
    });
  });
}
