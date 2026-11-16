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
                ),
                Dimmed(
                  enabled: s.rampEnabled,
                  child: _RampSettings(controller: controller, settings: s),
                ),
                const HintText(
                  'Das Tempo steigt jeweils am Taktanfang. Ist das Ziel erreicht, '
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
    );
  }
}
