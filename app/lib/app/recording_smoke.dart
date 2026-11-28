// #162/AK4, AK6: smoke test of the recording in the built desktop app (WP_SMOKE=record,
// tools/smoke_app.sh) on machines without a microphone (the CI runners of Windows and Linux): the
// core's artificial input (WpRecInput) takes the place of the microphone. The flow runs the real app
// with its recording, its «Armed» switch and the platform channel (microphone access, folder for
// recordings): one recording with the record button's flow, «Armed» with three play phases (three
// takes in `Recordings › <YYYY-MM-DD>`), and a microphone the system refuses. Each recording is
// checked as FLAC with 24 bit. A real microphone stays unchecked here.
import 'dart:async';
import 'dart:io';

import 'package:wp_core/wp_types.dart';

import '../l10n/app_localizations.dart';
import '../library/track.dart';
import 'app_controller.dart';
import 'practice_recording.dart';
import 'recording_controller.dart';
import 'smoke.dart';

/// Bits per sample of the FLAC file at [path] (STREAMINFO), null if it is no FLAC file.
int? flacBits(String path) {
  final RandomAccessFile f;
  try {
    f = File(path).openSync();
  } on FileSystemException {
    return null;
  }
  try {
    final b = f.readSync(22);
    if (b.length < 22 ||
        String.fromCharCodes(b.sublist(0, 4)) != 'fLaC' ||
        (b[4] & 0x7f) != 0) {
      return null;
    }
    return ((b[20] & 1) << 4 | b[21] >> 4) + 1;
  } finally {
    f.closeSync();
  }
}

/// The smoke flow of the recording. [setInput] chooses the core's input ([WpRecInput]); [pause]
/// waits between the steps (real time: the artificial input runs in real time). Returns null when
/// every step worked, otherwise the step that failed.
Future<String?> smokeRecording(
  AppController c, {
  required RecordingController recording,
  required PracticeRecording practice,
  required bool Function(WpRecInput input) setInput,
  required AppLocalizations l,
  Duration guard = const Duration(seconds: 30),
}) async {
  Future<void> pause(double seconds) => Future<void>.delayed(
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round()),
  );
  String? notFlac24(Track t) {
    final path = c.library.localPath(t) ?? c.library.filePath(t);
    final bits = flacBits(path);
    return bits == 24 ? null : '«${t.title}» is not FLAC with 24 bit ($bits)';
  }

  // #162/AK1: with an input there is the microphone
  if (!setInput(WpRecInput.silence)) return 'no artificial input';
  if (!recording.sources.contains(WpRecSource.microphone)) {
    return 'no microphone source';
  }

  // #162/AK2: one recording, as with the record button
  if (!setInput(WpRecInput.tone)) return 'no tone';
  final refused = await recording.start(l, source: WpRecSource.microphone);
  if (refused != null) {
    return 'recording did not start: $refused ${recording.error ?? ''}';
  }
  await pause(1.5);
  if (recording.silent) return 'the tone came in as silence';
  await recording.stop();
  final outcome = await recording.done;
  if (outcome is! RecordingSaved || outcome.track == null) {
    return 'recording not saved: $outcome';
  }
  if (outcome.seconds < 1) return 'recording only ${outcome.seconds} s';
  if (notFlac24(outcome.track!) case final e?) return e;

  // #162/AK6 (replaced by this test): «Armed» with three play phases
  if (!setInput(WpRecInput.silence)) return 'no silence';
  practice
    ..setKeepsOn(true)
    ..setSilenceSeconds(PracticeRecording.minSilenceSeconds);
  final day = dateStamp(DateTime.now());
  final armedProblem = await practice.turnOn(l);
  if (armedProblem != null) return '«Armed» did not switch on: $armedProblem';
  List<Track> takes() {
    final folder = c.library.folderPath([recordingsFolder, day]);
    return folder == null
        ? const []
        : [
            for (final t in c.library.tracks)
              if (t.folderId == folder) t,
          ];
  }

  for (var phase = 1; phase <= 3; phase++) {
    if (!await waitFor(
      recording,
      () => recording.phase == RecordingPhase.armed,
      guard: guard,
    )) {
      return 'phase $phase: not armed';
    }
    await pause(0.5);
    setInput(WpRecInput.tone); // playing
    if (!await waitFor(practice, () => practice.takeRunning, guard: guard)) {
      return 'phase $phase: no take started';
    }
    await pause(1.0);
    setInput(WpRecInput.silence); // the pause after the phase ends the take
    if (!await waitFor(
      c.library,
      () => takes().length >= phase,
      guard: guard,
    )) {
      return 'phase $phase: take not in Recordings › $day';
    }
  }
  await practice.turnOff();
  final armed = takes();
  if (armed.length != 3) return '${armed.length} takes instead of 3';
  for (final t in armed) {
    if (notFlac24(t) case final e?) return e;
  }

  // #162/AK3: the system refuses the microphone: nothing starts, the hint of the setting
  final before = c.library.tracks.length;
  setInput(WpRecInput.denied);
  final denied = await recording.start(l, source: WpRecSource.microphone);
  if (denied is! RecordingMicrophoneDenied || !recording.microphoneDenied) {
    return 'refused microphone: $denied';
  }
  if (await practice.turnOn(l) != PracticeArmProblem.microphoneDenied) {
    return 'refused microphone: «Armed» did not report it';
  }
  if (recording.busy || c.library.tracks.length != before) {
    return 'refused microphone: something started';
  }
  setInput(WpRecInput.device);
  return null;
}
