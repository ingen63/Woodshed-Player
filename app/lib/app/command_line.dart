// Command line of the desktop app (#140): what the app does for `play` and `record`. The program of
// the app parses the arguments itself (core/src/cli.cpp) and sends one request per call to the
// running app over a local socket (command_server.dart); this file answers it. Platform-independent
// and without sockets, so it is tested with a fake library and recorder.
//
// Protocol, one UTF-8 line each:
//   request (client -> app): a JSON object, see [CommandRequest]; then optionally the line `stop`
//     (Ctrl-C). Closing the connection counts as `stop`.
//   reply (app -> client): `out <text>` (stdout), `err <text>` (stderr), finally `exit <code>`.
// Messages are English only, like log messages (#140, clarification).
import 'dart:async';

import 'package:wp_core/wp_types.dart';

import '../l10n/app_localizations.dart';
import '../library/track.dart';
import '../time_format.dart';
import 'app_controller.dart';
import 'recording_controller.dart';

/// Exit codes of the command line, the same as `WP_CLI_EXIT_*` in core/include/wp_cli.h.
abstract final class CliExit {
  static const ok = 0;

  /// No matching title, several titles, recording refused or failed, no permission.
  static const failed = 1;

  /// Wrong arguments.
  static const usage = 2;

  /// The app could not be reached (client side only).
  static const unreachable = 3;

  /// Ctrl-C while armed: nothing was recorded.
  static const cancelled = 130;
}

/// Version of the protocol; the client sends it with every request.
const cliProtocolVersion = 1;

/// One request of the command line.
class CommandRequest {
  const CommandRequest({
    required this.command,
    this.title,
    this.artist,
    this.source,
    this.silenceSeconds,
    this.thresholdDb,
  });

  /// `play` or `record`.
  final String command;
  final String? title;
  final String? artist;

  /// `system` or `mic`; null: the source last chosen in the app.
  final String? source;
  final double? silenceSeconds;
  final double? thresholdDb;

  /// The request in [json]; null if it is not one (wrong version, wrong types).
  static CommandRequest? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    if (json['version'] != cliProtocolVersion) return null;
    final command = json['command'];
    final title = json['title'];
    final artist = json['artist'];
    final source = json['source'];
    final silence = json['silence'];
    final threshold = json['threshold'];
    if (command is! String ||
        (title != null && title is! String) ||
        (artist != null && artist is! String) ||
        (source != null && source is! String) ||
        (silence != null && silence is! num) ||
        (threshold != null && threshold is! num)) {
      return null;
    }
    return CommandRequest(
      command: command,
      title: title as String?,
      artist: artist as String?,
      source: source as String?,
      silenceSeconds: (silence as num?)?.toDouble(),
      thresholdDb: (threshold as num?)?.toDouble(),
    );
  }
}

/// Where the answer goes: one line for stdout or stderr of the command.
abstract class CommandOutput {
  void out(String line);
  void err(String line);
}

/// #140/AK1–AK4: the titles of [tracks] whose title is [title] and, if given, whose artist is
/// [artist]; upper and lower case do not count, nor spaces around.
List<Track> matchingTracks(
  Iterable<Track> tracks,
  String title,
  String? artist,
) {
  String norm(String? s) => (s ?? '').trim().toLowerCase();
  final t = norm(title);
  final a = artist == null ? null : norm(artist);
  return [
    for (final track in tracks)
      if (norm(track.title) == t && (a == null || norm(track.artist) == a))
        track,
  ];
}

/// `"Title" by Artist`, or `"Title"` without an artist.
String describeTrack(String title, String? artist) {
  final a = artist?.trim() ?? '';
  return a.isEmpty ? '"$title"' : '"$title" by $a';
}

/// The source named on the command line.
WpRecSource? cliSource(String name) => switch (name) {
  'system' => WpRecSource.system,
  'mic' => WpRecSource.microphone,
  _ => null,
};

/// Where the user grants the permission, as the app's own hints name it.
const _microphoneSettings = 'System Settings > Privacy & Security > Microphone';
const _systemAudioSettings =
    'System Settings > Privacy & Security > Screen & System Audio Recording';

class CommandHandler {
  CommandHandler({required this.app, this.recording, required this.texts});

  final AppController app;

  /// The recording shared with the record button; null where the app cannot record.
  final RecordingController? recording;

  /// Texts of the app in the system language, for the default name of a recording.
  final AppLocalizations Function() texts;

  /// Runs [request] and returns the exit code. [interrupt] completes on Ctrl-C or when the client
  /// goes away.
  Future<int> run(
    CommandRequest request,
    CommandOutput o,
    Future<void> interrupt,
  ) {
    switch (request.command) {
      case 'play':
        return _play(request, o);
      case 'record':
        return _record(request, o, interrupt);
      default:
        o.err('Unknown command "${request.command}".');
        return Future.value(CliExit.usage);
    }
  }

  Future<int> _play(CommandRequest r, CommandOutput o) async {
    final title = r.title?.trim() ?? '';
    if (title.isEmpty) {
      o.err('play needs --title.');
      return CliExit.usage;
    }
    final found = matchingTracks(app.library.tracks, title, r.artist);
    if (found.isEmpty) {
      // #140/AK3
      o.err('No title ${describeTrack(title, r.artist)} in the library.');
      return CliExit.failed;
    }
    if (found.length > 1) {
      // #140/AK4
      o.err('${found.length} titles match; add --artist to choose one:');
      for (final t in found) {
        o.err('  ${describeTrack(t.title, t.artist)}');
      }
      return CliExit.failed;
    }
    final track = found.single;
    if (!await app.select(track)) {
      o.err('${describeTrack(track.title, track.artist)} could not be loaded.');
      return CliExit.failed;
    }
    app.session.playTitle();
    o.out('Playing ${describeTrack(track.title, track.artist)}.');
    return CliExit.ok;
  }

  Future<int> _record(
    CommandRequest r,
    CommandOutput o,
    Future<void> interrupt,
  ) async {
    final rec = recording;
    if (rec == null) {
      o.err('Recording is not available on this platform.');
      return CliExit.failed;
    }
    // #140/AK17
    if (rec.busy) {
      o.err('A recording is already running.');
      return CliExit.failed;
    }
    WpRecSource? source;
    if (r.source != null) {
      source = cliSource(r.source!);
      if (source == null || !rec.sources.contains(source)) {
        o.err('The source "${r.source}" cannot record here.');
        return source == null ? CliExit.usage : CliExit.failed;
      }
    }
    final from = source ?? rec.source;
    final arming = Arming(
      thresholdDb: r.thresholdDb ?? WpRecArming.defaultThresholdDb,
      silenceSeconds: r.silenceSeconds ?? WpRecArming.defaultSilenceSeconds,
    );
    if (!_inRange(arming)) {
      o.err(
        'The threshold must be ${WpRecArming.minThresholdDb.round()} to '
        '${WpRecArming.maxThresholdDb.round()} dBFS, the pause '
        '${WpRecArming.minSilenceSeconds} to ${WpRecArming.maxSilenceSeconds.round()} s.',
      );
      return CliExit.usage;
    }
    final title = r.title?.trim();
    final artist = r.artist?.trim();
    final refused = await rec.start(
      texts(),
      source: from,
      title: title == null || title.isEmpty ? null : title,
      artist: artist == null || artist.isEmpty ? null : artist,
      arming: arming,
    );
    if (refused != null) return _refused(refused, o);
    final done = rec.done!;
    // #140/AK5
    o.out(
      'Armed: waiting for sound from the ${_sourceName(from)} '
      '(threshold ${_number(arming.thresholdDb)} dBFS, ends after '
      '${_number(arming.silenceSeconds)} s of silence). Ctrl-C cancels.',
    );
    var started = false, warned = false;
    void changed() {
      if (!started && rec.phase == RecordingPhase.recording) {
        started = true;
        o.out('Recording. Ctrl-C stops and saves.');
      }
      if (!warned && rec.silent && rec.phase == RecordingPhase.armed) {
        // #140/AK15: digital silence is what macOS delivers without the permission.
        warned = true;
        o.err(
          from == WpRecSource.microphone
              ? 'Only silence from the microphone so far. Check the input in '
                    'System Settings > Sound > Input, and the permission in $_microphoneSettings.'
              : 'Only silence so far. If something is playing, allow Woodshed Player in '
                    '$_systemAudioSettings.',
        );
      }
    }

    rec.addListener(changed);
    // #140/AK14: Ctrl-C cancels while armed and stops and saves while recording.
    unawaited(
      interrupt.then((_) async {
        if (identical(rec.done, done)) await rec.stop();
      }),
    );
    final RecordingOutcome outcome;
    try {
      outcome = await done;
    } finally {
      rec.removeListener(changed);
    }
    switch (outcome) {
      case RecordingSaved(:final track, :final seconds) when track != null:
        // #140/AK13
        o.out(
          'Saved ${describeTrack(track.title, track.artist)}, ${formatTime(seconds)}.',
        );
        return CliExit.ok;
      case RecordingSaved():
        o.err('The recording could not be added to the library.');
        return CliExit.failed;
      case RecordingCancelled():
        o.err('Cancelled, nothing was recorded.');
        return CliExit.cancelled;
      default:
        return _refused(outcome, o);
    }
  }

  static bool _inRange(Arming a) =>
      a.thresholdDb >= WpRecArming.minThresholdDb &&
      a.thresholdDb <= WpRecArming.maxThresholdDb &&
      a.silenceSeconds >= WpRecArming.minSilenceSeconds &&
      a.silenceSeconds <= WpRecArming.maxSilenceSeconds;

  static int _refused(RecordingOutcome outcome, CommandOutput o) {
    o.err(switch (outcome) {
      RecordingBusy() => 'A recording is already running.',
      // #140/AK15
      RecordingMicrophoneDenied() =>
        'Woodshed Player may not use the microphone. Allow it in $_microphoneSettings, '
            'then try again.',
      RecordingFailed(:final error) =>
        'Recording not possible: ${error.message} (code ${error.code}).',
      RecordingNoFolder() => 'There is no folder for recordings.',
      _ => 'Recording not possible.',
    });
    return CliExit.failed;
  }

  static String _sourceName(WpRecSource s) => switch (s) {
    WpRecSource.system => 'system audio',
    WpRecSource.microphone => 'microphone',
  };

  /// -50 rather than -50.0; 2.5 stays.
  static String _number(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
}
