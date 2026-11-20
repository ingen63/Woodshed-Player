// Attrappen für Tests ohne Audiogerät und ohne nativen Teil (#15, #17).
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/file_platform.dart';
import 'package:woodshed_player/app/file_store_io.dart';
import 'package:woodshed_player/l10n/app_localizations.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/metronome/metronome_controller.dart';
import 'package:woodshed_player/player/audio_core.dart';
import 'package:woodshed_player/player/player_service.dart';
import 'package:woodshed_player/sync/sync_service.dart';
import 'package:wp_core/wp_core.dart';

/// Kern-Attrappe: Laden bleibt «läuft», bis der Test es mit [finishLoad] oder [failLoad] beendet.
/// UI tests fix the language (#43): German, so the expected texts below stay independent of the system.
const testLocale = Locale('de');
const testDelegates = <LocalizationsDelegate<Object?>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

const testLocales = AppLocalizations.supportedLocales;

/// German texts for checks outside widgets.
final de = lookupAppLocalizations(testLocale);

class FakeCore implements AudioCore {
  final immediateErrors = <String, int>{};
  int _state = WpCode.loadIdle;
  double _progress = 0;
  double _duration = 0;
  bool playing = false;
  bool applyPlayImmediately =
      true; // false: Audio-Thread übernimmt «play» erst später
  double pos = 0;

  /// false: the audio thread applies a seek only on [applySeek] (slow device, #73).
  bool applySeekImmediately = true;
  double? pendingSeek;
  void applySeek() {
    final t = pendingSeek;
    if (t != null) pos = t;
    pendingSeek = null;
  }

  double rateValue = 1;
  double volumeValue = 1;
  (double, double)? loop;

  /// Loop-Durchgänge des Kerns (#29); Tests zählen sie selbst hoch.
  int passes = 0;
  final calls = <String>[];

  void finishLoad(double duration) {
    _state = WpCode.loadReady;
    _progress = 1;
    _duration = duration;
    playing = false;
    pos = 0;
  }

  void failLoad(int code) => _state = code;
  set progress(double p) => _progress = p;

  @override
  int loadAsync(String path) {
    calls.add('load $path');
    final err = immediateErrors[path];
    if (err != null) {
      _state = err;
      return err;
    }
    _state = WpCode.loadRunning;
    _progress = 0;
    return WpCode.ok;
  }

  @override
  int get loadState => _state;
  @override
  double get loadProgress => _progress;
  @override
  void play() {
    calls.add('play');
    if (applyPlayImmediately) playing = true;
  }

  @override
  void pause() {
    calls.add('pause');
    playing = false;
  }

  @override
  bool get isPlaying => playing;
  @override
  void seek(double seconds) {
    calls.add('seek $seconds');
    if (applySeekImmediately) {
      pos = seconds;
    } else {
      pendingSeek = seconds;
    }
  }

  @override
  set rate(double r) => rateValue = r;
  @override
  void setLoop(double a, double b) => loop = (a, b);
  @override
  void clearLoop() => loop = null;
  @override
  set volume(double v) => volumeValue = v;
  @override
  double get position => pos;
  @override
  double get duration => _duration;
  @override
  int get loopPasses => passes;

  /// Wellenform (#28): aus, bis ein Test sie einschaltet; dann ein Sinus-Hüllkurve über die Zeit.
  bool hasWaveform = false;
  @override
  WpWaveform? waveform(double start, double end, int count) {
    if (!hasWaveform || _duration <= 0 || count <= 0 || end <= start) {
      return null;
    }
    final mins = Float32List(count), maxs = Float32List(count);
    for (var i = 0; i < count; i++) {
      final t = start + (end - start) * (i + 0.5) / count;
      final a = 0.2 + 0.7 * (sin(t / 3).abs());
      mins[i] = -a;
      maxs[i] = a;
    }
    return WpWaveform(mins, maxs);
  }
}

class FakeTimer implements Timer {
  FakeTimer(this.interval, this.onTick);
  final Duration interval;
  final void Function(Timer) onTick;
  bool active = true;
  @override
  void cancel() => active = false;
  @override
  bool get isActive => active;
  @override
  int get tick => 0;
}

class FakeMetronome implements MetronomeBackend {
  bool isRunning = false;
  int _bpm = 120;
  @override
  void start() => isRunning = true;
  @override
  void stop() => isRunning = false;
  @override
  bool get running => isRunning;
  @override
  int get bpm => _bpm;
  @override
  set bpm(int v) => _bpm = v;
  @override
  set meter(int v) {}
  @override
  set subdivision(int v) {}
  @override
  set volume(double v) {}
  @override
  void ramp({
    required bool enabled,
    required int start,
    required int target,
    required int step,
    required int everyBars,
  }) {}
  @override
  void timedRamp({
    required bool enabled,
    required int start,
    required int target,
    required int seconds,
  }) {}
}

class FakeFiles implements FilePlatform {
  List<String> nextPick = [];
  int picks = 0;
  void Function(List<String>)? drop;

  @override
  Future<List<String>> pickAudioFiles() async {
    picks++;
    return nextPick;
  }

  @override
  Future<String?> supportDir() async => null;
  @override
  Future<String?> recordingsDir() async => recordings;

  /// Folder for recordings (#4); null: none, as without a support folder.
  String? recordings;
  @override
  void keepAwake(bool on) {}
  @override
  set onDropFiles(void Function(List<String> paths)? handler) => drop = handler;

  /// Tag and build date this fake build reports (#50/AK6).
  BuildInfo build = const BuildInfo();
  @override
  Future<BuildInfo> buildInfo() async => build;

  /// URLs handed to the system browser (#50).
  final opened = <String>[];
  @override
  Future<void> openUrl(String url) async => opened.add(url);

  void Function()? showAbout;
  @override
  set onShowAbout(void Function()? handler) => showAbout = handler;

  String? aboutMenuTitle;
  @override
  void setAboutMenuTitle(String title) => aboutMenuTitle = title;
}

/// Kern, Timer, Bibliothek in [dir] und Controller zusammen. Laden wird mit [finishLoads] abgeschlossen.
class TestApp {
  /// [duration]: Dauer jeder importierten Datei in Sekunden (null: unknown on import, as in the browser).
  TestApp(
    Directory dir, {
    double? duration = 30,
    SyncService Function(Library library)? sync,
  }) {
    library = Library(
      IoFileStore(dir),
      probe: (_) => duration,
      readSource: readLocalFile,
      saveDelay: Duration.zero,
      random: Random(3),
    );
    player = PlayerService(
      core,
      timerFactory: (d, f) {
        final t = FakeTimer(d, f);
        timers.add(t);
        return t;
      },
    );
    controller = AppController(
      library: library,
      player: player,
      metronome: MetronomeController(metronome),
      files: files,
      sync: sync?.call(library),
    );
  }

  // ignore: prefer_final_fields, unused_field
  var _clock = DateTime.utc(2026);
  final core = FakeCore();
  final timers = <FakeTimer>[];
  final metronome = FakeMetronome();
  final files = FakeFiles();
  late final Library library;
  late final PlayerService player;
  late final AppController controller;

  /// Laufendes Laden abschliessen und die Positionsabfrage einmal laufen lassen.
  void finishLoads([double duration = 30]) {
    if (core.loadState == WpCode.loadRunning) core.finishLoad(duration);
    tick();
  }

  void tick() {
    for (final t in timers.where((t) => t.active).toList()) {
      t.onTick(t);
    }
  }
}

/// In-memory FileStore that behaves like OPFS in the browser (#35): no paths, the audio core gets the name.
/// [hashGate] holds back hashing until it is completed.
class MemoryFileStore extends FileStore {
  final files = <String, Uint8List>{};
  int persistRequests = 0;
  bool persisted = false;
  Completer<void>? hashGate;

  @override
  Future<Uint8List?> read(String name) async => files[name];
  @override
  Future<void> write(String name, Uint8List bytes) async =>
      files[name] = Uint8List.fromList(bytes);
  @override
  Future<bool> exists(String name) async => files.containsKey(name);
  @override
  Future<void> delete(String name) async => files.remove(name);
  @override
  Future<void> rename(String from, String to) async =>
      files[to] = files.remove(from)!;
  @override
  Future<String?> sha256(String name) async {
    await hashGate?.future;
    final b = files[name];
    return b == null ? null : crypto.sha256.convert(b).toString();
  }

  @override
  String locate(String name) => name;
  @override
  String? localPath(String name) => null;
  @override
  Future<StorageInfo> storageInfo() async => StorageInfo(
    used: files.values.fold(0, (s, b) => s + b.length),
    quota: 1000000000,
    persisted: persisted,
  );
  @override
  Future<bool?> requestPersistence() async {
    persistRequests++;
    return persisted = true;
  }
}

/// Pumps frames until [done] holds (#62): widget tests wait for a state, never for a guessed time. Same
/// form as `pumpUntil` of the UI tests (`integration_test/ui_helpers.dart`), but on the fake clock: fails
/// after [maxFrames] frames of [step] instead of a real-time limit.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done,
  String what, {
  Duration step = const Duration(milliseconds: 10),
  int maxFrames = 500,
}) async {
  for (var i = 0; i < maxFrames && !done(); i++) {
    await tester.pump(step);
  }
  if (!done()) {
    fail('«$what» not reached after $maxFrames frames');
  }
}

/// Waits in real time until [done] holds (#62), for work outside the fake clock (file system,
/// isolates). [hangGuard] only catches a hang; under load the wait simply takes longer.
Future<void> waitUntil(
  WidgetTester tester,
  bool Function() done,
  String what, {
  Duration hangGuard = const Duration(seconds: 60),
}) async {
  await tester.runAsync(() => eventually(done, what, hangGuard: hangGuard));
}

/// Waits until [done] holds, polling in real time, instead of waiting a fixed time (#92, #78). For plain tests
/// without a [WidgetTester]. Fails only when the state is not reached within [hangGuard], so a loaded machine
/// makes the test slower, never red.
Future<void> eventually(
  bool Function() done,
  String what, {
  Duration hangGuard = const Duration(seconds: 60),
}) async {
  final watch = Stopwatch()..start();
  while (!done() && watch.elapsed < hangGuard) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  if (!done()) {
    fail('hang: «$what» not reached within ${hangGuard.inSeconds} s');
  }
}
