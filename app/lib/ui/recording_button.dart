// Aufnahme des Systemtons (#4, nur macOS 14.2+) als Knopf im Kopf (#30). Fertige Aufnahmen kommen in
// die Bibliothek (#17).
import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:wp_core/wp_core.dart';

import '../app/app_controller.dart';
import '../time_format.dart';
import 'messages.dart';
import 'style.dart';

class RecordingButton extends StatefulWidget {
  const RecordingButton({super.key, required this.controller});
  final AppController controller;

  @override
  State<RecordingButton> createState() => _RecordingButtonState();
}

class _RecordingButtonState extends State<RecordingButton> {
  Timer? _ticker;
  bool _recording = false;
  double _seconds = 0, _level = 0;
  bool _silent = false;
  String? _path;

  /// Detail of the core when recording could not start.
  String? _error;

  @override
  void dispose() {
    _ticker?.cancel();
    if (WpRecorder.isRecording) WpRecorder.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recording) {
      WpRecorder.stop();
      _ticker?.cancel();
      _ticker = null;
      setState(() => _recording = false);
      final path = _path;
      if (path != null && File(path).existsSync()) {
        await widget.controller.addRecording(path);
      }
      return;
    }
    final name = context.l10n.recordingFileName(fileStamp(DateTime.now()));
    final dir = await widget.controller.files.recordingsDir();
    if (dir == null) return;
    final path = '$dir/$name.wav';
    try {
      WpRecorder.start(path);
      setState(() {
        _recording = true;
        _path = path;
        _seconds = 0;
        _silent = false;
        _error = null;
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
        setState(() {
          _seconds = WpRecorder.seconds;
          _level = WpRecorder.level;
          _silent = _seconds > 3 && WpRecorder.onlySilence;
        });
      });
    } on WpException catch (e) {
      setState(() => _error = e.message);
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
        ? l.recordingFailed(error)
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
