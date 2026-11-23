// The three areas Player, Practice and Metronome (#115, design A «tabs»): segmented control on desktop and
// tablet, tab bar at the bottom on the phone, a dot at the tab where something plays, a mini bar for what
// plays in another area, the area Metronome on its own, and the shortcuts of the area Player.
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/app_controller.dart';
import '../metronome/metronome_panel.dart';
import '../time_format.dart';
import 'messages.dart';
import 'style.dart';

String areaLabel(BuildContext context, AppArea a) => switch (a) {
  AppArea.player => context.l10n.areaPlayer,
  AppArea.practice => context.l10n.areaPractice,
  AppArea.metronome => context.l10n.areaMetronome,
};

IconData areaIcon(AppArea a) => switch (a) {
  AppArea.player => WsIcons.musicNote,
  AppArea.practice => WsIcons.slider,
  AppArea.metronome => WsIcons.metronome,
};

/// The areas where something plays: the metronome in its own, a playing track in the area it was last
/// shown in ([AppController.trackArea], Player or Practice).
Set<AppArea> runningAreas(AppController c) => {
  if (c.metronome.running) AppArea.metronome,
  if (c.player.isPlaying) c.trackArea,
};

/// #115: «Player | Practice | Metronome» (desktop in the title bar, tablet on top).
class AreaSwitcher extends StatelessWidget {
  const AreaSwitcher({
    super.key,
    required this.area,
    required this.running,
    required this.onSelect,
  });

  final AppArea area;
  final Set<AppArea> running;
  final ValueChanged<AppArea> onSelect;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    final h = m.touch ? m.target : 28.0;
    final platform = Theme.of(context).platform;
    return Semantics(
      label: context.l10n.areas,
      container: true,
      child: Container(
        key: const Key('areaSwitcher'),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: ws.panel2,
          border: Border.all(color: ws.border),
          borderRadius: BorderRadius.circular(m.touch ? 12 : 8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            for (final (i, a) in AppArea.values.indexed)
              _segment(context, a, h, ws, m, platform, i + 1),
          ],
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    AppArea a,
    double h,
    WsTheme ws,
    WsMetrics m,
    TargetPlatform platform,
    int n,
  ) {
    final selected = a == area;
    final label = areaLabel(context, a);
    final on = running.contains(a);
    return Semantics(
      selected: selected,
      button: true,
      label: on ? context.l10n.areaRunning(label) : label,
      excludeSemantics: true,
      child: Tooltip(
        message: KeyboardPresence.available(platform)
            ? shortcutLabel(platform, '$n', command: true)
            : '',
        child: ExcludeFocus(
          child: TextButton(
            key: Key('area:${a.name}'),
            onPressed: () => onSelect(a),
            style: TextButton.styleFrom(
              minimumSize: Size(0, h),
              padding: EdgeInsets.symmetric(horizontal: m.touch ? 22 : 18),
              backgroundColor: selected ? ws.amber : ws.panel2.withAlpha(0),
              foregroundColor: selected ? ws.bg : ws.text,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(m.touch ? 9 : 6),
              ),
              textStyle: TextStyle(
                fontFamily: textFont,
                fontSize: m.body,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Text(label),
                if (on)
                  _Dot(
                    key: Key('running:${a.name}'),
                    color: selected ? ws.bg : ws.amber,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// #115: tab bar at the bottom of the phone, symbol and label.
class AreaTabBar extends StatelessWidget {
  const AreaTabBar({
    super.key,
    required this.area,
    required this.running,
    required this.onSelect,
  });

  final AppArea area;
  final Set<AppArea> running;
  final ValueChanged<AppArea> onSelect;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    return Semantics(
      label: context.l10n.areas,
      container: true,
      child: Container(
        key: const Key('areaTabBar'),
        decoration: BoxDecoration(
          color: ws.panel,
          border: Border(top: BorderSide(color: ws.border)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              for (final a in AppArea.values)
                Expanded(child: _tab(context, a, ws, m)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, AppArea a, WsTheme ws, WsMetrics m) {
    final selected = a == area;
    final label = areaLabel(context, a);
    final on = running.contains(a);
    final color = selected ? ws.amber : ws.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: on ? context.l10n.areaRunning(label) : label,
      excludeSemantics: true,
      child: InkWell(
        key: Key('area:${a.name}'),
        onTap: () => onSelect(a),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: m.target + 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 2,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(areaIcon(a), size: 22, color: color),
                  if (on)
                    Positioned(
                      right: -6,
                      top: -2,
                      child: _Dot(
                        key: Key('running:${a.name}'),
                        color: ws.amber,
                      ),
                    ),
                ],
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({super.key, required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

/// #115: mini bar for what plays in another area: the track (in the area Metronome, or under the library
/// on the phone) or the metronome (in Player and Practice). A tap on its button starts or stops it.
class MiniBar extends StatelessWidget {
  const MiniBar({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.playing,
    required this.toggleLabel,
    required this.onToggle,
    this.onOpen,
    this.iconColor,
  });

  final IconData icon;
  final String title, subtitle, toggleLabel;
  final bool playing;
  final VoidCallback onToggle;

  /// Tap on the bar itself, e.g. opening the full player on the phone.
  final VoidCallback? onOpen;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    return Material(
      color: ws.panel,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          constraints: BoxConstraints(minHeight: m.target + 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: ws.border)),
          ),
          padding: const EdgeInsets.fromLTRB(WsSpace.l, 4, WsSpace.s, 4),
          child: Row(
            spacing: WsSpace.m,
            children: [
              Icon(icon, size: 18, color: iconColor ?? ws.amber),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: ws.muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
              ExcludeFocus(
                child: SizedBox.square(
                  dimension: m.target,
                  child: IconButton(
                    key: const Key('miniToggle'),
                    tooltip: toggleLabel,
                    onPressed: onToggle,
                    icon: Icon(
                      playing ? WsIcons.pause : WsIcons.play,
                      semanticLabel: toggleLabel,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The loaded track as a mini bar (#115): title, «paused · mm:ss» or the position, Play/Pause.
class TrackMiniBar extends StatelessWidget {
  const TrackMiniBar({super.key, required this.controller, this.onOpen});
  final AppController controller;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c.player, c.library, c.metronome]),
      builder: (context, _) {
        final p = c.player;
        final l = context.l10n;
        final time = '${formatTime(p.position)} / ${formatTime(p.duration)}';
        return KeyedSubtree(
          key: const Key('miniBar:track'),
          child: MiniBar(
            icon: WsIcons.musicNote,
            title: c.currentTitle ?? '',
            subtitle: p.isPlaying ? time : l.miniPaused(time),
            playing: p.isPlaying,
            toggleLabel: p.isPlaying
                ? l.pause
                : c.metronome.running
                ? l.miniPlayTrack
                : l.play,
            onToggle: c.session.toggleTitle,
            onOpen: onOpen,
          ),
        );
      },
    );
  }
}

/// The running metronome as a mini bar (#115): tempo, Stop.
class MetronomeMiniBar extends StatelessWidget {
  const MetronomeMiniBar({super.key, required this.controller, this.onOpen});
  final AppController controller;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final m = controller.metronome;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) => KeyedSubtree(
        key: const Key('miniBar:metronome'),
        child: MiniBar(
          icon: WsIcons.metronome,
          iconColor: WsTheme.of(context).blue,
          title: context.l10n.miniMetronome(m.settings.bpm),
          subtitle: '',
          playing: m.running,
          toggleLabel: m.running ? context.l10n.stop : context.l10n.start,
          onToggle: m.toggle,
          onOpen: onOpen,
        ),
      ),
    );
  }
}

/// #115/AK4: the area Metronome: every setting of the metronome on its own, without a track.
class MetronomeScreen extends StatelessWidget {
  const MetronomeScreen({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final m = WsLayout.of(context);
    return SingleChildScrollView(
      key: const Key('metronomeScreen'),
      padding: EdgeInsets.all(m.pad),
      child: Center(
        child: ConstrainedBox(
          // #133: two columns on the desktop
          constraints: BoxConstraints(
            maxWidth: m.size == WsSize.desktop ? 1040 : 640,
          ),
          child: MetronomePanel(controller: controller.metronome),
        ),
      ),
    );
  }
}

/// #115/AK11: shortcuts of the area Player, like Spotify (Windows and Linux with Ctrl or Alt): Space
/// Play/Pause, ⌥S shuffle, ⌥R repeat, M mute, ⌘K search, ⌘→/⌘← next/previous track, ⇧⌘→/⇧⌘← seek,
/// ⌘↑/⌘↓ volume. Off in text fields, except ⌘K.
class PlayerShortcuts extends StatelessWidget {
  const PlayerShortcuts({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.child,
  });

  final AppController controller;
  final VoidCallback onSearch;
  final Widget child;

  /// Seconds one ⇧⌘→ or ⇧⌘← seeks, like the ±15 s buttons of the area Practice.
  static const seekStep = 15.0;

  /// One ⌘↑ or ⌘↓ changes the volume by this.
  static const volumeStep = 0.1;

  static bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        (ctx.widget is EditableText ||
            ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  /// Handles [event]; public so that one Focus can switch between the shortcuts of the areas.
  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final command = keys.isMetaPressed || keys.isControlPressed;
    final key = event.logicalKey;
    if (command && key == LogicalKeyboardKey.keyK) {
      onSearch();
      return KeyEventResult.handled;
    }
    if (_typing()) return KeyEventResult.ignored;
    final c = controller;
    final p = c.player;
    final repeat = event is KeyRepeatEvent;
    if (command && !keys.isAltPressed) {
      final shift = keys.isShiftPressed;
      if (key == LogicalKeyboardKey.arrowRight) {
        shift ? p.skip(seekStep) : (repeat ? null : c.next());
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        shift ? p.skip(-seekStep) : (repeat ? null : c.previous());
      } else if (key == LogicalKeyboardKey.arrowUp && !shift) {
        p.setVolume(p.volume + volumeStep);
      } else if (key == LogicalKeyboardKey.arrowDown && !shift) {
        p.setVolume(p.volume - volumeStep);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (command || repeat) return KeyEventResult.ignored;
    if (keys.isAltPressed) {
      if (_isKey(event, LogicalKeyboardKey.keyS, PhysicalKeyboardKey.keyS)) {
        c.toggleShuffle();
      } else if (_isKey(
        event,
        LogicalKeyboardKey.keyR,
        PhysicalKeyboardKey.keyR,
      )) {
        c.cycleRepeat();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space) {
      if (p.hasTrack) c.session.toggleTitle();
    } else if (key == LogicalKeyboardKey.keyM) {
      p.toggleMute();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// ⌥S on a Mac types «ß» (logical key), so the physical key counts as well.
  static bool _isKey(
    KeyEvent e,
    LogicalKeyboardKey logical,
    PhysicalKeyboardKey physical,
  ) => e.logicalKey == logical || e.physicalKey == physical;

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: true, onKeyEvent: onKey, child: child);
}
