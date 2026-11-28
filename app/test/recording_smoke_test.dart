// #162/AK4, AK6: the flow of the smoke test of the recording (lib/app/recording_smoke.dart) with a
// recorder that plays the core's artificial input (WpRecInput) and a temporary library; the built
// Windows and Linux app runs it with the real core in tools/smoke_app.sh (mode «record»). The flow
// waits in real time, so a full run takes about 6 s. Never the real library.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:woodshed_player/app/practice_recording.dart';
import 'package:woodshed_player/app/recording_controller.dart';
import 'package:woodshed_player/app/recording_smoke.dart';
import 'package:woodshed_player/l10n/app_localizations.dart';
import 'package:wp_core/wp_types.dart';

import 'fakes.dart';
import 'recording_desktop_test.dart' show flacHeader;

/// The core with its artificial input: «denied» refuses the start, a tone starts the take of an armed
/// recording and silence ends it at once. Every file is a FLAC header with [bits] bits per sample.
/// [events] logs the inputs, starts and stops with the seconds since the recorder was made.
class _SimRecorder extends FakeRecorder {
  _SimRecorder(this.bits);

  final int bits;
  final _clock = Stopwatch()..start();
  final events = <(double, String)>[];
  WpRecInput input = WpRecInput.device;

  void _log(String e) => events.add((_clock.elapsedMicroseconds / 1e6, e));

  void setInput(WpRecInput v) {
    input = v;
    _log(v.name);
    if (!recording || arming == null) return;
    if (v == WpRecInput.tone && gate == WpRecGate.armed) {
      gate = WpRecGate.recording;
      keptSeconds = 1;
    } else if (v == WpRecInput.silence && gate == WpRecGate.recording) {
      gate = WpRecGate.done;
    }
  }

  @override
  void start(String path, WpRecSource source) {
    if (input == WpRecInput.denied) {
      throw const WpRecordingException(
        WpRecCode.accessDenied,
        0,
        'The system refuses access to the microphone',
      );
    }
    super.start(path, source);
    // each take its own content, so it is a new title and not a duplicate
    File(path).writeAsBytesSync([...flacHeader(bits), starts]);
    _log('start');
  }

  @override
  void startArmed(
    String path,
    WpRecSource source, {
    required double thresholdDb,
    required double silenceSeconds,
    double? tailSeconds,
  }) {
    super.startArmed(
      path,
      source,
      thresholdDb: thresholdDb,
      silenceSeconds: silenceSeconds,
      tailSeconds: tailSeconds,
    );
    _log('armed');
  }

  @override
  void stop() {
    super.stop();
    _log('stop');
  }
}

/// A recording that keeps the hint of a refused microphone to itself, when [hideDenied] is set.
class _Recording extends RecordingController {
  _Recording({required super.app, required super.recorder, super.tick});

  bool hideDenied = false;

  @override
  bool get microphoneDenied => !hideDenied && super.microphoneDenied;
}

class _Run {
  _Run(this.result, this.app, this.recorder);

  final String? result;
  final TestApp app;
  final _SimRecorder recorder;

  /// Seconds from the [n]th event named [from] to the next event named [to] after it.
  double gap(String from, String to, [int n = 0]) {
    final e = recorder.events;
    final i = [
      for (var k = 0; k < e.length; k++)
        if (e[k].$2 == from) k,
    ][n];
    final j = e.indexWhere((x) => x.$2 == to, i + 1);
    return e[j].$1 - e[i].$1;
  }
}

void main() {
  late AppLocalizations en;
  late Directory tmp;
  setUpAll(() async {
    await initializeDateFormatting();
    en = lookupAppLocalizations(const Locale('en'));
  });
  final print = debugPrint;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp_rec_smoke');
    debugPrint = (_, {wrapWidth}) {}; // the refused start is logged
  });
  tearDown(() {
    debugPrint = print;
    tmp.deleteSync(recursive: true);
  });

  /// Runs the flow. [accept] answers the [n]th call of setInput (counted from 1; default: yes);
  /// [onInput] runs after each input is set.
  Future<_Run> run({
    double duration = 30,
    int bits = 24,
    Set<WpRecSource>? sources,
    bool Function(WpRecInput input, int n)? accept,
    void Function(WpRecInput input, TestApp app)? onInput,
    bool hideDenied = false,
  }) async {
    final app = TestApp(Directory('${tmp.path}/lib'), duration: duration);
    await app.library.load();
    app.files.recordings = (Directory('${tmp.path}/rec')..createSync()).path;
    final rec = _SimRecorder(bits);
    if (sources != null) rec.sources = sources;
    final recording = _Recording(
      app: app.controller,
      recorder: rec,
      tick: const Duration(milliseconds: 1),
    )..hideDenied = hideDenied;
    final practice = PracticeRecording(
      app: app.controller,
      recording: recording,
    );
    // the record button loads the new title; the fake core finishes each load
    final loads = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => app.finishLoads(),
    );
    var calls = 0;
    try {
      final result = await smokeRecording(
        app.controller,
        recording: recording,
        practice: practice,
        setInput: (input) {
          if (!(accept?.call(input, ++calls) ?? true)) return false;
          rec.setInput(input);
          onInput?.call(input, app);
          return true;
        },
        l: en,
        guard: const Duration(seconds: 3),
      );
      return _Run(result, app, rec);
    } finally {
      loads.cancel();
      await practice.turnOff();
      practice.dispose();
      recording.dispose();
    }
  }

  test('#162/AK4 #162/AK6: one recording, three takes of «Armed», a refused microphone', () async {
    final r = await run();
    expect(r.result, isNull);
    final lib = r.app.library;
    final day = lib.folderPath([recordingsFolder, dateStamp(DateTime.now())]);
    expect(day, isNotNull);
    expect(lib.tracks, hasLength(4));
    expect(lib.tracks.where((t) => t.folderId == day), hasLength(3));
    for (final t in lib.tracks) {
      expect(flacBits(lib.localPath(t) ?? lib.filePath(t)), 24);
    }
    // the input of the system again at the end, and nothing records
    expect(r.recorder.input, WpRecInput.device);
    expect(r.recorder.recording, isFalse);
    // the artificial input runs in real time: the steps wait for it
    expect(r.gap('start', 'stop'), greaterThanOrEqualTo(1.45));
    for (var phase = 0; phase < 3; phase++) {
      expect(r.gap('armed', 'tone', phase), greaterThanOrEqualTo(0.45));
      expect(r.gap('tone', 'silence', phase + 1), greaterThanOrEqualTo(0.95));
    }
  });

  group('#162/AK4: the first step that fails is the answer', () {
    test('no artificial input', () async {
      final r = await run(accept: (_, n) => n != 1);
      expect(r.result, 'no artificial input');
    });

    test('no microphone', () async {
      final r = await run(sources: {WpRecSource.system});
      expect(r.result, 'no microphone source');
    });

    test('no tone', () async {
      final r = await run(accept: (_, n) => n != 2);
      expect(r.result, 'no tone');
    });

    test('a recording that is no FLAC with 24 bit', () async {
      final r = await run(bits: 16);
      expect(r.result, endsWith('is not FLAC with 24 bit (16)'));
    });

    test('a recording shorter than 1 s', () async {
      final r = await run(duration: 0.5);
      expect(r.result, 'recording only 0.5 s');
    });

    test('1 s is long enough; then no silence', () async {
      final r = await run(duration: 1, accept: (_, n) => n != 3);
      expect(r.result, 'no silence');
    });

    test('a refused microphone without the hint of the setting', () async {
      final r = await run(hideDenied: true);
      expect(r.result, startsWith('refused microphone: '));
      expect(r.result, isNot(contains('«Armed»')));
      expect(r.result, isNot(contains('something started')));
    });

    test('the library changed while the microphone was refused', () async {
      final r = await run(
        onInput: (input, app) {
          if (input == WpRecInput.denied) {
            app.library.delete({app.library.tracks.first.id});
          }
        },
      );
      expect(r.result, 'refused microphone: something started');
    });
  });
}
