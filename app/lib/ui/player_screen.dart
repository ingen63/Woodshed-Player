// Area «Player» (#115): the loaded track with cover, title, position and volume, controlled like Spotify:
// Shuffle · Previous · Play/Pause · Next · Repeat (off → list → track). No practice modules (#115/AK2).
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../app/app_controller.dart';
import '../player/play_queue.dart';
import '../time_format.dart';
import 'library_view.dart' show TrackArtwork;
import 'messages.dart';
import 'style.dart';
import 'timeline.dart' show ProgressScrubber;

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.controller, this.leading});

  final AppController controller;

  /// Top left, e.g. closing the full player on the phone.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.player, c.library]),
      builder: (context, _) {
        final m = WsLayout.of(context);
        final ws = WsTheme.of(context);
        final l = context.l10n;
        final p = c.player;
        final loaded = p.hasTrack && p.duration > 0;
        final cover = switch (m.size) {
          WsSize.desktop => 260.0,
          WsSize.tablet => 360.0,
          WsSize.phone => 280.0,
        };
        final list = _listName(context, c);
        final body = LayoutBuilder(
          builder: (context, box) {
            final width = min(box.maxWidth - 2 * m.pad, 580.0);
            return SingleChildScrollView(
              padding: EdgeInsets.all(m.pad),
              child: Center(
                child: SizedBox(
                  width: max(width, 0),
                  child: Column(
                    key: const Key('playerScreen'),
                    spacing: m.touch ? WsSpace.l : WsSpace.m,
                    children: [
                      if (leading != null)
                        Align(alignment: Alignment.centerLeft, child: leading),
                      TrackArtwork(
                        path: loaded ? c.currentArtwork : null,
                        size: min(cover, width),
                      ),
                      Column(
                        children: [
                          Text(
                            loaded ? c.currentTitle ?? '' : l.noTrackSelected,
                            key: const Key('playerTitle'),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: m.size == WsSize.phone ? 22 : 26,
                              fontWeight: FontWeight.w700,
                              color: ws.text,
                            ),
                          ),
                          if (loaded && c.currentTrack?.artist != null)
                            Text(
                              c.currentTrack!.artist!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: ws.muted,
                                fontSize: m.body + 1,
                              ),
                            ),
                          if (!loaded)
                            Padding(
                              padding: const EdgeInsets.only(top: WsSpace.s),
                              child: BorderedButton(
                                key: const Key('openFile'),
                                label: l.openFile,
                                icon: WsIcons.folder,
                                onPressed: () => c.pickAndImport(),
                                shortcut: const ShortcutBadge(
                                  'O',
                                  command: true,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (loaded) ...[
                        Column(
                          spacing: WsSpace.xs,
                          children: [
                            ProgressScrubber(
                              key: const Key('playerProgress'),
                              position: p.position,
                              duration: p.duration,
                              onSeek: p.seek,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  formatTime(p.position),
                                  key: const Key('playerPosition'),
                                  style: ws.number(12, color: ws.muted),
                                ),
                                Text(
                                  formatTime(p.duration),
                                  style: ws.number(12, color: ws.muted),
                                ),
                              ],
                            ),
                          ],
                        ),
                        PlayerControls(controller: c),
                        if (list != null)
                          Text(
                            l.playingFrom(list),
                            key: const Key('playingFrom'),
                            style: TextStyle(color: ws.muted, fontSize: 12),
                          ),
                        _Volume(controller: c),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
        return body;
      },
    );
  }

  /// Name of the folder or playlist the track plays from; null for a track on its own.
  static String? _listName(BuildContext context, AppController c) {
    final q = c.queue;
    if (q == null) return null;
    if (q.isPlaylist) return c.library.playlist(q.playlistId!)?.name;
    final id = q.folderId;
    if (id == null) return context.l10n.noFolder;
    return c.library.folders.where((f) => f.id == id).firstOrNull?.name;
  }
}

/// #115/AK8: Shuffle · Previous · Play/Pause · Next · Repeat; a dot under Shuffle and Repeat shows «on»,
/// a small 1 at Repeat the track.
class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final l = context.l10n;
    final m = WsLayout.of(context);
    final ws = WsTheme.of(context);
    final p = c.player;
    final big = m.touch ? 72.0 : 60.0;
    final small = max(m.target, m.touch ? 52.0 : 40.0);
    Widget toggle({
      required String name,
      required IconData icon,
      required String label,
      required bool on,
      required VoidCallback onPressed,
      String? badge,
    }) => Semantics(
      toggled: on,
      child: SizedBox.square(
        dimension: small,
        child: IconButton(
          key: Key(name),
          tooltip: label,
          onPressed: onPressed,
          iconSize: 32,
          padding: EdgeInsets.zero,
          color: on ? ws.amber : ws.text,
          icon: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 22, semanticLabel: label),
                  if (badge != null)
                    Positioned(
                      right: -7,
                      top: -5,
                      child: Text(badge, style: ws.number(10, color: ws.amber)),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Container(
                key: on ? Key('$name:on') : null,
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? ws.amber : ws.bg.withAlpha(0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Widget step(Key key, IconData icon, String label, VoidCallback onPressed) =>
        SizedBox.square(
          dimension: small,
          child: IconButton(
            key: key,
            tooltip: label,
            onPressed: onPressed,
            icon: Icon(icon, size: 26, semanticLabel: label),
          ),
        );
    return ExcludeFocus(
      child: Row(
        key: const Key('playerControls'),
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: m.touch ? WsSpace.l : WsSpace.m,
        children: [
          toggle(
            name: 'shuffle',
            icon: WsIcons.shuffle,
            label: c.shuffle ? l.shuffleOn : l.shuffle,
            on: c.shuffle,
            onPressed: c.toggleShuffle,
          ),
          step(
            const Key('previous'),
            WsIcons.backwardEnd,
            l.previousTrack,
            () => c.previous(),
          ),
          SizedBox.square(
            dimension: big,
            child: IconButton.filled(
              key: const Key('playPause'),
              tooltip: p.isPlaying ? l.pause : l.play,
              style: IconButton.styleFrom(
                backgroundColor: ws.text,
                foregroundColor: ws.bg,
              ),
              onPressed: c.session.toggleTitle,
              icon: Icon(
                p.isPlaying ? WsIcons.pause : WsIcons.play,
                size: 28,
                semanticLabel: p.isPlaying ? l.pause : l.play,
              ),
            ),
          ),
          step(
            const Key('next'),
            WsIcons.forwardEnd,
            l.nextTrack,
            () => c.next(),
          ),
          toggle(
            name: 'repeat',
            icon: c.repeat == Repeat.track ? WsIcons.repeatOne : WsIcons.repeat,
            label: switch (c.repeat) {
              Repeat.off => l.repeatOff,
              Repeat.list => l.repeatList,
              Repeat.track => l.repeatTrack,
            },
            on: c.repeat != Repeat.off,
            onPressed: c.cycleRepeat,
            badge: c.repeat == Repeat.track ? '1' : null,
          ),
        ],
      ),
    );
  }
}

/// Volume: symbol (mutes, «M») and slider.
class _Volume extends StatelessWidget {
  const _Volume({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    final p = controller.player;
    final v = p.volume;
    final l = context.l10n;
    return Semantics(
      key: const Key('playerVolume'),
      label: l.volume,
      child: ExcludeFocus(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('mute'),
              tooltip: l.volume,
              onPressed: p.toggleMute,
              icon: Icon(
                v <= 0
                    ? WsIcons.speakerOff
                    : v < 0.34
                    ? WsIcons.speaker1
                    : v < 0.67
                    ? WsIcons.speaker2
                    : WsIcons.speaker3,
                size: 18,
                color: ws.muted,
              ),
            ),
            SizedBox(
              width: 200,
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
                child: Slider(value: v.clamp(0, 1), onChanged: p.setVolume),
              ),
            ),
            const ShortcutBadge('M'),
          ],
        ),
      ),
    );
  }
}
