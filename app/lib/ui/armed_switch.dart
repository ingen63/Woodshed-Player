// #147: the switch «Armed» of the areas Practice and Metronome (Mac; #157: and the web app): on, the microphone records
// each time you play (PracticeRecording). It shows armed (a ring) and recording (a square and the
// duration), the level of the microphone, and opens a popover with the threshold, a level meter to set
// it by, and the pause that ends a take.
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import '../app/practice_recording.dart';
import '../time_format.dart';
import 'messages.dart';
import 'style.dart';

/// #147/AK11, AK12: why the switch went off, for the user.
String armedProblemMessage(
  AppLocalizations l,
  PracticeArmProblem p,
  PracticeRecording practice,
) => switch (p) {
  PracticeArmProblem.busy => l.armedBusy,
  // #157/AK6: in the browser the website's permission, not a macOS setting
  PracticeArmProblem.microphoneDenied =>
    kIsWeb ? l.armedMicrophoneDeniedBrowser : l.armedMicrophoneDenied,
  PracticeArmProblem.background => l.armedStoppedInBackground,
  PracticeArmProblem.storageFull => l.armedStorageFull,
  PracticeArmProblem.failed => switch (practice.recording.error) {
    final e? => l.recordingFailed(recordingErrorMessage(l, e)),
    null => l.armedFailed,
  },
};

/// #147/AK10: position of a peak [level] (0–1) on a meter from [PracticeRecording.minThresholdDb] to
/// 0 dBFS, 0–1.
double meterPosition(double level) {
  if (level <= 0) return 0;
  final db = 20 * math.log(level) / math.ln10;
  return ((db - PracticeRecording.minThresholdDb) /
          (PracticeRecording.maxThresholdDb - PracticeRecording.minThresholdDb))
      .clamp(0.0, 1.0);
}

class ArmedSwitch extends StatefulWidget {
  const ArmedSwitch({super.key, required this.practice});
  final PracticeRecording practice;

  @override
  State<ArmedSwitch> createState() => _ArmedSwitchState();
}

class _ArmedSwitchState extends State<ArmedSwitch> {
  PracticeRecording get _p => widget.practice;

  Future<void> _toggle() async {
    if (_p.on) {
      await _p.turnOff();
      return;
    }
    final problem = await _p.turnOn(context.l10n);
    if (problem != null && mounted) _explain(problem);
  }

  void _explain(PracticeArmProblem problem) {
    final l = context.l10n;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('armedProblemDialog'),
        content: Text(armedProblemMessage(l, problem, _p)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.ok),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: _p, builder: (context, _) => _build());

  Widget _build() {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    final l = context.l10n;
    final on = _p.on;
    final running = _p.takeRunning;
    final problem = _p.problem;
    final duration = formatTime(_p.seconds);
    return ExcludeFocus(
      child: Row(
        key: const Key('armedSwitch'),
        mainAxisSize: MainAxisSize.min,
        spacing: WsSpace.xs,
        children: [
          if (problem != null && !on)
            IconButton(
              key: const Key('armedProblem'),
              tooltip: armedProblemMessage(l, problem, _p),
              color: ws.record,
              icon: const Icon(WsIcons.warning, size: 18),
              onPressed: () => _explain(problem),
            ),
          if (on)
            SizedBox(
              width: 40,
              child: LinearProgressIndicator(
                key: const Key('armedLevel'),
                value: meterPosition(_p.level),
                color: ws.record,
                minHeight: 4,
              ),
            ),
          Semantics(
            toggled: on,
            label: running
                ? l.armedRecordingLabel(duration)
                : on
                ? l.armedWaiting
                : l.armedSwitch,
            excludeSemantics: true,
            child: Tooltip(
              message: l.armedSwitchTooltip,
              child: TextButton(
                key: const Key('armedToggle'),
                onPressed: _toggle,
                style: TextButton.styleFrom(
                  foregroundColor: ws.text,
                  backgroundColor: running
                      ? ws.record.withAlpha(48)
                      : on
                      ? ws.amberSoft
                      : ws.panel2,
                  minimumSize: Size(m.target, m.touch ? m.target : 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(
                    fontFamily: textFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: on ? ws.record : ws.border),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: WsSpace.s,
                  children: [
                    // #147/AK10: off a grey ring, armed a red ring, recording a red square.
                    Container(
                      key: Key(
                        running
                            ? 'armedMark:recording'
                            : on
                            ? 'armedMark:armed'
                            : 'armedMark:off',
                      ),
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: running ? ws.record : null,
                        border: running
                            ? null
                            : Border.all(
                                color: on ? ws.record : ws.muted,
                                width: 2,
                              ),
                        borderRadius: BorderRadius.circular(running ? 1 : 5),
                      ),
                    ),
                    running
                        ? Text(
                            duration,
                            key: const Key('armedDuration'),
                            style: ws.number(12, weight: FontWeight.w600),
                          )
                        : Text(l.armedSwitch),
                  ],
                ),
              ),
            ),
          ),
          MenuAnchor(
            menuChildren: [ArmedSettingsPanel(practice: _p)],
            builder: (context, menu, _) => IconButton(
              key: const Key('armedSettingsButton'),
              tooltip: l.armedSettings,
              icon: const Icon(WsIcons.chevronDown, size: 16),
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            ),
          ),
        ],
      ),
    );
  }
}

/// #147/AK9: the popover at the switch: threshold with a level meter, and the pause; #156/AK1: whether
/// the switch goes off after a take.
class ArmedSettingsPanel extends StatelessWidget {
  const ArmedSettingsPanel({super.key, required this.practice});
  final PracticeRecording practice;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: practice,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final ws = WsTheme.of(context);
    final l = context.l10n;
    final p = practice;
    final threshold = p.thresholdDb;
    final silence = p.silenceSeconds;
    final range =
        PracticeRecording.maxThresholdDb - PracticeRecording.minThresholdDb;
    final mark = (threshold - PracticeRecording.minThresholdDb) / range;
    final level = meterPosition(p.level);
    final loud = level > mark;
    return Container(
      key: const Key('armedSettings'),
      width: 280,
      padding: const EdgeInsets.all(WsSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.armedSettings,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: WsSpace.m),
          _row(
            l.armedThreshold,
            l.armedThresholdValue(threshold.round()),
            ws,
            const Key('armedThresholdValue'),
          ),
          const SizedBox(height: WsSpace.s),
          // #147: the level against the threshold, so the threshold can be set by ear and eye.
          Semantics(
            label: l.armedLevel,
            child: SizedBox(
              key: const Key('armedMeter'),
              height: 8,
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: ws.panel2,
                        border: Border.all(color: ws.border),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Container(
                      width: box.maxWidth * level,
                      decoration: BoxDecoration(
                        color: loud ? ws.record : ws.amber,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Positioned(
                      left: (box.maxWidth * mark - 1).clamp(
                        0,
                        box.maxWidth - 2,
                      ),
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: ws.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!p.on)
            Padding(
              padding: const EdgeInsets.only(top: WsSpace.xs),
              child: Text(
                l.armedLevelOff,
                key: const Key('armedLevelOff'),
                style: TextStyle(color: ws.muted, fontSize: 12),
              ),
            ),
          Slider(
            key: const Key('armedThresholdSlider'),
            min: PracticeRecording.minThresholdDb,
            max: PracticeRecording.maxThresholdDb,
            divisions: range.round(),
            value: threshold,
            label: l.armedThresholdValue(threshold.round()),
            onChanged: (v) => p.setThresholdDb(v.roundToDouble()),
            onChangeEnd: (_) => p.applySettings(),
          ),
          _row(
            l.armedSilence,
            l.armedSilenceValue(silence.round()),
            ws,
            const Key('armedSilenceValue'),
          ),
          Slider(
            key: const Key('armedSilenceSlider'),
            min: PracticeRecording.minSilenceSeconds,
            max: PracticeRecording.maxSilenceSeconds,
            divisions:
                (PracticeRecording.maxSilenceSeconds -
                        PracticeRecording.minSilenceSeconds)
                    .round(),
            value: silence,
            label: l.armedSilenceValue(silence.round()),
            onChanged: (v) => p.setSilenceSeconds(v.roundToDouble()),
            onChangeEnd: (_) => p.applySettings(),
          ),
          // #156/AK1: off after a take (the default) or armed again for the next one.
          Row(
            children: [
              Expanded(child: Text(l.armedOffAfterTake)),
              Switch(
                key: const Key('armedOffAfterTake'),
                value: !p.keepsOn,
                onChanged: (v) => p.setKeepsOn(!v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, WsTheme ws, Key key) => Row(
    children: [
      Expanded(child: Text(label)),
      Text(
        value,
        key: key,
        style: ws.number(12, weight: FontWeight.w600),
      ),
    ],
  );
}
