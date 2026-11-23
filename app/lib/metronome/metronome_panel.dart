import 'package:material_ui/material_ui.dart';

import 'metronome_controller.dart';
import 'metronome_settings.dart';
import '../ui/messages.dart';
import '../ui/style.dart';
import 'repeat_button.dart';

/// Bedienfeld des Metronoms in Karten wie der Player-Reiter (#19). #133: on the desktop in two columns
/// (tempo and meter left, ramp right), so that the minimum window size (#130) shows all of it.
class MetronomePanel extends StatelessWidget {
  const MetronomePanel({super.key, required this.controller});

  final MetronomeController controller;

  static const _subdivisions = [1, 2, 3, 4];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.settings;
        final l = context.l10n;
        final size = WsLayout.of(context).size;
        final narrow = size == WsSize.phone;
        final rampMode = _RampMode(
          controller: controller,
          byTime: s.rampByTime,
        );
        final tempo = WsCard(
          key: const Key('card:metronome'),
          children: [
            CardHeader(
              icon: WsIcons.metronome,
              title: l.metronome,
              trailing: ExcludeFocus(
                child: FilledButton.icon(
                  key: const Key('metronomeToggle'),
                  onPressed: controller.toggle,
                  icon: Icon(
                    controller.running ? WsIcons.stop : WsIcons.play,
                    size: 16,
                  ),
                  label: Text(
                    controller.running
                        ? l.metronomeStopKey
                        : l.metronomeStartKey,
                  ),
                ),
              ),
            ),
            Row(
              children: [
                RepeatButton(
                  icon: Icons.remove,
                  tooltip: l.slower,
                  onStep: () => controller.changeBpm(-1),
                ),
                Expanded(
                  child: Text(
                    l.bpm(s.bpm),
                    key: const Key('metronomeBpm'),
                    textAlign: TextAlign.center,
                    // #115: in the area Metronome the tempo is its largest number
                    style: WsTheme.of(context).number(
                      WsLayout.of(context).bpm,
                      color: WsTheme.of(context).blue,
                    ),
                  ),
                ),
                RepeatButton(
                  icon: Icons.add,
                  tooltip: l.faster,
                  onStep: () => controller.changeBpm(1),
                ),
                const SizedBox(width: 8),
                BorderedButton(label: l.tapKey, onPressed: controller.tap),
              ],
            ),
            Slider(
              value: s.bpm.toDouble(),
              min: MetronomeSettings.minBpm.toDouble(),
              max: MetronomeSettings.maxBpm.toDouble(),
              divisions: MetronomeSettings.maxBpm - MetronomeSettings.minBpm,
              label: '${s.bpm}',
              onChanged: (v) => controller.setBpm(v.round()),
            ),
            HintText(l.metronomeKeysHint),
          ],
        );
        final meter = WsCard(
          key: const Key('card:meter'),
          children: [
            CardHeader(icon: WsIcons.timer, title: l.meterAndSound),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in MetronomeSettings.meters)
                  BorderedButton(
                    label: MetronomeSettings.meterLabel(m),
                    selected: s.meter == m,
                    onPressed: () => controller.setMeter(m),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sub in _subdivisions)
                  BorderedButton(
                    label: subdivisionLabel(l, sub),
                    selected: s.subdivision == sub,
                    onPressed: () => controller.setSubdivision(sub),
                  ),
              ],
            ),
            Row(
              children: [
                const Icon(WsIcons.speaker2, size: 18),
                Expanded(
                  child: Slider(
                    value: s.volume,
                    onChanged: controller.setVolume,
                    label: l.percent((s.volume * 100).round()),
                    divisions: 100,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    l.percent((s.volume * 100).round()),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ],
        );
        final ramp = WsCard(
          key: const Key('card:ramp'),
          children: [
            CardHeader(
              icon: WsIcons.speedometer,
              title: l.autoTempoRamp,
              value: s.rampEnabled,
              onChanged: (v) => controller.setRamp(enabled: v),
              trailing: narrow ? null : rampMode,
            ),
            // #115: on the phone the title keeps the whole line, «Bars | Time» goes below it
            if (narrow) Align(alignment: Alignment.centerLeft, child: rampMode),
            Dimmed(
              enabled: s.rampEnabled,
              child: _RampSettings(controller: controller, settings: s),
            ),
            HintText(s.rampByTime ? l.rampByTimeHint : l.rampByBarsHint),
          ],
        );
        Widget column(List<Widget> cards) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: cards,
        );
        if (size != WsSize.desktop) return column([tempo, meter, ramp]);
        return Row(
          key: const Key('metronomeColumns'),
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            Expanded(child: column([tempo, meter])),
            Expanded(child: ramp),
          ],
        );
      },
    );
  }
}

/// Umschalter «Takte» / «Zeit» der Auto-Steigerung (#23).
class _RampMode extends StatelessWidget {
  const _RampMode({required this.controller, required this.byTime});

  final MetronomeController controller;
  final bool byTime;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(width: 8),
      BorderedButton(
        key: const Key('rampMode:bars'),
        label: context.l10n.bars,
        selected: !byTime,
        onPressed: () => controller.setRamp(byTime: false),
      ),
      const SizedBox(width: 4),
      BorderedButton(
        key: const Key('rampMode:time'),
        label: context.l10n.time,
        selected: byTime,
        onPressed: () => controller.setRamp(byTime: true),
      ),
    ],
  );
}

class _RampSettings extends StatelessWidget {
  const _RampSettings({required this.controller, required this.settings});

  final MetronomeController controller;
  final MetronomeSettings settings;

  Widget _stepper(
    String label,
    int value,
    void Function(int) set, {
    int step = 1,
  }) => Row(
    children: [
      Expanded(child: Text(label)),
      RepeatButton(icon: Icons.remove, onStep: () => set(value - step)),
      SizedBox(width: 56, child: Text('$value', textAlign: TextAlign.center)),
      RepeatButton(icon: Icons.add, onStep: () => set(value + step)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final l = context.l10n;
    return Column(
      children: [
        _stepper(l.startBpm, s.rampStart, (v) => controller.setRamp(start: v)),
        _stepper(
          l.targetBpm,
          s.rampTarget,
          (v) => controller.setRamp(target: v),
        ),
        if (s.rampByTime)
          _stepper(
            l.durationMinutes,
            s.rampMinutes,
            (v) => controller.setRamp(minutes: v),
          )
        else ...[
          Row(
            children: [
              Expanded(child: Text(l.step)),
              DropdownButton<int>(
                value: s.rampStep,
                items: [
                  for (final st in MetronomeSettings.rampSteps)
                    DropdownMenuItem(value: st, child: Text(l.bpmStep(st))),
                ],
                onChanged: (v) => controller.setRamp(step: v),
              ),
            ],
          ),
          _stepper(
            l.everyBars,
            s.rampEveryBars,
            (v) => controller.setRamp(everyBars: v),
          ),
        ],
      ],
    );
  }
}
