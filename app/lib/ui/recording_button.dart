// Recording as a button in the header (#30): the system audio (#4, macOS 14.2+) as WAV or the
// microphone (#113, macOS) as FLAC, chosen in the menu next to the button and remembered on this
// device. Finished recordings go to the library (#17), titled with date and time in the user's locale.
import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:wp_core/wp_core.dart';

import '../app/app_controller.dart';
import '../time_format.dart';
import 'messages.dart';
import 'style.dart';

/// The recorder behind the button; tests replace the core with a fake (#4).
abstract class Recorder {
  /// [source] records on this platform (#113).
  bool sourceAvailable(WpRecSource source);

  /// Records [source] into [path]. Throws [WpRecordingException] if recording cannot start.
  void start(String path, WpRecSource source);
  void stop();
  bool get isRecording;
  double get seconds;

  /// Peak level since the last query, 0–1.
  double get level;

  /// Only silence so far: no permission, or nothing is playing.
  bool get onlySilence;
}

/// [Recorder] of the audio core.
class CoreRecorder implements Recorder {
  const CoreRecorder();
  @override
  bool sourceAvailable(WpRecSource source) =>
      WpRecorder.sourceAvailable(source);
  @override
  void start(String path, WpRecSource source) =>
      WpRecorder.startSource(path, source);
  @override
  void stop() => WpRecorder.stop();
  @override
  bool get isRecording => WpRecorder.isRecording;
  @override
  double get seconds => WpRecorder.seconds;
  @override
  double get level => WpRecorder.level;
  @override
  bool get onlySilence => WpRecorder.onlySilence;
}

class RecordingButton extends StatefulWidget {
  const RecordingButton({
    super.key,
    required this.controller,
    this.recorder = const CoreRecorder(),
    this.now = DateTime.now,
  });
  final AppController controller;
  final Recorder recorder;

  /// Clock for the name of the recording.
  final DateTime Function() now;

  @override
  State<RecordingButton> createState() => _RecordingButtonState();
}

class _RecordingButtonState extends State<RecordingButton> {
  Timer? _ticker;
  bool _recording = false;
  double _seconds = 0, _level = 0;
  bool _silent = false;
  String? _path;
  String? _title;

  /// Error of the core when recording could not start (#44).
  WpRecordingException? _error;

  /// #113/AK4: the microphone permission was refused; nothing was recorded.
  bool _micDenied = false;

  /// Source of the running recording.
  WpRecSource? _recordingSource;

  /// #113/AK1: the sources this platform records, in menu order.
  List<WpRecSource> get _sources => [
    for (final s in WpRecSource.values)
      if (widget.recorder.sourceAvailable(s)) s,
  ];

  /// The source last chosen on this device; the system audio until one is chosen (as before #113).
  WpRecSource get _source {
    final sources = _sources;
    final chosen = WpRecSource.named(widget.controller.library.recordingSource);
    if (chosen != null && sources.contains(chosen)) return chosen;
    return sources.isEmpty ? WpRecSource.system : sources.first;
  }

  void _choose(WpRecSource source) {
    // The library takes the new source at once and saves it in the background.
    unawaited(widget.controller.library.setRecordingSource(source.name));
    setState(() {
      _micDenied = false;
      _error = null;
      _silent = false;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (widget.recorder.isRecording) widget.recorder.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      widget.recorder.stop();
      _ticker?.cancel();
      _ticker = null;
      setState(() => _recording = false);
      final path = _path;
      if (path != null && File(path).existsSync()) {
        await widget.controller.addRecording(path, title: _title);
      }
      return;
    }
    final l = context.l10n;
    final source = _source;
    final now = widget.now();
    final name = l.recordingFileName(fileStamp(now));
    final title = recordingTitle(l, now);
    final files = widget.controller.files;
    // #113/AK4: macOS asks the first time; refused, there is a hint and no file, so no empty title.
    if (source == WpRecSource.microphone && !await files.microphoneAccess()) {
      if (mounted) setState(() => _micDenied = true);
      return;
    }
    final dir = await files.recordingsDir();
    if (dir == null || !mounted) return;
    final path = '$dir/$name.${source.extension}';
    try {
      widget.recorder.start(path, source);
      setState(() {
        _recording = true;
        _recordingSource = source;
        _path = path;
        _title = title;
        _seconds = 0;
        _silent = false;
        _error = null;
        _micDenied = false;
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
        setState(() {
          _seconds = widget.recorder.seconds;
          _level = widget.recorder.level;
          _silent = _seconds > 3 && widget.recorder.onlySilence;
        });
      });
    } on WpRecordingException catch (e) {
      debugPrint(e.toString());
      setState(() => _error = e);
    }
  }

  void _explain(String text) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.ok),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    final l = context.l10n;
    final error = _error;
    final source = _recording ? (_recordingSource ?? _source) : _source;
    final mic = source == WpRecSource.microphone;
    final sources = _sources;
    final problem = error != null
        ? l.recordingFailed(recordingErrorMessage(l, error))
        : _micDenied
        ? l.recordingMicrophoneDenied
        : _silent
        ? (mic ? l.recordingMicrophoneSilent : l.recordingSilent)
        : null;
    return ExcludeFocus(
      child: Row(
        key: const Key('recordingButton'),
        mainAxisSize: MainAxisSize.min,
        spacing: WsSpace.s,
        children: [
          if (problem != null)
            IconButton(
              key: const Key('recordingProblem'),
              tooltip: problem,
              color: ws.record,
              icon: const Icon(WsIcons.warning, size: 18),
              onPressed: () => _explain(problem),
            ),
          if (_recording)
            SizedBox(
              width: 40,
              child: LinearProgressIndicator(
                key: const Key('recordingLevel'),
                value: _level.clamp(0, 1),
                color: ws.record,
                minHeight: 4,
              ),
            ),
          // #113/AK1: the source, chosen before recording; hidden while one runs.
          if (!_recording && sources.length > 1)
            PopupMenuButton<WpRecSource>(
              key: const Key('recordingSource'),
              tooltip: l.recordingSource,
              icon: Icon(mic ? WsIcons.mic : WsIcons.desktop, size: 18),
              onSelected: _choose,
              itemBuilder: (_) => [
                for (final s in sources)
                  CheckedPopupMenuItem(
                    key: Key('recordingSource:${s.name}'),
                    value: s,
                    checked: s == source,
                    child: Text(recordingSourceLabel(l, s)),
                  ),
              ],
            ),
          Tooltip(
            message: mic ? l.recordingTooltipMicrophone : l.recordingTooltip,
            child: TextButton(
              onPressed: _toggle,
              style: TextButton.styleFrom(
                foregroundColor: ws.text,
                backgroundColor: _recording ? ws.amberSoft : ws.panel2,
                minimumSize: Size(m.target, m.touch ? m.target : 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                  fontFamily: textFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: ws.border),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: WsSpace.s,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: ws.record,
                      borderRadius: BorderRadius.circular(_recording ? 1 : 5),
                    ),
                  ),
                  _recording
                      ? Text(
                          formatTime(_seconds),
                          key: const Key('recordingDuration'),
                          style: ws.number(12, weight: FontWeight.w600),
                        )
                      : Text(l.recording),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
