// #15: PlayerService ohne Audiogerät, mit Attrappen für Kern und Timer.
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/playback_settings.dart';
import 'package:woodshed_player/player/audio_core.dart';
import 'package:woodshed_player/player/player_service.dart';
import 'package:wp_core/wp_core.dart';

import 'fakes.dart';

import 'package:woodshed_player/ui/messages.dart';

import 'dart:ui' show Locale;

class Harness {
  Harness() {
    service = PlayerService(
      core,
      timerFactory: (d, f) {
        final t = FakeTimer(d, f);
        timers.add(t);
        return t;
      },
    );
    service.addListener(() => notifications++);
  }

  final core = FakeCore();
  final timers = <FakeTimer>[];
  late final PlayerService service;
  int notifications = 0;

  FakeTimer? get activeTimer => timers.where((t) => t.active).firstOrNull;

  /// Alle aktiven Timer einmal auslösen.
  void fire([int times = 1]) {
    for (var i = 0; i < times; i++) {
      for (final t in timers.where((t) => t.active).toList()) {
        t.onTick(t);
      }
    }
  }

  Future<bool> loadReady(
    String path,
    double duration, {
    PlaybackSettings? settings,
    String? id,
  }) async {
    final f = service.load(
      path,
      trackId: id,
      settings: settings ?? const PlaybackSettings(),
    );
    core.finishLoad(duration);
    fire();
    return f;
  }
}

void main() {
  group('#15/AK1 Zustand und Benachrichtigung', () {
    test('Laden setzt Titel, Dauer, Position und Einstellungen', () async {
      final h = Harness();
      final f = h.service.load(
        '/musik/stück.mp3',
        trackId: 't1',
        settings: const PlaybackSettings(
          speedEnabled: true,
          speed: 0.75,
          loopEnabled: true,
          loopStart: 10,
          loopEnd: 20,
        ),
      );
      expect(h.service.isLoading, isTrue);
      expect(h.notifications, greaterThan(0));
      h.core.progress = 0.5;
      h.fire();
      expect(h.service.loadProgress, 0.5);
      expect(h.service.isLoading, isTrue);

      h.core.finishLoad(120);
      h.fire();
      expect(await f, isTrue);
      expect(h.service.isLoading, isFalse);
      expect(h.service.title, 'stück.mp3');
      expect(h.service.trackId, 't1');
      expect(h.service.duration, 120);
      expect(h.service.position, 0);
      expect(h.service.isPlaying, isFalse);
      expect(h.core.rateValue, 0.75);
      expect(h.core.loop, (10.0, 20.0));
      expect(h.service.error, isNull);
    });

    test('nicht gesetztes Loop-Ende wird zum Titelende', () async {
      final h = Harness();
      await h.loadReady(
        '/a.mp3',
        90,
        settings: const PlaybackSettings(loopEnabled: true),
      );
      expect(h.service.settings.loopEnd, 90);
      expect(h.core.loop, (0.0, 90.0));
    });

    test('Play, Pause, Seek, Skip und Lautstärke', () async {
      final h = Harness();
      await h.loadReady('/a.mp3', 100);
      h.service.setVolume(0.4);
      expect(h.core.volumeValue, 0.4);
      h.service.play();
      expect(h.service.isPlaying, isTrue);
      h.core.pos = 12.5;
      h.fire();
      expect(h.service.position, 12.5);
      h.service.seek(200);
      expect(h.service.position, 100);
      expect(h.core.calls.last, 'seek 100.0');
      h.service.seek(50);
      h.service.skip(-15);
      expect(h.service.position, 35);
      h.service.skip(-100);
      expect(h.service.position, 0);
      h.service.pause();
      expect(h.service.isPlaying, isFalse);
      expect(h.core.isPlaying, isFalse);
    });

    test(
      'Leertaste im aktiven Loop springt beim Stoppen zum Loop-Anfang',
      () async {
        final h = Harness();
        await h.loadReady(
          '/a.mp3',
          100,
          settings: const PlaybackSettings(
            loopEnabled: true,
            loopStart: 20,
            loopEnd: 40,
          ),
        );
        h.service.togglePlayPauseReturningToLoop();
        expect(h.service.isPlaying, isTrue);
        h.core.pos = 33;
        h.fire();
        h.service.togglePlayPauseReturningToLoop();
        expect(h.service.isPlaying, isFalse);
        expect(h.service.position, 20);
      },
    );

    test('Dateiende: Kern hört auf, Zustand folgt', () async {
      final h = Harness();
      await h.loadReady('/a.mp3', 10);
      h.service.play();
      h.core.playing = false;
      h.core.pos = 10;
      h.fire(4); // nach der Anlaufzeit gilt der Kern
      expect(h.service.isPlaying, isFalse);
      expect(h.service.position, 10);
    });
  });

  group('#15/AK1 Einstellungen wie in der Swift-App', () {
    late Harness h;
    final saved = <(String, PlaybackSettings)>[];
    setUp(() async {
      h = Harness();
      saved.clear();
      h.service.onSettingsChanged = (id, s) => saved.add((id, s));
      await h.loadReady('/a.mp3', 100, id: 'abc');
    });

    test('Tempo in 0,05er-Schritten, begrenzt auf 0,1–2,0', () {
      h.service.setSpeed(0.7342);
      expect(h.service.settings.speed, closeTo(0.75, 1e-9));
      h.service.setSpeed(5);
      expect(h.service.settings.speed, 2.0);
      h.service.setSpeed(0);
      expect(h.service.settings.speed, closeTo(0.1, 1e-9));
      expect(h.core.rateValue, 1.0); // Schalter aus
      h.service.setSpeedEnabled(true);
      expect(h.core.rateValue, closeTo(0.1, 1e-9));
    });

    test('Pfeiltasten schalten das Tempo ein und ändern in Schritten', () {
      h.service.adjustSpeed(-2);
      expect(h.service.settings.speedEnabled, isTrue);
      expect(h.service.settings.speed, closeTo(0.9, 1e-9));
      expect(h.core.rateValue, closeTo(0.9, 1e-9));
    });

    test('Loop ohne Grenzen einschalten: ganzer Titel', () {
      h.service.setLoopEnabled(true);
      expect(h.core.loop, (0.0, 100.0));
    });

    test('Anfang hinter das Ende: Loop bis Titelende', () {
      h.service.setLoopStart(10);
      h.service.setLoopEnd(30);
      h.service.setLoopStart(50);
      expect(h.service.settings.loopStart, 50);
      expect(h.service.settings.loopEnd, 100);
      expect(h.core.loop, (50.0, 100.0));
    });

    test('Ende vor den Anfang: mindestens 1 s nach dem Anfang', () {
      h.service.setLoopStart(40);
      h.service.setLoopEnd(30);
      expect(h.service.settings.loopEnd, 41);
      expect(h.service.settings.loopStart, 40);
    });

    test('Änderungen gehen an die Bibliothek, unveränderte nicht', () {
      h.service.setLoopStart(5);
      expect(saved.length, 1);
      expect(saved.last.$1, 'abc');
      expect(saved.last.$2.loopStart, 5);
      h.service.setLoopStart(5);
      expect(saved.length, 1);
    });
  });

  group('#15/AK2 Positionsabfrage', () {
    test('etwa 30-mal pro Sekunde', () {
      expect(
        PlayerService.defaultTick.inMilliseconds,
        inInclusiveRange(30, 35),
      );
    });

    test('nur solange etwas läuft', () async {
      final h = Harness();
      expect(h.activeTimer, isNull);
      await h.loadReady('/a.mp3', 100);
      expect(h.activeTimer, isNull); // geladen, aber pausiert
      h.service.play();
      expect(h.activeTimer, isNotNull);
      expect(h.activeTimer!.interval, PlayerService.defaultTick);
      h.fire(10);
      expect(h.activeTimer, isNotNull);
      h.service.pause();
      expect(h.activeTimer, isNotNull); // noch ein Tick für die Endposition
      h.core.pos = 42;
      h.fire();
      expect(h.service.position, 42);
      expect(h.activeTimer, isNull);
      expect(h.timers.where((t) => t.active), isEmpty);
    });

    test('während der Audio-Thread «play» noch nicht übernommen hat, gilt «spielt»', () async {
      final h = Harness();
      await h.loadReady('/a.mp3', 100);
      h.core.applyPlayImmediately = false;
      h.service.play();
      h.fire();
      expect(h.service.isPlaying, isTrue);
      h.core.playing = true;
      h.fire(5);
      expect(h.service.isPlaying, isTrue);
    });

    test(
      'Gerätewechsel im Kern (pausiert) beendet die Abfrage, Position bleibt',
      () async {
        final h = Harness();
        await h.loadReady('/a.mp3', 100);
        h.service.play();
        h.core.pos = 30;
        h.fire(4);
        h.core.playing = false; // Kopfhörer ab
        h.fire();
        expect(h.service.isPlaying, isFalse);
        expect(h.service.position, 30);
        expect(h.activeTimer, isNull);
      },
    );
  });

  group('#15/AK3 Fehler', () {
    test(
      'sofortiger Fehler (kein Gerät): Meldung, alter Titel bleibt',
      () async {
        final h = Harness();
        await h.loadReady('/alt.mp3', 60);
        h.service.play();
        h.core.immediateErrors['/neu.mp3'] = WpCode.deviceUnavailable;
        expect(await h.service.load('/neu.mp3'), isFalse);
        expect(
          h.service.error,
          const LoadError(WpCode.deviceUnavailable, 'neu.mp3'),
        );
        expect(
          loadErrorMessage(de, h.service.error!),
          contains('Kein Audiogerät'),
        );
        expect(h.service.title, 'alt.mp3');
        expect(h.service.duration, 60);
        expect(h.service.isPlaying, isTrue);
      },
    );

    test('Fehler beim Dekodieren: Meldung mit Dateiname, alter Titel spielt weiter', () async {
      final h = Harness();
      await h.loadReady('/alt.mp3', 60);
      h.service.play();
      final f = h.service.load('/kaputt.flac');
      h.core.failLoad(WpCode.unsupportedFormat);
      h.fire();
      expect(await f, isFalse);
      expect(
        loadErrorMessage(de, h.service.error!),
        'Die Datei «kaputt.flac» ist kein unterstütztes Audioformat (MP3, WAV, FLAC) oder beschädigt.',
      );
      expect(h.service.title, 'alt.mp3');
      expect(h.service.isPlaying, isTrue);
      expect(h.service.isLoading, isFalse);
    });

    test('neues Laden überholt ein laufendes', () async {
      final h = Harness();
      final first = h.service.load('/eins.mp3');
      final second = h.service.load('/zwei.mp3');
      expect(await first, isFalse);
      h.core.finishLoad(5);
      h.fire();
      expect(await second, isTrue);
      expect(h.service.title, 'zwei.mp3');
    });

    test('erfolgreiches Laden löscht die alte Meldung', () async {
      final h = Harness();
      h.core.immediateErrors['/x.mp3'] = WpCode.fileNotFound;
      await h.service.load('/x.mp3');
      expect(h.service.error?.code, WpCode.fileNotFound);
      await h.loadReady('/y.mp3', 3);
      expect(h.service.error, isNull);
    });

    test('jeder Fehlercode hat eine eigene Meldung (Deutsch und Englisch)', () {
      const codes = [
        WpCode.invalidArgument,
        WpCode.fileNotFound,
        WpCode.unsupportedFormat,
        WpCode.deviceUnavailable,
        WpCode.outOfMemory,
        WpCode.fileUnreadable,
        WpCode.cancelled,
        WpCode.busy,
        WpCode.unsupportedSampleRate,
      ];
      for (final l in [de, lookupAppLocalizations(const Locale('en'))]) {
        final texts = codes
            .map((c) => loadErrorMessage(l, LoadError(c, 'x.mp3')))
            .toSet();
        expect(texts.length, codes.length);
        for (final t in texts) {
          expect(t, isNot(contains('Code')));
          expect(t, isNot(contains('code')));
        }
      }
      expect(
        loadErrorMessage(de, const LoadError(-99, 'x.mp3')),
        contains('Unbekannter Fehler'),
      );
    });
  });

  group('#29 Steigerung nach Loop-Durchgängen im PlayerService', () {
    Future<Harness> rampHarness() async {
      final h = Harness();
      await h.loadReady(
        '/a.wav',
        60,
        id: 't1',
        settings: const PlaybackSettings(
          loopEnabled: true,
          loopStart: 10,
          loopEnd: 20,
        ),
      );
      h.service.setRamp(enabled: true);
      h.service.play();
      return h;
    }

    void passes(Harness h, int n) {
      h.core.passes += n;
      h.fire();
    }

    test('Einschalten beginnt bei der Startstufe', () async {
      final h = await rampHarness();
      expect(h.service.settings.speedEnabled, isTrue);
      expect(h.service.settings.speed, 0.6);
      expect(h.core.rateValue, 0.6);
      expect(
        rampStatus(de, h.service.settings, h.service.rampPasses),
        '60 % · 0 von 10',
      );
    });

    test(
      'AK2/AK3: Durchgänge des Kerns zählen, nach 10 eine Stufe höher',
      () async {
        final h = await rampHarness();
        passes(h, 7);
        expect(h.service.rampPasses, 7);
        expect(
          rampStatus(de, h.service.settings, h.service.rampPasses),
          '60 % · 7 von 10',
        );
        passes(h, 3);
        expect(h.service.settings.speed, 0.65);
        expect(h.core.rateValue, 0.65);
        expect(h.service.rampPasses, 0);
      },
    );

    test('AK2: Seek von Hand zählt nicht', () async {
      final h = await rampHarness();
      h.service.seek(12);
      h.service.seek(10);
      h.fire(3);
      expect(h.service.rampPasses, 0);
    });

    test(
      'AK2: Durchgänge vor dem Laden oder Einschalten zählen nicht',
      () async {
        final h = Harness();
        h.core.passes = 42;
        await h.loadReady(
          '/a.wav',
          60,
          settings: const PlaybackSettings(
            loopEnabled: true,
            loopStart: 10,
            loopEnd: 20,
          ),
        );
        h.service.play();
        passes(h, 5); // Steigerung noch aus
        h.service.setRamp(enabled: true);
        passes(h, 1);
        expect(h.service.rampPasses, 1);
      },
    );

    test(
      'AK4: an der Zielstufe bleibt die Geschwindigkeit, der Zähler läuft',
      () async {
        final h = await rampHarness();
        h.service.setRamp(target: 65);
        passes(h, 10);
        expect(h.service.settings.speed, 0.65);
        passes(h, 23);
        expect(h.service.settings.speed, 0.65);
        expect(h.service.rampPasses, 23);
        expect(
          rampStatus(de, h.service.settings, h.service.rampPasses),
          '65 % · Ziel erreicht · 23 Durchgänge',
        );
      },
    );

    test('AK5: Loop-Grenzen ändern setzt den Zähler zurück', () async {
      final h = await rampHarness();
      passes(h, 6);
      h.service.setLoopEnd(25);
      expect(h.service.rampPasses, 0);
      expect(h.service.settings.speed, 0.6);
      passes(h, 6);
      h.service.setLoopStart(12);
      expect(h.service.rampPasses, 0);
    });

    test(
      'AK5: Geschwindigkeit von Hand: Zähler 0, weiter ab der neuen Stufe',
      () async {
        final h = await rampHarness();
        passes(h, 8);
        h.service.setSpeed(0.8);
        expect(h.service.rampPasses, 0);
        passes(h, 10);
        expect(h.service.settings.speed, closeTo(0.85, 1e-9));
      },
    );

    test(
      'Stufenwechsel durch die Steigerung setzt den Zähler nicht zurück',
      () async {
        final h = await rampHarness();
        passes(h, 12);
        expect(h.service.rampPasses, 2);
      },
    );

    test('AK6: ausgeschaltet bleibt die Geschwindigkeit', () async {
      final h = Harness();
      await h.loadReady(
        '/a.wav',
        60,
        settings: const PlaybackSettings(
          speedEnabled: true,
          speed: 0.7,
          loopEnabled: true,
          loopStart: 10,
          loopEnd: 20,
        ),
      );
      h.service.play();
      passes(h, 50);
      expect(h.service.settings.speed, 0.7);
      expect(h.core.rateValue, 0.7);
      expect(h.service.rampActive, isFalse);
    });

    test('ohne aktiven Loop wird nicht gezählt', () async {
      final h = await rampHarness();
      h.service.setLoopEnabled(false);
      passes(h, 20);
      expect(h.service.rampPasses, 0);
      expect(h.service.settings.speed, 0.6);
    });

    test('AK7: Stufen werden gespeichert', () async {
      final h = await rampHarness();
      final saved = <PlaybackSettings>[];
      h.service.onSettingsChanged = (_, s) => saved.add(s);
      passes(h, 10);
      expect(saved.last.speed, 0.65);
      expect(saved.last.rampEnabled, isTrue);
    });

    test('Ziel nie unter dem Start', () async {
      final h = await rampHarness();
      h.service.setRamp(start: 120);
      expect(h.service.settings.rampTarget, 120);
      h.service.setRamp(target: 50);
      expect(h.service.settings.rampStart, 50);
    });
  });

  // #11: cases found by mutation testing (make mutants).
  group('#11 PlayerService: every change notifies, state after load, unload and dispose', () {
    test('a new service is idle; play, pause, seek, volume, settings and ticks notify', () async {
      final h = Harness();
      expect(h.service.isPlaying, isFalse);
      expect(h.service.isLoading, isFalse);
      expect(h.service.isPolling, isFalse);
      await h.loadReady('/a.wav', 60);
      h.fire(); // stops polling: nothing plays
      expect(h.service.isPolling, isFalse);
      var n = h.notifications;
      void notified(String what) {
        expect(h.notifications, greaterThan(n), reason: what);
        n = h.notifications;
      }

      h.service.play();
      notified('play');
      expect(h.service.isPolling, isTrue);
      h.service.play(); // already playing: nothing to do
      expect(h.core.calls.where((c) => c == 'play').length, 1);
      expect(h.notifications, n);
      h.service.pause();
      notified('pause');
      h.fire(2); // the last tick ends the polling
      notified('tick');
      expect(h.service.isPolling, isFalse);
      h.service.seek(5);
      notified('seek');
      expect(h.service.isPolling, isTrue); // a seek fetches the final position
      h.service.setVolume(0.5);
      notified('volume');
      h.service.setSpeed(0.75);
      notified('settings');
    });

    test('play without a title does nothing', () {
      final h = Harness();
      h.service.play();
      expect(h.core.calls, isNot(contains('play')));
      expect(h.service.isPlaying, isFalse);
      expect(h.notifications, 0);
    });

    test('an immediate load error notifies and is not «loading»', () {
      final h = Harness();
      h.core.immediateErrors['/x.wav'] = WpCode.fileNotFound;
      h.service.load('/x.wav');
      expect(h.service.isLoading, isFalse);
      expect(h.service.error?.code, WpCode.fileNotFound);
      expect(h.notifications, greaterThan(0));
      final n = h.notifications;
      h.service.clearError();
      expect(h.service.error, isNull);
      expect(h.notifications, n + 1);
      h.service.clearError(); // no error: no notification
      expect(h.notifications, n + 1);
    });

    test('a load that ends neither ready nor with an error code is an invalid argument', () async {
      final h = Harness();
      final f = h.service.load('/a.wav');
      h.core.failLoad(WpCode.loadIdle);
      h.fire();
      expect(await f, isFalse);
      expect(h.service.error?.code, WpCode.invalidArgument);
    });

    test('a new title starts paused, with the ramp counter at 0', () async {
      final h = Harness();
      await h.loadReady(
        '/a.wav',
        60,
        settings: const PlaybackSettings(
          loopEnabled: true,
          loopStart: 10,
          loopEnd: 20,
        ),
      );
      h.service.setRamp(enabled: true);
      h.service.play();
      h.core.passes += 3;
      h.fire();
      expect(h.service.rampPasses, 3);
      expect(h.service.isPlaying, isTrue);
      h.service.load('/b.wav');
      h.core.finishLoad(30);
      h.fire();
      expect(h.service.isPlaying, isFalse);
      expect(h.service.rampPasses, 0);
    });

    test('changing the ramp step keeps the pass counter (#29/AK5 resets only on loop or speed)', () async {
      final h = Harness();
      await h.loadReady(
        '/a.wav',
        60,
        settings: const PlaybackSettings(
          loopEnabled: true,
          loopStart: 10,
          loopEnd: 20,
        ),
      );
      h.service.setRamp(enabled: true);
      h.service.play();
      h.core.passes += 4;
      h.fire();
      expect(h.service.rampPasses, 4);
      h.service.setRamp(step: 10);
      expect(h.service.rampPasses, 4);
      h.service.setRamp(passes: 12);
      expect(h.service.rampPasses, 4);
      h.service.setLoopEnabled(false);
      expect(h.service.rampPasses, 0);
    });

    test(
      'a loop of exactly 1 s is kept; setting the end switches the loop on',
      () async {
        final h = Harness();
        await h.loadReady('/a.wav', 60);
        h.service.setLoopEnd(11);
        expect(h.service.settings.loopEnabled, isTrue);
        h.service.setLoopStart(10);
        expect(h.service.settings.loopStart, 10);
        expect(h.service.settings.loopEnd, 11);
        expect(h.service.activeLoop, (10.0, 11.0));
      },
    );

    test('unload while playing stops and notifies', () async {
      final h = Harness();
      await h.loadReady('/a.wav', 60);
      h.service.play();
      final n = h.notifications;
      h.service.unload();
      expect(h.service.isPlaying, isFalse);
      expect(h.service.hasTrack, isFalse);
      expect(h.notifications, n + 1);
    });

    test('dispose stops polling and ends a running load with false', () async {
      final h = Harness();
      final f = h.service.load('/a.wav');
      expect(h.activeTimer, isNotNull);
      h.service.dispose();
      expect(h.activeTimer, isNull);
      expect(await f, isFalse);
      expect(() => h.service.addListener(() {}), throwsStateError);
    });
  });
}
