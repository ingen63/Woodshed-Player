// Recording as a button in the header (#30): the system audio (#4, macOS 14.2+) or the
// microphone (#113, macOS; #157: the only source in the browser), both as FLAC (#118), chosen in the menu next to the button and
// remembered on this device. Finished recordings go to the library (#17), titled with date and time in the user's locale.
// #140: the command line arms a recording; the button shows «Armed» and cancels it when pressed.
// The state lives in a RecordingController, shared with the command line.
// #147/AK11: while «Armed» (practice recording) holds the recording, the button stays idle and a click
// only explains why.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:wp_core/wp_types.dart';

import '../app/app_controller.dart';
import '../app/recording_controller.dart';
import '../time_format.dart';
import 'messages.dart';
import 'style.dart';

export '../app/recording_controller.dart' show Recorder, RecordingInterruption;

class RecordingButton extends StatefulWidget {
  const RecordingButton({
    super.key,
    required this.controller,
    this.recorder,
    this.now = DateTime.now,
    this.recording,
  });
  final AppController controller;

  /// The recorder of the button's own recording; needed without [recording].
  final Recorder? recorder;

  /// Clock for the name of the recording.
  final DateTime Function() now;

  /// #140: the recording shared with the command line; without it the button keeps its own.
  final RecordingController? recording;

  @override
  State<RecordingButton> createState() => _RecordingButtonState();
}

class _RecordingButtonState extends State<RecordingButton> {
  RecordingController? _own;
  RecordingController get _rec => widget.recording ?? _own!;

  @override
  void initState() {
    super.initState();
    if (widget.recording == null) {
      _own = RecordingController(
        app: widget.controller,
        recorder: widget.recorder!,
        now: widget.now,
      );
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_rec.reserved) {
      _explain(context.l10n.recordingLockedByArmed);
      return;
    }
    if (_rec.busy) {
      await _rec.stop();
    } else {
      await _rec.start(context.l10n);
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _rec,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final rec = _rec;
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    final l = context.l10n;
    final error = rec.error;
    // #147/AK11: the takes of «Armed» show at the switch, not here.
    final locked = rec.reserved;
    final running = !locked && rec.phase != RecordingPhase.idle;
    final armed = rec.phase == RecordingPhase.armed;
    final source = running ? (rec.recordingSource ?? rec.source) : rec.source;
    final mic = source == WpRecSource.microphone;
    final sources = rec.sources;
    final problem = error != null
        ? l.recordingFailed(recordingErrorMessage(l, error))
        // #157/AK7, AK8: ended by itself in the browser
        : rec.interruption == RecordingInterruption.background
        ? l.recordingStoppedInBackground
        : rec.interruption == RecordingInterruption.storageFull
        ? l.recordingStorageFull
        : rec.interruption == RecordingInterruption.failed
        ? l.recordingFailed(l.recordingErrorFile)
        : rec.microphoneDenied
        // #157/AK6, #162/AK3: the setting of this system or the website's permission
        ? microphoneDeniedMessage(l)
        : rec.silent
        ? (!mic ? l.recordingSilent : microphoneSilentMessage(l))
        : null;
    return ExcludeFocus(
      child: Row(
        key: const Key('recordingButton'),
        mainAxisSize: MainAxisSize.min,
        spacing: WsSpace.s,
        children: [
          if (problem != null && !locked)
            IconButton(
              key: const Key('recordingProblem'),
              tooltip: problem,
              color: ws.record,
              icon: const Icon(WsIcons.warning, size: 18),
              onPressed: () => _explain(problem),
            ),
          if (running)
            SizedBox(
              width: 40,
              child: LinearProgressIndicator(
                key: const Key('recordingLevel'),
                value: rec.level.clamp(0, 1),
                color: ws.record,
                minHeight: 4,
              ),
            ),
          // #113/AK1: the source, chosen before recording; hidden while one runs.
          if (!running && sources.length > 1)
            PopupMenuButton<WpRecSource>(
              key: const Key('recordingSource'),
              tooltip: l.recordingSource,
              icon: Icon(mic ? WsIcons.mic : WsIcons.desktop, size: 18),
              onSelected: rec.choose,
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
            message: locked
                ? l.recordingLockedByArmed
                : armed
                ? l.recordingArmedTooltip
                : mic
                ? l.recordingTooltipMicrophone
                : l.recordingTooltip,
            child: TextButton(
              onPressed: _toggle,
              style: TextButton.styleFrom(
                foregroundColor: ws.text,
                backgroundColor: running ? ws.amberSoft : ws.panel2,
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
                  // #140/AK5: armed is a ring, recording a square, idle a dot.
                  Container(
                    key: armed ? const Key('recordingArmedMark') : null,
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: armed ? null : ws.record,
                      border: armed
                          ? Border.all(color: ws.record, width: 2)
                          : null,
                      borderRadius: BorderRadius.circular(
                        running && !armed ? 1 : 5,
                      ),
                    ),
                  ),
                  armed
                      ? Text(l.recordingArmed, key: const Key('recordingArmed'))
                      : running
                      ? Text(
                          formatTime(rec.seconds),
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
