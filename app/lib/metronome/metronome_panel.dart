import 'package:material_ui/material_ui.dart';

import 'metronome_controller.dart';
import 'metronome_settings.dart';
import 'repeat_button.dart';

/// Bedienfeld des Metronoms (ohne eigene Gestaltung des Metronom-Projekts).
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Metronom', style: theme.textTheme.titleMedium),
                const Spacer(),
                FilledButton.icon(
                  key: const Key('metronomeToggle'),
                  onPressed: controller.toggle,
                  icon: Icon(
                    controller.running ? Icons.stop : Icons.play_arrow,
                  ),
                  label: Text(controller.running ? 'Stopp (M)' : 'Start (M)'),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                RepeatButton(
                  icon: Icons.add,
                  tooltip: 'Schneller (↑)',
                  onStep: () => controller.changeBpm(1),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: controller.tap,
                  child: const Text('Tap (T)'),
                ),
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
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final m in MetronomeSettings.meters)
                  ChoiceChip(
                    label: Text(MetronomeSettings.meterLabel(m)),
                    selected: s.meter == m,
                    onSelected: (_) => controller.setMeter(m),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in _subdivisions.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: s.subdivision == e.key,
                    onSelected: (_) => controller.setSubdivision(e.key),
                  ),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.volume_down),
                Expanded(
                  child: Slider(
                    value: s.volume,
                    onChanged: controller.setVolume,
                    label: '${(s.volume * 100).round()} %',
                    divisions: 100,
                  ),
                ),
                Text('${(s.volume * 100).round()} %'),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Automatische Tempo-Steigerung'),
              value: s.rampEnabled,
              onChanged: (v) => controller.setRamp(enabled: v),
            ),
            if (s.rampEnabled)
              _RampSettings(controller: controller, settings: s),
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
