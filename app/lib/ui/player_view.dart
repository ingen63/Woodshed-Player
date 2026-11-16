// Reiter «Player» im Stil der alten App (FEA-19, Vorlage WoodshedPlayer/Views/PlayerView.swift).
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../time_format.dart';
import 'style.dart';

/// Zustand, den der Player-Reiter anzeigt.
class PlayerViewState {
  const PlayerViewState({
    this.title,
    this.position = 0,
    this.duration = 0,
    this.playing = false,
    this.volume = 1,
    this.speedOn = false,
    this.speed = 1,
    this.loopOn = false,
    this.loopStart = 0,
    this.loopEnd = 0,
    this.error,
  });

  final String? title;
  final double position, duration, volume, speed, loopStart, loopEnd;
  final bool playing, speedOn, loopOn;
  final String? error;

  bool get loaded => title != null && duration > 0;

  /// Der Loop gilt erst, wenn das Ende mindestens 1 s nach dem Anfang liegt.
  bool get loopValid => loopEnd >= loopStart + 1;
}

/// Aktionen des Player-Reiters.
class PlayerViewActions {
  const PlayerViewActions({
    required this.open,
    required this.playPause,
    required this.seek,
    required this.volume,
    required this.speedOn,
    required this.speed,
    required this.loopOn,
    required this.loopStart,
    required this.loopEnd,
  });

  final VoidCallback open, playPause;
  final ValueChanged<double> seek, volume, speed, loopStart, loopEnd;
  final ValueChanged<bool> speedOn, loopOn;
}

class PlayerView extends StatelessWidget {
  const PlayerView({
    super.key,
    required this.state,
    required this.actions,
    this.extraCards = const [],
  });

  final PlayerViewState state;
  final PlayerViewActions actions;

  /// Weitere Karten am Ende, z. B. die Aufnahme (nur macOS).
  final List<Widget> extraCards;

  @override
  Widget build(BuildContext context) {
    return AccentBackground(
      child: CardColumn(
        children: [
          if (state.error != null) _ErrorCard(state.error!),
          if (state.loaded) ...[
            _NowPlayingCard(state: state, actions: actions),
            _SpeedCard(state: state, actions: actions),
            _LoopCard(state: state, actions: actions),
          ] else
            _EmptyCard(onOpen: actions.open),
          ...extraCards,
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return WsCard(
      children: [
        Row(
          children: [
            Icon(WsIcons.warning, color: error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: TextStyle(color: error)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Hinweis ohne geladenen Titel (wie ContentUnavailableView).
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grey = theme.colorScheme.onSurfaceVariant;
    return WsCard(
      key: const Key('card:empty'),
      children: [
        Center(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Icon(WsIcons.musicNote, size: 44, color: grey),
              const SizedBox(height: 10),
              Text(
                'Kein Titel ausgewählt',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                Platform.isMacOS
                    ? 'Öffne eine MP3-, WAV- oder FLAC-Datei oder zieh sie ins Fenster.'
                    : 'Öffne eine MP3-, WAV- oder FLAC-Datei aus «Dateien».',
                textAlign: TextAlign.center,
                style: TextStyle(color: grey),
              ),
              const SizedBox(height: 14),
              BorderedButton(
                key: const Key('openFile'),
                label: 'Datei öffnen',
                icon: WsIcons.folder,
                onPressed: onOpen,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

// MARK: Titel mit Wiedergabe (Aufbau wie der Quick-Look-Player von macOS)

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.state, required this.actions});
  final PlayerViewState state;
  final PlayerViewActions actions;

  @override
  Widget build(BuildContext context) {
    final info = _TrackInfo(title: state.title!, duration: state.duration);
    return WsCard(
      key: const Key('card:nowPlaying'),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _VolumeCapsule(value: state.volume, onChanged: actions.volume),
        ),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 520
              ? Row(
                  children: [
                    const _Artwork(size: 150),
                    const SizedBox(width: 24),
                    Expanded(child: info),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(child: _Artwork(size: 180)),
                    const SizedBox(height: 16),
                    info,
                  ],
                ),
        ),
        _TransportBar(state: state, actions: actions),
      ],
    );
  }
}

/// Platzhalter für das Cover (die Flutter-App liest noch keine Cover).
class _Artwork extends StatelessWidget {
  const _Artwork({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: Container(
      width: size,
      height: size,
      color: Colors.grey.withValues(alpha: 0.15),
      child: Icon(
        WsIcons.musicNote,
        size: size * 0.5,
        color: Colors.grey.withValues(alpha: 0.6),
      ),
    ),
  );
}

class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.title, required this.duration});
  final String title;
  final double duration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          key: const Key('trackTitle'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Dauer: ',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              TextSpan(
                text: formatTime(duration),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          key: const Key('trackDuration'),
        ),
      ],
    );
  }
}

/// Lautstärke als dunkle Kapsel mit weissem Regler.
class _VolumeCapsule extends StatelessWidget {
  const _VolumeCapsule({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  static IconData symbol(double v) => v <= 0
      ? WsIcons.speakerOff
      : v < 0.34
      ? WsIcons.speaker1
      : v < 0.67
      ? WsIcons.speaker2
      : WsIcons.speaker3;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('volume'),
    label: 'Lautstärke',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 110,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                thumbColor: Colors.white,
                overlayShape: SliderComponentShape.noOverlay,
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: ExcludeFocus(
                child: Slider(value: value.clamp(0, 1), onChanged: onChanged),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 22,
            child: Icon(symbol(value), color: Colors.white, size: 18),
          ),
        ],
      ),
    ),
  );
}

/// Dunkle Wiedergabeleiste; einzeilig, bei schmalem Platz zweizeilig.
class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.state, required this.actions});
  final PlayerViewState state;
  final PlayerViewActions actions;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      _barButton(
        WsIcons.back15,
        '15 Sekunden zurück',
        () => actions.seek((state.position - 15).clamp(0, state.duration)),
      ),
      _barButton(
        state.playing ? WsIcons.pause : WsIcons.play,
        state.playing ? 'Pause' : 'Wiedergabe',
        actions.playPause,
        size: 26,
        key: const Key('playPause'),
      ),
      _barButton(
        WsIcons.forward15,
        '15 Sekunden vor',
        () => actions.seek((state.position + 15).clamp(0, state.duration)),
      ),
    ];
    final timeStyle = const TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    Widget timeline() => Row(
      children: [
        Text(formatTime(state.position), style: timeStyle),
        const SizedBox(width: 12),
        Expanded(
          child: ProgressScrubber(
            position: state.position,
            duration: state.duration,
            loop: state.loopOn && state.loopValid
                ? (state.loopStart, state.loopEnd)
                : null,
            onSeek: actions.seek,
          ),
        ),
        const SizedBox(width: 12),
        Text(formatTime(state.duration), style: timeStyle),
      ],
    );
    return Container(
      key: const Key('transportBar'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(24),
      ),
      child: LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 420
            ? Row(
                children: [
                  ...buttons,
                  const SizedBox(width: 6),
                  Expanded(child: timeline()),
                ],
              )
            : Column(
                children: [
                  timeline(),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 28,
                    children: buttons,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _barButton(
    IconData icon,
    String label,
    VoidCallback onPressed, {
    double size = 22,
    Key? key,
  }) => ExcludeFocus(
    child: IconButton(
      key: key,
      onPressed: onPressed,
      tooltip: label,
      color: Colors.white,
      iconSize: size,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, semanticLabel: label),
    ),
  );
}

/// Dünner Fortschrittsbalken mit weissem Knopf; bei aktivem Loop ist sein Bereich orange.
class ProgressScrubber extends StatefulWidget {
  const ProgressScrubber({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.loop,
  });

  final double position, duration;
  final (double, double)? loop;
  final ValueChanged<double> onSeek;

  @override
  State<ProgressScrubber> createState() => _ProgressScrubberState();
}

class _ProgressScrubberState extends State<ProgressScrubber> {
  double? _drag;

  double _timeAt(double x, double width) =>
      width <= 0 ? 0 : (x / width).clamp(0.0, 1.0) * widget.duration;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth, d = widget.duration;
        double xOf(double t) => d > 0 ? w * (t / d).clamp(0.0, 1.0) : 0;
        final x = xOf(_drag ?? widget.position);
        final loop = widget.loop;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (e) =>
              setState(() => _drag = _timeAt(e.localPosition.dx, w)),
          onHorizontalDragUpdate: (e) =>
              setState(() => _drag = _timeAt(e.localPosition.dx, w)),
          onHorizontalDragEnd: (_) {
            if (_drag != null) widget.onSeek(_drag!);
            setState(() => _drag = null);
          },
          onTapUp: (e) => widget.onSeek(_timeAt(e.localPosition.dx, w)),
          child: SizedBox(
            height: 24,
            width: w,
            child: Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.none,
              children: [
                _capsule(w, 5, Colors.white.withValues(alpha: 0.25)),
                _capsule(x, 5, Colors.white.withValues(alpha: 0.7)),
                if (loop != null && d > 0)
                  Positioned(
                    key: const Key('loopRange'),
                    left: xOf(loop.$1),
                    child: _capsule(
                      (xOf(loop.$2) - xOf(loop.$1)).clamp(3, w),
                      9,
                      Colors.orange.withValues(alpha: 0.75),
                    ),
                  ),
                Positioned(
                  left: (x - 11).clamp(0, (w - 22).clamp(0, w)),
                  child: Container(
                    width: 22,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 1.5),
                      ],
                    ),
                  ),
                ),
                if (loop != null && d > 0) ...[
                  _marker(xOf(loop.$1), 'loopStartMarker'),
                  _marker(xOf(loop.$2), 'loopEndMarker'),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _capsule(double width, double height, Color color) => Container(
    width: width < 0 ? 0 : width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );

  Widget _marker(double x, String key) => Positioned(
    key: Key(key),
    left: x - 2,
    child: Container(
      width: 4,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.orange,
        borderRadius: BorderRadius.circular(1.5),
        border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
      ),
    ),
  );
}

// MARK: Geschwindigkeit

class _SpeedCard extends StatelessWidget {
  const _SpeedCard({required this.state, required this.actions});
  final PlayerViewState state;
  final PlayerViewActions actions;

  static const presets = [0.5, 0.7, 0.8, 0.9, 1.0, 1.1];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grey = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return WsCard(
      key: const Key('card:speed'),
      children: [
        CardHeader(
          icon: WsIcons.speedometer,
          title: 'Geschwindigkeit',
          value: state.speedOn,
          onChanged: actions.speedOn,
        ),
        Dimmed(
          key: const Key('dim:speed'),
          enabled: state.speedOn,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('0,1×', style: grey),
                  Expanded(
                    child: ExcludeFocus(
                      child: Slider(
                        value: state.speed.clamp(0.1, 2.0),
                        min: 0.1,
                        max: 2.0,
                        onChanged: (v) => actions.speed((v * 20).round() / 20),
                      ),
                    ),
                  ),
                  Text('2×', style: grey),
                  SizedBox(
                    width: 70,
                    child: Text(
                      formatRate(state.speed),
                      key: const Key('speedValue'),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in presets)
                    BorderedButton(
                      key: Key('preset:$p'),
                      label: formatRate(p),
                      selected: (state.speed - p).abs() < 0.001,
                      onPressed: () => actions.speed(p),
                    ),
                ],
              ),
            ],
          ),
        ),
        const HintText(
          'Die Tonhöhe bleibt unverändert. Geschwindigkeit in 0,05er-Schritten.',
        ),
      ],
    );
  }
}

// MARK: Loop

class _LoopCard extends StatelessWidget {
  const _LoopCard({required this.state, required this.actions});
  final PlayerViewState state;
  final PlayerViewActions actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    Widget row(
      String name,
      double value,
      ValueChanged<double> set,
      String help,
    ) => LayoutBuilder(
      builder: (context, c) => Row(
        children: [
          SizedBox(width: 64, child: Text(name, style: label)),
          TimeField(key: Key('time:$name'), value: value, onCommit: set),
          const SizedBox(width: 12),
          BorderedButton(
            label: 'Aktuelle Position',
            icon: WsIcons.location,
            tooltip: help,
            iconOnly: c.maxWidth < 360, // schmal: nur das Symbol
            onPressed: () => set(state.position),
          ),
        ],
      ),
    );
    return WsCard(
      key: const Key('card:loop'),
      children: [
        CardHeader(
          icon: WsIcons.repeat,
          title: 'Loop',
          value: state.loopOn,
          onChanged: actions.loopOn,
        ),
        Dimmed(
          key: const Key('dim:loop'),
          enabled: state.loopOn,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row(
                'Anfang',
                state.loopStart,
                actions.loopStart,
                'Aktuelle Wiedergabeposition als Anfang übernehmen',
              ),
              const SizedBox(height: 10),
              row(
                'Ende',
                state.loopEnd,
                actions.loopEnd,
                'Aktuelle Wiedergabeposition als Ende übernehmen',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  BorderedButton(
                    label: 'Zum Loop-Anfang',
                    icon: WsIcons.backwardEnd,
                    onPressed: () => actions.seek(state.loopStart),
                  ),
                  BorderedButton(
                    label: 'Ganzer Titel',
                    icon: WsIcons.leftRight,
                    onPressed: () {
                      actions.loopStart(0);
                      actions.loopEnd(state.duration);
                    },
                  ),
                ],
              ),
              if (state.loopOn && !state.loopValid) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(WsIcons.warning, size: 14, color: Colors.orange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Das Ende muss mindestens 1 Sekunde nach dem Anfang liegen.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const HintText(
          'Format: mm:ss, z. B. 01:23 – Zehntelsekunden mit Punkt, z. B. 01:23.5. '
          'Leertaste = Play/Pause.',
        ),
      ],
    );
  }
}

/// Zeitfeld (mm:ss); übernimmt bei Return oder wenn der Fokus geht.
class TimeField extends StatefulWidget {
  const TimeField({super.key, required this.value, required this.onCommit});
  final double value;
  final ValueChanged<double> onCommit;

  @override
  State<TimeField> createState() => _TimeFieldState();
}

class _TimeFieldState extends State<TimeField> {
  late final _text = TextEditingController(text: formatTimeField(widget.value));
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(TimeField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) {
      _text.text = formatTimeField(widget.value);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = parseTime(_text.text);
    if (parsed != null) {
      widget.onCommit(parsed);
      _text.text = formatTimeField(parsed);
    } else {
      _text.text = formatTimeField(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 96,
    child: TextField(
      controller: _text,
      focusNode: _focus,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      decoration: const InputDecoration(
        isDense: true,
        hintText: 'mm:ss',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      // Return übernimmt und gibt den Fokus an die Tastenkürzel zurück.
      onSubmitted: (_) => _focus.unfocus(
        disposition: UnfocusDisposition.previouslyFocusedChild,
      ),
    ),
  );
}
