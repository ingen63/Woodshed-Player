// #147: the armed practice recording. Switched on in the areas Practice and Metronome (Mac only), it
// records the microphone by itself: each time the level rises above the threshold a new take starts
// (1 s before the sound), and it ends after the chosen pause (1 s after the last sound) or with the
// space bar. Each take goes to the library into `Recordings › <YYYY-MM-DD>`, named after the loaded
// track and the start time. The core detects sound and silence (sound_gate.cpp); this class arms the
// next take after each one and holds the recording, so the record button and the command line stay
// off while it is on. Platform-independent, tested with a fake recorder.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wp_core/wp_types.dart';

import '../l10n/app_localizations.dart';
import 'app_controller.dart';
import 'practice_arming.dart';
import 'recording_controller.dart';

/// #147/AK7: top folder of the takes; the same name in every language, so every device finds it.
const recordingsFolder = 'Recordings';

String _two(int v) => v.toString().padLeft(2, '0');

/// #147/AK8: `HH:MM:SS`, 24 hours, the same in every language.
String clockStamp(DateTime t) =>
    '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

/// #147/AK7: `YYYY-MM-DD`.
String dateStamp(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';

/// #147/AK7, AK8: title and folders of a take that began at [started]; [track] is the title loaded in
/// the area Practice, null elsewhere.
({String title, List<String> folders}) practiceTakeNaming(
  String? track,
  DateTime started,
) {
  final name = track?.trim() ?? '';
  final time = clockStamp(started);
  return (
    title: name.isEmpty ? time : '$name $time',
    folders: [recordingsFolder, dateStamp(started)],
  );
}

/// Why the switch could not stay on.
enum PracticeArmProblem {
  /// #147/AK11: another recording runs.
  busy,

  /// #147/AK12: the microphone permission was refused.
  microphoneDenied,

  /// The core could not start (see [RecordingController.error]) or there is no folder for recordings.
  failed,
}

class PracticeRecording extends ChangeNotifier implements PracticeArming {
  PracticeRecording({required this.app, required this.recording}) {
    recording.addListener(_changed);
  }

  final AppController app;
  final RecordingController recording;

  /// #147/AK9: range and default of the threshold (dBFS).
  static const minThresholdDb = -60.0;
  static const maxThresholdDb = 0.0;
  static const defaultThresholdDb = -30.0;

  /// #147/AK9: range and default of the pause that ends a take (seconds).
  static const minSilenceSeconds = 1.0;
  static const maxSilenceSeconds = 30.0;
  static const defaultSilenceSeconds = 5.0;

  /// #147/AK3: kept after the last sound.
  static const tailSeconds = 1.0;

  bool _on = false;
  AppLocalizations? _texts;
  PracticeArmProblem? _problem;

  /// The switch is on.
  @override
  bool get on => _on;

  /// Why the switch went off by itself, until it is switched on again.
  PracticeArmProblem? get problem => _problem;

  /// A take of this switch runs or is armed in the core.
  bool get _ours =>
      identical(recording.owner, this) &&
      recording.phase != RecordingPhase.idle;

  /// #147/AK10: a take is being recorded (otherwise, while on, it waits for sound).
  bool get takeRunning => _ours && recording.phase == RecordingPhase.recording;

  /// #147/AK10: peak level of the microphone, 0–1; 0 while no take is armed.
  double get level => _ours ? recording.level : 0;

  /// #147/AK10: seconds of the running take.
  double get seconds => takeRunning ? recording.seconds : 0;

  /// #147/AK9: the threshold chosen on this device.
  double get thresholdDb => (app.library.armThresholdDb ?? defaultThresholdDb)
      .clamp(minThresholdDb, maxThresholdDb);

  /// #147/AK9: the pause chosen on this device.
  double get silenceSeconds =>
      (app.library.armSilenceSeconds ?? defaultSilenceSeconds).clamp(
        minSilenceSeconds,
        maxSilenceSeconds,
      );

  /// #147/AK9: remembers the threshold on this device; the next armed take uses it ([applySettings]).
  void setThresholdDb(double db) {
    unawaited(
      app.library.setArmSettings(
        thresholdDb: db.clamp(minThresholdDb, maxThresholdDb),
      ),
    );
    notifyListeners();
  }

  /// #147/AK9: remembers the pause on this device.
  void setSilenceSeconds(double seconds) {
    unawaited(
      app.library.setArmSettings(
        silenceSeconds: seconds.clamp(minSilenceSeconds, maxSilenceSeconds),
      ),
    );
    notifyListeners();
  }

  /// #147/AK9: the settings apply at once while waiting for sound (armed anew); a running take keeps
  /// its settings, the next one gets the new ones.
  Future<void> applySettings() async {
    if (_ours && recording.phase == RecordingPhase.armed) {
      await recording.stop();
    }
  }

  /// #147/AK1, AK11, AK12: switches on and arms the first take. Returns why it could not, then the
  /// switch is off again.
  Future<PracticeArmProblem?> turnOn(AppLocalizations l) async {
    if (_on) return null;
    _texts = l;
    if (!recording.reserve(this)) return _fail(PracticeArmProblem.busy);
    _on = true;
    _problem = null;
    notifyListeners();
    return _arm();
  }

  /// #147/AK6: switches off; a running take is stopped and saved, an armed one leaves nothing.
  Future<void> turnOff() async {
    if (!_on) return;
    _on = false;
    // Releasing tells the listeners (_changed).
    recording.release(this);
    if (_ours) await recording.stop();
  }

  /// #147/AK4: the space bar ends a running take at once; the switch stays on.
  @override
  Future<void> endTake() async {
    if (takeRunning) await recording.stop();
  }

  Future<PracticeArmProblem?> _arm() async {
    final l = _texts;
    // The start marks the recording busy at once, so a second call waits for the next end.
    if (!_on || recording.busy || l == null) return null;
    final refused = await recording.start(
      l,
      source: WpRecSource.microphone,
      arming: Arming(
        thresholdDb: thresholdDb,
        silenceSeconds: silenceSeconds,
        tailSeconds: tailSeconds,
      ),
      owner: this,
      naming: _naming,
      select: false,
    );
    if (refused == null) {
      // Switched off while the start waited for the permission: nothing is kept.
      if (!_on) await recording.stop();
      return null;
    }
    await turnOff();
    return _fail(switch (refused) {
      RecordingMicrophoneDenied() => PracticeArmProblem.microphoneDenied,
      RecordingBusy() => PracticeArmProblem.busy,
      _ => PracticeArmProblem.failed,
    });
  }

  PracticeArmProblem _fail(PracticeArmProblem p) {
    _problem = p;
    notifyListeners();
    return p;
  }

  ({String title, List<String> folders}) _naming(DateTime started) =>
      practiceTakeNaming(
        app.area == AppArea.practice && app.player.hasTrack
            ? app.currentTitle
            : null,
        started,
      );

  /// #147/AK5: after each take the next one is armed while the switch is on.
  void _changed() {
    if (_on) unawaited(Future.microtask(_arm));
    notifyListeners();
  }

  @override
  void dispose() {
    recording.removeListener(_changed);
    recording.release(this);
    super.dispose();
  }
}
