import 'package:material_ui/material_ui.dart';

import 'metronome_controller.dart';
import 'metronome_settings.dart';
import '../ui/style.dart';
import 'repeat_button.dart';

/// Bedienfeld des Metronoms in Karten wie der Player-Reiter (#19).
class MetronomePanel extends StatelessWidget {
  const MetronomePanel({super.key, required this.controller});

  final MetronomeController controller;

  static const _subdivisions = {
    1: 'Viertel',
    2: 'Achtel',
    3: 'Triolen',
    4: 'Sechzehntel',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.settings;
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            WsCard(
              key: const Key('card:metronome'),
              children: [
                CardHeader(
                  icon: WsIcons.metronome,
                  title: 'Metronom',
                  trailing: ExcludeFocus(
                    child: FilledButton.icon(
                      key: const Key('metronomeToggle'),
                      onPressed: controller.toggle,
                      icon: Icon(
                        controller.running ? WsIcons.stop : WsIcons.play,
                        size: 16,
                      ),
                      label: Text(
                        controller.running ? 'Stopp (M)' : 'Start (M)',
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    RepeatButton(
                      icon: Icons.remove,
                      tooltip: 'Langsamer (↓)',
                      onStep: () => controller.changeBpm(-1),
                    ),
                    Expanded(
                      child: Text(
                        '${s.bpm} BPM',
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
                      tooltip: 'Schneller (↑)',
                      onStep: () => controller.changeBpm(1),
                    ),
                    const SizedBox(width: 8),
                    BorderedButton(label: 'Tap (T)', onPressed: controller.tap),
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
                const HintText(
                  'Tasten: M = Start/Stopp, ↑ / ↓ = Tempo ±1 (mit Shift ±10), T = Tap-Tempo. '
                  'Titel und Metronom laufen nie gleichzeitig.',
                ),
              ],
            ),
            WsCard(
              key: const Key('card:meter'),
              children: [
                const CardHeader(icon: WsIcons.timer, title: 'Takt und Klang'),
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
                    for (final e in _subdivisions.entries)
                      BorderedButton(
                        label: e.value,
                        selected: s.subdivision == e.key,
                        onPressed: () => controller.setSubdivision(e.key),
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
                        label: '${(s.volume * 100).round()} %',
                        divisions: 100,
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${(s.volume * 100).round()} %',
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
                  title: 'Automatische Tempo-Steigerung',
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
                HintText(
                  s.rampByTime
                      ? 'Das Tempo ändert sich in 1-BPM-Schritten gleichmässig über die Dauer, '
                            'jeweils am Taktanfang. Ist das Ziel erreicht, bleibt es einen Schritt lang '
                            'und beginnt dann wieder beim Start-BPM.'
                      : 'Das Tempo steigt jeweils am Taktanfang. Ist das Ziel erreicht, '
                            'bleibt es gleich viele Takte und beginnt dann wieder beim Start-BPM.',
                ),
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
        label: 'Takte',
        selected: !byTime,
        onPressed: () => controller.setRamp(byTime: false),
      ),
      const SizedBox(width: 4),
      BorderedButton(
        key: const Key('rampMode:time'),
        label: 'Zeit',
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
    return Column(
      children: [
        _stepper('Start-BPM', s.rampStart, (v) => controller.setRamp(start: v)),
        _stepper(
          'Ziel-BPM',
          s.rampTarget,
          (v) => controller.setRamp(target: v),
        ),
        if (s.rampByTime)
          _stepper(
            'Dauer (Minuten)',
            s.rampMinutes,
            (v) => controller.setRamp(minutes: v),
          )
        else ...[
          Row(
            children: [
              const Expanded(child: Text('Schritt')),
              DropdownButton<int>(
                value: s.rampStep,
                items: [
                  for (final st in MetronomeSettings.rampSteps)
                    DropdownMenuItem(value: st, child: Text('+$st BPM')),
                ],
                onChanged: (v) => controller.setRamp(step: v),
              ),
            ],
          ),
          _stepper(
            'Alle … Takte',
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
                      label: 'Fertig',
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
        final sub = MetronomePanel._subdivisions[s.subdivision] ?? '';
        final ramp = s.rampEnabled
            ? s.rampByTime
                  ? 'Auto ${s.rampStart}→${s.rampTarget} BPM in ${s.rampMinutes} min'
                  : 'Auto +${s.rampStep} BPM / ${s.rampEveryBars} Takte'
            : null;
        final bpm = Text(
          '${s.bpm}',
          key: const Key('moduleBpm'),
          style: ws.number(m.bpm, color: ws.blue),
        );
        final details = Text(
          'BPM · ${MetronomeSettings.meterLabel(s.meter)} · $sub',
          style: TextStyle(color: ws.muted, fontSize: m.body),
        );
        final toggle = BorderedButton(
          key: const Key('moduleMetronomeToggle'),
          label: controller.running ? 'Stopp' : 'Start',
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
              tooltip: 'Langsamer (↓)',
              onStep: () => controller.changeBpm(-1),
            ),
            RepeatButton(
              icon: Icons.add,
              tooltip: 'Schneller (↑)',
              onStep: () => controller.changeBpm(1),
            ),
            Expanded(
              child: BorderedButton(
                key: const Key('moduleTap'),
                label: 'Tap',
                expand: true,
                onPressed: controller.tap,
              ),
            ),
            toggle,
            BorderedButton(
              key: const Key('metronomeSettings'),
              label: 'Einstellungen',
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
              title: 'Metronom',
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
