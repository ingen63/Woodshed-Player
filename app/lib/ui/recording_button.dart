// Recording of the system audio (#4, macOS 14.2+ only) as a button in the header (#30). Finished
// recordings go to the library (#17), titled with date and time in the user's locale.
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
  /// Throws [WpRecordingException] if recording cannot start.
  void start(String wavPath);
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
  void start(String wavPath) => WpRecorder.start(wavPath);
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
    final now = widget.now();
    final name = l.recordingFileName(fileStamp(now));
    final title = recordingTitle(l, now);
    final dir = await widget.controller.files.recordingsDir();
    if (dir == null || !mounted) return;
    final path = '$dir/$name.wav';
    try {
      widget.recorder.start(path);
      setState(() {
        _recording = true;
        _path = path;
        _title = title;
        _seconds = 0;
        _silent = false;
        _error = null;
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
    final problem = error != null
        ? l.recordingFailed(recordingErrorMessage(l, error))
        : (_silent ? l.recordingSilent : null);
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
          Tooltip(
            message: l.recordingTooltip,
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
