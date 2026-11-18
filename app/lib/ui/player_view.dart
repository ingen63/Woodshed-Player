// Übe-Bildschirm im Design «Studio» (#30, docs/design/A-*.dc.html): Kopf mit Titel und Zeit,
// Zeitleiste (Wellenform), Loop-Leiste, Module Tempo · Steigerung · Metronom und Wiedergabe.
// Desktop: drei Module nebeneinander; Tablet: zwei Spalten; Phone: einspaltig, S/Play/E unten.
import 'dart:io';
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../library/playback_settings.dart';
import '../metronome/repeat_button.dart';
import '../time_format.dart';
import 'library_view.dart' show TrackArtwork;
import 'style.dart';
import 'timeline.dart';

export 'timeline.dart' show ProgressScrubber, Timeline, WaveformQuery;

/// Zustand, den der Übe-Bildschirm anzeigt.
class PlayerViewState {
  const PlayerViewState({
    this.title,
    this.artist,
    this.artwork,
    this.position = 0,
    this.duration = 0,
    this.playing = false,
    this.volume = 1,
    this.speedOn = false,
    this.speed = 1,
    this.loopOn = false,
    this.loopStart = 0,
    this.loopEnd = 0,
    this.ramp = const PlaybackSettings(),
    this.rampLabel = '',
    this.rampPasses = 0,
    this.error,
    this.waveform,
    this.trackKey,
  });

  final String? title;
  final String? artist;

  /// Pfad zum Cover oder null.
  final String? artwork;
  final double position, duration, volume, speed, loopStart, loopEnd;
  final bool playing, speedOn, loopOn;

  /// Einstellungen der Steigerung nach Loop-Durchgängen (#29), nur die `ramp*`-Felder gelten.
  final PlaybackSettings ramp;

  /// Stufe und Durchgänge, z. B. «75 % · 7 von 10».
  final String rampLabel;

  /// Durchgänge auf der aktuellen Stufe (#29).
  final int rampPasses;
  final String? error;

  /// Wellenform des Titels (#28); ohne sie zeigt die Zeitleiste einen Fortschrittsbalken.
  final WaveformQuery? waveform;

  /// Kennung des Titels (z. B. Pfad), damit die Zeitleiste die Wellenform neu holt.
  final Object? trackKey;

  bool get loaded => title != null && duration > 0;

  /// Der Loop gilt erst, wenn das Ende mindestens 1 s nach dem Anfang liegt.
  bool get loopValid => loopEnd >= loopStart + 1;

  (double, double)? get activeLoop =>
      loopOn && loopValid ? (loopStart, loopEnd) : null;

  /// Zählt die Steigerung gerade? Nur mit Geschwindigkeit und aktivem Loop (#29).
  bool get rampCounting => ramp.rampEnabled && speedOn && activeLoop != null;
}

/// Ändert einzelne Einstellungen der Steigerung nach Loop-Durchgängen (#29).
typedef RampChange = void Function({
  bool? enabled,
  int? start,
  int? target,
  int? step,
  int? passes,
});

/// Aktionen des Übe-Bildschirms.
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
    ValueChanged<double>? loopStartField,
    ValueChanged<double>? loopEndField,
    this._wholeTrack,
    this.ramp,
  }) : loopStartField = loopStartField ?? loopStart,
       loopEndField = loopEndField ?? loopEnd;

  final VoidCallback open, playPause;
  final ValueChanged<double> seek, volume, speed;

  /// Grenze setzen und Loop einschalten (Marker, «S hier»/«E hier», Tasten S/E).
  final ValueChanged<double> loopStart, loopEnd;

  /// Grenze aus dem Zeitfeld; schaltet den Loop nicht ein (wie in der Swift-App).
  final ValueChanged<double> loopStartField, loopEndField;
  final VoidCallback? _wholeTrack;
  final ValueChanged<bool> speedOn, loopOn;

  /// Steigerung nach Loop-Durchgängen (#29) einstellen.
  final RampChange? ramp;

  void wholeTrack(double duration) {
    if (_wholeTrack != null) return _wholeTrack();
    loopStartField(0);
    loopEndField(duration);
  }
}

class PlayerView extends StatelessWidget {
  const PlayerView({
    super.key,
    required this.state,
    required this.actions,
    this.extraCards = const [],
    this.metronome,
    this.leading,
    this.headerTrailing,
  });

  final PlayerViewState state;
  final PlayerViewActions actions;

  /// Weitere Module am Ende.
  final List<Widget> extraCards;

  /// Metronom-Modul (drittes Modul am Desktop).
  final Widget? metronome;

  /// Links im Kopf: Bibliothek einblenden (Tablet) bzw. zurück zur Bibliothek (Phone).
  final Widget? leading;

  /// Rechts im Kopf, z. B. der Aufnahme-Knopf.
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    final m = WsLayout.of(context);
    final s = state;
    final header = _Header(
      state: s,
      leading: leading,
      trailing: headerTrailing,
    );
    final top = <Widget>[header, if (s.error != null) _ErrorCard(s.error!)];
    if (!s.loaded) {
      return CardColumn(
        children: [
          ...top,
          _EmptyCard(onOpen: actions.open),
          ?metronome,
          ...extraCards,
        ],
      );
    }
    final timeline = WsPanel(
      key: const Key('card:timeline'),
      padding: EdgeInsets.fromLTRB(
        m.touch ? 14 : 12,
        10,
        m.touch ? 14 : 12,
        m.touch ? 18 : 10,
      ),
      child: Timeline(
        position: s.position,
        duration: s.duration,
        loop: s.activeLoop,
        onSeek: actions.seek,
        onLoopStart: actions.loopStart,
        onLoopEnd: actions.loopEnd,
        waveform: s.waveform,
        trackKey: s.trackKey,
      ),
    );
    final loop = _LoopBar(state: s, actions: actions);
    final tempo = _TempoModule(state: s, actions: actions);
    final ramp = actions.ramp == null
        ? null
        : _RampModule(state: s, change: actions.ramp!);
    final transport = _Transport(state: s, actions: actions);

    switch (m.size) {
      case WsSize.desktop:
        return CardColumn(
          children: [
            ...top,
            timeline,
            loop,
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: m.gap,
                children: [
                  Expanded(child: tempo),
                  if (ramp != null) Expanded(child: ramp),
                  if (metronome != null) Expanded(child: metronome!),
                ],
              ),
            ),
            transport,
            ...extraCards,
          ],
        );
      case WsSize.tablet:
        return CardColumn(
          children: [
            ...top,
            timeline,
            loop,
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: m.gap,
                children: [
                  Expanded(child: tempo),
                  if (ramp != null) Expanded(child: ramp),
                ],
              ),
            ),
            ?metronome,
            transport,
            ...extraCards,
          ],
        );
      case WsSize.phone:
        return Column(
          children: [
            Expanded(
              child: CardColumn(
                children: [
                  ...top,
                  timeline,
                  loop,
                  tempo,
                  ?ramp,
                  ?metronome,
                  transport,
                  ...extraCards,
                ],
              ),
            ),
            _ThumbBar(state: s, actions: actions),
          ],
        );
    }
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    return WsPanel(
      child: Row(
        spacing: WsSpace.s,
        children: [
          Icon(WsIcons.warning, color: ws.record, size: 18),
          Expanded(
            child: Text(message, style: TextStyle(color: ws.record)),
          ),
        ],
      ),
    );
  }
}

/// Hinweis ohne geladenen Titel.
class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    return WsPanel(
      key: const Key('card:empty'),
      child: Column(
        spacing: WsSpace.s,
        children: [
          const SizedBox(height: WsSpace.s),
          Icon(WsIcons.musicNote, size: 44, color: ws.muted),
          Text(
            'Kein Titel ausgewählt',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: ws.text,
            ),
          ),
          Text(
            Platform.isMacOS
                ? 'Öffne eine MP3-, WAV- oder FLAC-Datei oder zieh sie ins Fenster.'
                : 'Öffne eine MP3-, WAV- oder FLAC-Datei aus «Dateien».',
            textAlign: TextAlign.center,
            style: TextStyle(color: ws.muted),
          ),
          const SizedBox(height: WsSpace.xs),
          BorderedButton(
            key: const Key('openFile'),
            label: 'Datei öffnen',
            icon: WsIcons.folder,
            onPressed: onOpen,
            shortcut: const ShortcutBadge('O', command: true),
          ),
          const SizedBox(height: WsSpace.s),
        ],
      ),
    );
  }
}

// MARK: Kopf

class _Header extends StatelessWidget {
  const _Header({required this.state, this.leading, this.trailing});
  final PlayerViewState state;
  final Widget? leading, trailing;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    final s = state;
    final subtitle = [
      if (s.artist != null) s.artist!,
      if (s.loaded) formatTime(s.duration),
    ].join(' · ');
    final titleSize = m.size == WsSize.desktop ? 20.0 : 17.0;
    final info = Column(
      crossAxisAlignment: m.size == WsSize.tablet
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          s.title ?? 'Woodshed Player',
          key: s.title == null ? null : const Key('trackTitle'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w600,
            color: ws.text,
          ),
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            key: const Key('trackSubtitle'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: m.body - 1, color: ws.muted),
          ),
      ],
    );
    final clock = s.loaded
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(text: formatTimePrecise(s.position)),
                if (m.size == WsSize.desktop)
                  TextSpan(
                    text: ' / ${formatTimePrecise(s.duration)}',
                    style: ws.number(m.clock * 0.72, color: ws.muted),
                  ),
              ],
            ),
            key: const Key('clock'),
            style: ws.number(m.clock),
          )
        : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: WsSpace.m,
      children: [
        ?leading,
        if (s.loaded && m.size == WsSize.desktop)
          TrackArtwork(path: s.artwork, size: 40),
        Expanded(child: info),
        ?clock,
        ?trailing,
      ],
    );
  }
}

// MARK: Loop

class _LoopBar extends StatelessWidget {
  const _LoopBar({required this.state, required this.actions});
  final PlayerViewState state;
  final PlayerViewActions actions;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    final s = state;
    final times = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: WsSpace.xs,
      children: [
        TimeField(
          key: const Key('time:Anfang'),
          value: s.loopStart,
          onCommit: actions.loopStartField,
          precise: true,
          fontSize: m.loopTimes,
        ),
        Text('→', style: ws.number(m.loopTimes)),
        TimeField(
          key: const Key('time:Ende'),
          value: s.loopEnd,
          onCommit: actions.loopEndField,
          precise: true,
          fontSize: m.loopTimes,
        ),
      ],
    );
    final length = (s.loopEnd - s.loopStart).clamp(0, double.infinity);
    final info = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${length.toStringAsFixed(1).replaceAll('.', ',')} s'),
          if (s.rampCounting) ...[
            const TextSpan(text: ' · Durchgang '),
            TextSpan(
              text: '${s.rampPasses}',
              style: TextStyle(color: ws.text, fontWeight: FontWeight.w700),
            ),
            TextSpan(text: ' von ${s.ramp.rampPasses}'),
          ],
        ],
      ),
      key: const Key('loopInfo'),
      style: TextStyle(color: ws.muted, fontSize: m.body),
    );
    final toggle = BorderedButton(
      key: const Key('loopToggle'),
      label: s.loopOn ? 'Loop an' : 'Loop aus',
      selected: s.loopOn,
      onPressed: () => actions.loopOn(!s.loopOn),
      shortcut: null,
    );
    final here = [
      BorderedButton(
        key: const Key('here:Anfang'),
        label: 'S hier',
        tooltip: 'Aktuelle Wiedergabeposition als Anfang übernehmen',
        onPressed: () => actions.loopStart(s.position),
        shortcut: const ShortcutBadge('S'),
        expand: m.touch,
      ),
      BorderedButton(
        key: const Key('here:Ende'),
        label: 'E hier',
        tooltip: 'Aktuelle Wiedergabeposition als Ende übernehmen',
        onPressed: () => actions.loopEnd(s.position),
        shortcut: const ShortcutBadge('E'),
        expand: m.touch,
      ),
    ];
    final extra = [
      BorderedButton(
        key: const Key('toLoopStart'),
        label: 'Zum Loop-Anfang',
        icon: WsIcons.backwardEnd,
        iconOnly: true,
        onPressed: () => actions.seek(s.loopStart),
      ),
      BorderedButton(
        key: const Key('wholeTrack'),
        label: 'Ganzer Titel',
        icon: WsIcons.leftRight,
        onPressed: () => actions.wholeTrack(s.duration),
      ),
    ];
    final warning = s.loopOn && !s.loopValid
        ? Row(
            spacing: 6,
            children: [
              Icon(WsIcons.warning, size: 14, color: ws.amber),
              Expanded(
                child: Text(
                  'Das Ende muss mindestens 1 Sekunde nach dem Anfang liegen.',
                  style: TextStyle(fontSize: 12, color: ws.amber),
                ),
              ),
            ],
          )
        : null;
    final label = Text('LOOP', style: ws.label(color: ws.amber));

    final Widget content;
    switch (m.size) {
      case WsSize.desktop:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WsSpace.s,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: WsSpace.l,
              runSpacing: WsSpace.s,
              children: [
                label,
                times,
                info,
                Wrap(
                  spacing: WsSpace.s,
                  runSpacing: WsSpace.s,
                  children: [...here, ...extra, toggle],
                ),
              ],
            ),
            ?warning,
          ],
        );
      case WsSize.tablet:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WsSpace.m,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: WsSpace.m,
              runSpacing: WsSpace.s,
              children: [label, times, info],
            ),
            Row(
              spacing: 10,
              children: [
                for (final b in [...here, toggle]) Expanded(child: b),
              ],
            ),
            Wrap(spacing: WsSpace.s, runSpacing: WsSpace.s, children: extra),
            ?warning,
          ],
        );
      case WsSize.phone:
        // S hier / E hier liegen unten in Daumenreichweite (_ThumbBar).
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WsSpace.s,
          children: [
            Row(
              spacing: WsSpace.s,
              children: [
                label,
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: times,
                  ),
                ),
              ],
            ),
            info,
            Wrap(
              spacing: WsSpace.s,
              runSpacing: WsSpace.s,
              children: [...extra, toggle],
            ),
            ?warning,
          ],
        );
    }
    return WsPanel(key: const Key('card:loop'), child: content);
  }
}

// MARK: Tempo

class _TempoModule extends StatelessWidget {
  const _TempoModule({required this.state, required this.actions});
  final PlayerViewState state;
  final PlayerViewActions actions;

  /// Schnellwahl (#30/AK7).
  static const presets = [0.5, 0.75, 0.8, 1.0];

  static String presetLabel(double p) {
    final t = p.toString();
    return t.replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    final s = state;
    return WsCard(
      key: const Key('card:speed'),
      children: [
        CardHeader(
          title: 'Tempo',
          tooltip: 'Die Tonhöhe bleibt unverändert.',
          value: s.speedOn,
          onChanged: actions.speedOn,
          trailing: const Padding(
            padding: EdgeInsets.only(right: WsSpace.s),
            child: ShortcutBadge('← →'),
          ),
        ),
        Dimmed(
          key: const Key('dim:speed'),
          enabled: s.speedOn,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WsSpace.m,
            children: [
              Text(
                formatRate(s.speed),
                key: const Key('speedValue'),
                style: ws.number(m.tempo, color: ws.amber),
              ),
              SizedBox(
                height: m.touch ? m.target : 24,
                child: ExcludeFocus(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: m.touch ? 6 : 4,
                      thumbShape: RoundSliderThumbShape(
                        enabledThumbRadius: m.touch ? 13 : 8,
                      ),
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      key: const Key('speedSlider'),
                      value: s.speed.clamp(0.1, 2.0),
                      min: 0.1,
                      max: 2.0,
                      onChanged: (v) => actions.speed((v * 20).round() / 20),
                    ),
                  ),
                ),
              ),
              Row(
                spacing: m.touch ? 8 : 6,
                children: [
                  for (final p in presets)
                    Expanded(
                      child: BorderedButton(
                        key: Key('preset:$p'),
                        label: presetLabel(p),
                        mono: true,
                        expand: true,
                        selected: (s.speed - p).abs() < 0.001,
                        onPressed: () => actions.speed(p),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// MARK: Steigerung nach Durchgängen (#29)

/// Stufen von [PlaybackSettings.rampStart] bis [PlaybackSettings.rampTarget] in Prozent.
List<int> rampLadder(PlaybackSettings r) {
  final out = <int>[];
  for (var p = r.rampStart; p < r.rampTarget; p += r.rampStep) {
    out.add(p);
  }
  out.add(r.rampTarget);
  return out;
}

class _RampModule extends StatefulWidget {
  const _RampModule({required this.state, required this.change});
  final PlayerViewState state;
  final RampChange change;

  @override
  State<_RampModule> createState() => _RampModuleState();
}

/// Einstellungen eingeklappt, damit am Desktop alle Module ohne Scrollen sichtbar sind.
class _RampModuleState extends State<_RampModule> {
  bool _settings = false;

  RampChange get change => widget.change;

  Widget _stepper(
    BuildContext context,
    String label,
    String key,
    String value,
    VoidCallback down,
    VoidCallback up,
  ) => Row(
    children: [
      Expanded(child: Text(label)),
      RepeatButton(key: Key('ramp:$key:-'), icon: Icons.remove, onStep: down),
      SizedBox(
        width: 56,
        child: Text(
          value,
          key: Key('ramp:$key'),
          textAlign: TextAlign.center,
          style: WsTheme.of(context).number(13, weight: FontWeight.w500),
        ),
      ),
      RepeatButton(key: Key('ramp:$key:+'), icon: Icons.add, onStep: up),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final s = widget.state;
    final r = s.ramp;
    final on = r.rampEnabled;
    final ladder = rampLadder(r);
    final percent = (s.speed * 100).round();
    final reached = ladder.where((p) => p <= percent);
    final now = reached.isEmpty ? null : reached.last;
    return WsCard(
      key: const Key('card:ramp'),
      children: [
        CardHeader(
          title: 'Steigerung',
          value: on,
          onChanged: (v) => change(enabled: v),
          trailing: BorderedButton(
            key: const Key('rampSettings'),
            label: _settings ? 'Einstellungen schliessen' : 'Einstellen',
            icon: _settings ? WsIcons.close : WsIcons.slider,
            iconOnly: true,
            selected: _settings,
            onPressed: () => setState(() => _settings = !_settings),
          ),
        ),
        Text(
          '+${r.rampStep} % nach ${r.rampPasses} '
          '${r.rampPasses == 1 ? 'Durchgang' : 'Durchgängen'}',
          style: TextStyle(fontSize: 12, color: ws.muted),
        ),
        Dimmed(
          enabled: on,
          child: _Ladder(steps: ladder, now: on ? now : null),
        ),
        if (on)
          Text(
            s.rampLabel,
            key: const Key('ramp:status'),
            style: ws.number(15),
          ),
        if (_settings) ...[
          Dimmed(
            key: const Key('dim:ramp'),
            enabled: on,
            child: Column(
              children: [
                _stepper(
                  context,
                  'Startstufe',
                  'start',
                  '${r.rampStart} %',
                  () => change(start: r.rampStart - 5),
                  () => change(start: r.rampStart + 5),
                ),
                _stepper(
                  context,
                  'Zielstufe',
                  'target',
                  '${r.rampTarget} %',
                  () => change(target: r.rampTarget - 5),
                  () => change(target: r.rampTarget + 5),
                ),
                Row(
                  children: [
                    const Expanded(child: Text('Schrittweite')),
                    DropdownButton<int>(
                      key: const Key('ramp:step'),
                      value: r.rampStep,
                      items: [
                        for (final st in PlaybackSettings.rampSteps)
                          DropdownMenuItem(value: st, child: Text('+$st %')),
                      ],
                      onChanged: on ? (v) => change(step: v) : null,
                    ),
                  ],
                ),
                _stepper(
                  context,
                  'Durchgänge pro Stufe',
                  'passes',
                  '${r.rampPasses}',
                  () => change(passes: r.rampPasses - 1),
                  () => change(passes: r.rampPasses + 1),
                ),
              ],
            ),
          ),
          HintText(
            on && !s.rampCounting
                ? 'Gezählt wird nur bei eingeschaltetem Tempo und aktivem Loop.'
                : 'Ein Durchgang zählt beim Sprung vom Loop-Ende zum Anfang. '
                      'Loop oder Tempo von Hand ändern setzt den Zähler zurück.',
          ),
        ],
      ],
    );
  }
}

/// Stufenleiter: erreichte Stufen gedämpft, aktuelle umrandet, kommende grau.
class _Ladder extends StatelessWidget {
  const _Ladder({required this.steps, required this.now});
  final List<int> steps;
  final int? now;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final n = steps.length;
    final labelEvery = max(1, (n / 9).ceil());
    return SizedBox(
      key: const Key('rampLadder'),
      height: 24 + 9.0 * min(n, 9) + 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: n > 12 ? 2 : 6,
        children: [
          for (var i = 0; i < n; i++)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 4,
                children: [
                  Container(
                    key: Key(
                      steps[i] == now ? 'ladder:now' : 'ladder:${steps[i]}',
                    ),
                    height: 24 + 9.0 * min(n, 9) * (n == 1 ? 1 : i / (n - 1)),
                    decoration: BoxDecoration(
                      color: now != null && steps[i] <= now!
                          ? ws.amber.withValues(
                              alpha: steps[i] == now ? 1 : 0.45,
                            )
                          : ws.border,
                      borderRadius: BorderRadius.circular(3),
                      border: steps[i] == now
                          ? Border.all(color: ws.text, width: 2)
                          : null,
                    ),
                  ),
                  SizedBox(
                    height: 14,
                    child: i % labelEvery == 0 || i == n - 1
                        ? FittedBox(
                            child: Text(
                              '${steps[i]}',
                              style: ws.number(
                                11,
                                color: steps[i] == now ? ws.text : ws.muted,
                                weight: steps[i] == now
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// MARK: Wiedergabe

class _Transport extends StatelessWidget {
  const _Transport({required this.state, required this.actions});
  final PlayerViewState state;
  final PlayerViewActions actions;

  @override
  Widget build(BuildContext context) {
    final m = WsLayout.of(context);
    final s = state;
    final buttons = <Widget>[
      _IconBtn(
        icon: WsIcons.backwardEnd,
        label: 'Zum Loop-Start',
        onPressed: () => actions.seek(s.activeLoop?.$1 ?? 0),
      ),
      _IconBtn(
        icon: WsIcons.back15,
        label: '15 Sekunden zurück',
        onPressed: () => actions.seek((s.position - 15).clamp(0, s.duration)),
      ),
      if (m.size != WsSize.phone)
        _IconBtn(
          key: const Key('playPause'),
          icon: s.playing ? WsIcons.pause : WsIcons.play,
          label: s.playing ? 'Pause' : 'Wiedergabe',
          onPressed: actions.playPause,
          wide: true,
        ),
      _IconBtn(
        icon: WsIcons.forward15,
        label: '15 Sekunden vor',
        onPressed: () => actions.seek((s.position + 15).clamp(0, s.duration)),
      ),
      if (m.size != WsSize.phone) const ShortcutBadge('Leertaste'),
    ];
    final volume = _Volume(value: s.volume, onChanged: actions.volume);
    return Wrap(
      key: const Key('transportBar'),
      alignment: m.size == WsSize.tablet
          ? WrapAlignment.center
          : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: m.touch ? WsSpace.l : WsSpace.s,
      runSpacing: WsSpace.s,
      children: [...buttons, volume],
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    final h = m.touch ? max(48.0, m.target) : 32.0;
    return ExcludeFocus(
      child: Tooltip(
        message: label,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: ws.text,
            backgroundColor: wide ? ws.panel2 : ws.panel,
            minimumSize: Size(wide ? h * 1.4 : h * 1.15, h),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: ws.border),
              borderRadius: BorderRadius.circular(m.touch ? 10 : 6),
            ),
          ),
          child: Icon(icon, size: m.touch ? 20 : 16, semanticLabel: label),
        ),
      ),
    );
  }
}

/// Lautstärke: Symbol und kurzer Regler.
class _Volume extends StatelessWidget {
  const _Volume({required this.value, required this.onChanged});
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
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    return Semantics(
      key: const Key('volume'),
      label: 'Lautstärke',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(symbol(value), size: 18, color: ws.muted),
          SizedBox(
            width: 120,
            height: m.touch ? m.target : 32,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: ws.muted,
                trackHeight: 3,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: m.touch ? 10 : 7,
                ),
              ),
              child: ExcludeFocus(
                child: Slider(value: value.clamp(0, 1), onChanged: onChanged),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Phone: S hier, Play, E hier unten in Daumenreichweite (#30/AK4).
class _ThumbBar extends StatelessWidget {
  const _ThumbBar({required this.state, required this.actions});
  final PlayerViewState state;
  final PlayerViewActions actions;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    final h = max(56.0, m.target);
    Widget btn(
      Key key,
      String tip,
      Widget child,
      VoidCallback onTap, {
      bool strong = false,
    }) => Expanded(
      child: ExcludeFocus(
        child: Tooltip(
          message: tip,
          child: TextButton(
            key: key,
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: ws.text,
              backgroundColor: strong ? ws.panel2 : ws.panel,
              minimumSize: Size(m.target, h),
              textStyle: const TextStyle(
                fontFamily: textFont,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                side: BorderSide(color: ws.border),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
    return Container(
      key: const Key('thumbBar'),
      color: ws.bg,
      padding: const EdgeInsets.fromLTRB(
        WsSpace.l,
        WsSpace.s,
        WsSpace.l,
        WsSpace.l,
      ),
      child: Row(
        spacing: 10,
        children: [
          btn(
            const Key('here:Anfang'),
            'Aktuelle Wiedergabeposition als Anfang übernehmen',
            const Text('S hier'),
            () => actions.loopStart(state.position),
          ),
          btn(
            const Key('playPause'),
            state.playing ? 'Pause' : 'Wiedergabe',
            Icon(
              state.playing ? WsIcons.pause : WsIcons.play,
              size: 22,
              semanticLabel: state.playing ? 'Pause' : 'Wiedergabe',
            ),
            actions.playPause,
            strong: true,
          ),
          btn(
            const Key('here:Ende'),
            'Aktuelle Wiedergabeposition als Ende übernehmen',
            const Text('E hier'),
            () => actions.loopEnd(state.position),
          ),
        ],
      ),
    );
  }
}

// MARK: Zeitfeld

/// Zeitfeld (mm:ss bzw. mm:ss.d); übernimmt bei Return oder wenn der Fokus geht.
class TimeField extends StatefulWidget {
  const TimeField({
    super.key,
    required this.value,
    required this.onCommit,
    this.precise = false,
    this.fontSize,
  });
  final double value;
  final ValueChanged<double> onCommit;

  /// Immer mit Zehntelsekunden (`00:42.0`).
  final bool precise;

  /// Ohne Rahmen in der Zahlenschrift dieser Grösse (Loop-Anzeige «Start → Ende»).
  final double? fontSize;

  @override
  State<TimeField> createState() => _TimeFieldState();
}

class _TimeFieldState extends State<TimeField> {
  late final _text = TextEditingController(text: _format(widget.value));
  final _focus = FocusNode();

  String _format(double v) =>
      widget.precise ? formatTimePrecise(v) : formatTimeField(v);

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
      _text.text = _format(widget.value);
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
      _text.text = _format(parsed);
    } else {
      _text.text = _format(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final size = widget.fontSize;
    final style = size == null
        ? ws.number(14, weight: FontWeight.w500)
        : ws.number(size);
    return SizedBox(
      width: size == null ? 96 : size * 0.62 * 7 + 12,
      child: TextField(
        controller: _text,
        focusNode: _focus,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: style,
        cursorColor: ws.amber,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'mm:ss',
          border: size == null
              ? const OutlineInputBorder()
              : const UnderlineInputBorder(borderSide: BorderSide.none),
          focusedBorder: size == null
              ? OutlineInputBorder(borderSide: BorderSide(color: ws.amber))
              : UnderlineInputBorder(borderSide: BorderSide(color: ws.amber)),
          contentPadding: EdgeInsets.symmetric(
            horizontal: size == null ? 8 : 2,
            vertical: size == null ? 8 : 4,
          ),
        ),
        // Return übernimmt und gibt den Fokus an die Tastenkürzel zurück.
        onSubmitted: (_) => _focus.unfocus(
          disposition: UnfocusDisposition.previouslyFocusedChild,
        ),
      ),
    );
  }
}
