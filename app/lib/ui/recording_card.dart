// Aufnahme des Systemtons (#4, nur macOS 14.2+). Fertige Aufnahmen kommen in die Bibliothek (#17).
import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:wp_core/wp_core.dart';

import '../app/app_controller.dart';
import '../time_format.dart';
import 'style.dart';

class RecordingCard extends StatefulWidget {
  const RecordingCard({super.key, required this.controller});
  final AppController controller;

  @override
  State<RecordingCard> createState() => _RecordingCardState();
}

class _RecordingCardState extends State<RecordingCard> {
  Timer? _ticker;
  bool _recording = false;
  double _seconds = 0, _level = 0;
  bool _silent = false;
  String? _path, _error;

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
    final dir = await widget.controller.files.recordingsDir();
    if (dir == null) return;
    final path = '$dir/Aufnahme ${fileStamp(DateTime.now())}.wav';
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
      setState(() => _error = 'Aufnahme nicht möglich: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeFocus(
      child: WsCard(
        key: const Key('card:recording'),
        children: [
          CardHeader(
            icon: WsIcons.record,
            title: 'Aufnahme',
            trailing: FilledButton.icon(
              onPressed: _toggle,
              style: FilledButton.styleFrom(
                backgroundColor: _recording ? Colors.red : null,
              ),
              icon: Icon(_recording ? WsIcons.stop : WsIcons.record, size: 14),
              label: Text(_recording ? 'Stopp' : 'Aufnahme starten'),
            ),
          ),
          if (_recording)
            Row(
              children: [
                Text(
                  formatTime(_seconds),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LinearProgressIndicator(value: _level.clamp(0, 1)),
                ),
              ],
            ),
          if (_silent)
            Text(
              'Es kommt nur Stille an. Läuft gerade Musik? Sonst die Berechtigung erteilen: '
              'Systemeinstellungen › Datenschutz & Sicherheit › Bildschirm- & Systemaudioaufnahme.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          const HintText(
            'Nimmt den Systemton auf (ohne Mikrofon). Die Aufnahme wird nur lokal gespeichert '
            'und danach in die Bibliothek übernommen.',
          ),
        ],
      ),
    );
  }
}
