import 'package:material_ui/material_ui.dart';

import 'metronome_controller.dart';
import 'metronome_settings.dart';
import '../ui/messages.dart';
import '../ui/style.dart';
import 'repeat_button.dart';

/// Bedienfeld des Metronoms in Karten wie der Player-Reiter (#19).
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
        final theme = Theme.of(context);
        final l = context.l10n;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            WsCard(
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
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
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
                  divisions:
                      MetronomeSettings.maxBpm - MetronomeSettings.minBpm,
                  label: '${s.bpm}',
                  onChanged: (v) => controller.setBpm(v.round()),
                ),
                HintText(l.metronomeKeysHint),
              ],
            ),
            WsCard(
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
            ),
            WsCard(
              key: const Key('card:ramp'),
              children: [
                CardHeader(
                  icon: WsIcons.speedometer,
                  title: l.autoTempoRamp,
                  value: s.rampEnabled,
                  onChanged: (v) => controller.setRamp(enabled: v),
                  trailing: _RampMode(
                    controller: controller,
                    byTime: s.rampByTime,
                  ),
                ),
                Dimmed(
                  enabled: s.rampEnabled,
                  child: _RampSettings(controller: controller, settings: s),
                ),
                HintText(s.rampByTime ? l.rampByTimeHint : l.rampByBarsHint),
              ],
            ),
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

/// Modul «Metronom» im Übe-Bildschirm (#30): BPM in Blau, Start/Stopp, −/+, Tap; alle Einstellungen
/// öffnen sich als Dialog (Desktop/Tablet) bzw. als Blatt von unten (Phone).
class MetronomeModule extends StatelessWidget {
  const MetronomeModule({super.key, required this.controller});

  final MetronomeController controller;

  void _openSettings(BuildContext context) {
    final m = WsLayout.of(context);
    Widget panel(BuildContext context) => WsLayout(
      metrics: m,
      child: ExcludeFocus(child: MetronomePanel(controller: controller)),
    );
    if (m.size == WsSize.phone) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (context, scroll) => SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.all(WsSpace.l),
            child: panel(context),
          ),
        ),
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(WsSpace.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: WsSpace.m,
                children: [
                  panel(context),
                  Align(
                    alignment: Alignment.centerRight,
                    child: BorderedButton(
                      key: const Key('metronomeSettingsClose'),
                      label: context.l10n.done,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final ws = WsTheme.of(context);
        final m = WsLayout.of(context);
        final s = controller.settings;
        final l = context.l10n;
        final ramp = s.rampEnabled
            ? s.rampByTime
                  ? l.moduleRampTime(s.rampStart, s.rampTarget, s.rampMinutes)
                  : l.moduleRampBars(s.rampStep, s.rampEveryBars)
            : null;
        final bpm = Text(
          '${s.bpm}',
          key: const Key('moduleBpm'),
          style: ws.number(m.bpm, color: ws.blue),
        );
        final details = Text(
          l.moduleDetails(
            MetronomeSettings.meterLabel(s.meter),
            subdivisionLabel(l, s.subdivision),
          ),
          style: TextStyle(color: ws.muted, fontSize: m.body),
        );
        final toggle = BorderedButton(
          key: const Key('moduleMetronomeToggle'),
          label: controller.running ? l.stop : l.start,
          icon: controller.running ? WsIcons.stop : WsIcons.play,
          iconOnly: true,
          selected: controller.running,
          onPressed: controller.toggle,
        );
        final controls = Row(
          spacing: WsSpace.s,
          children: [
            RepeatButton(
              icon: Icons.remove,
              tooltip: l.slower,
              onStep: () => controller.changeBpm(-1),
            ),
            RepeatButton(
              icon: Icons.add,
              tooltip: l.faster,
              onStep: () => controller.changeBpm(1),
            ),
            Expanded(
              child: BorderedButton(
                key: const Key('moduleTap'),
                label: l.tap,
                expand: true,
                onPressed: controller.tap,
              ),
            ),
            toggle,
            BorderedButton(
              key: const Key('metronomeSettings'),
              label: l.settings,
              icon: WsIcons.slider,
              iconOnly: true,
              onPressed: () => _openSettings(context),
            ),
          ],
        );
        return WsCard(
          key: const Key('module:metronome'),
          children: [
            CardHeader(
              title: l.metronome,
              trailing: const ShortcutBadge('M · T · ↑↓'),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              spacing: WsSpace.m,
              children: [
                bpm,
                Expanded(child: details),
              ],
            ),
            controls,
            if (ramp != null)
              Text(
                ramp,
                key: const Key('moduleRamp'),
                style: TextStyle(color: ws.blue, fontSize: 12),
              ),
          ],
        );
      },
    );
  }
}
