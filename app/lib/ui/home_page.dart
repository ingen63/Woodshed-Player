// Hauptfenster im Design «Studio» (#30). Nach Fensterbreite: Desktop (> 1000) mit fester Bibliothek
// links, Tablet (600–1000) mit einblendbarer Bibliothek, Phone (< 600) mit Bibliothek als eigener Seite.
// Alle Zustände liegen in den Controllern; ein Wechsel der Grösse verliert weder Wiedergabe noch Loop.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/app_controller.dart';
import '../metronome/metronome_panel.dart';
import '../metronome/practice_shortcuts.dart';
import 'about_dialog.dart';
import 'library_view.dart';
import 'messages.dart';
import 'player_view.dart';
import 'style.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    this.recordingButton,
    this.installHint = false,
  });
  final AppController controller;

  /// #39/AK6: hint «Add to Home Screen» on top until it is closed (iPhone/iPad in the browser); once
  /// closed it stays away on this device (#110).
  final bool installHint;

  /// Aufnahme-Knopf (#4); sichtbar nur auf macOS, Windows und Linux (#30/AK10).
  final Widget? recordingButton;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _phonePlayer = false; // Phone: Übe-Seite statt Bibliothek
  Timer? _metronomeTicker;
  final _scaffold = GlobalKey<ScaffoldState>();

  /// Hält den Aufnahme-Knopf (und eine laufende Aufnahme) über Layout-Wechsel hinweg.
  final _recordingKey = GlobalKey();

  /// #37: back in the foreground → sync.
  late final AppLifecycleListener _lifecycle;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    KeyboardPresence.instance.attach();
    c.addListener(_showMessage);
    c.metronome.addListener(_updateTicker);
    _lifecycle = AppLifecycleListener(onResume: () => c.resumed());
    c.files.onShowAbout = () {
      if (mounted) showAbout(context, c.files);
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    c.files.setAboutMenuTitle(context.l10n.aboutApp); // #50/AK6: macOS app menu
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    c.files.onShowAbout = null;
    c.removeListener(_showMessage);
    c.metronome.removeListener(_updateTicker);
    _metronomeTicker?.cancel();
    super.dispose();
  }

  /// Tempo der automatischen Steigerung abholen, solange das Metronom läuft.
  void _updateTicker() {
    if (c.metronome.running) {
      _metronomeTicker ??= Timer.periodic(
        const Duration(milliseconds: 33),
        (_) => c.metronome.sync(),
      );
    } else {
      _metronomeTicker?.cancel();
      _metronomeTicker = null;
    }
  }

  void _showMessage() {
    final m = c.message;
    if (m == null) return;
    c.clearMessage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(
            libraryMessageText(context.l10n, m),
            key: const Key('message'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.ok),
            ),
          ],
        ),
      );
    });
  }

  void _playPause() {
    final p = c.player;
    if (!p.hasTrack) return;
    p.isPlaying ? p.togglePlayPauseReturningToLoop() : c.session.playTitle();
  }

  void _deleteCurrent() {
    final t = c.currentTrack;
    if (t != null) confirmDeleteTrack(context, c, t);
  }

  @override
  Widget build(BuildContext context) {
    final p = c.player;
    final platform = Theme.of(context).platform;
    final meta = isApplePlatform(platform);
    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.keyO,
          meta: meta,
          control: !meta,
        ): () =>
            c.pickAndImport(),
        SingleActivator(
          LogicalKeyboardKey.keyN,
          meta: meta,
          control: !meta,
          shift: true,
        ): () =>
            newFolder(context, c.library),
      },
      child: PracticeShortcuts(
        metronome: c.metronome,
        onPlayPause: _playPause,
        onLoopStart: () => p.hasTrack ? p.setLoopStart(p.position) : null,
        onLoopEnd: () => p.hasTrack ? p.setLoopEnd(p.position) : null,
        onSpeedStep: (n) => p.hasTrack ? p.adjustSpeed(n) : null,
        onDelete: _deleteCurrent,
        child: LayoutBuilder(
          builder: (context, box) {
            final metrics = WsMetrics(WsSize.forWidth(box.maxWidth), platform);
            final layout = switch (metrics.size) {
              WsSize.desktop => _desktop(),
              WsSize.tablet => _tablet(),
              WsSize.phone => _phone(),
            };
            return WsLayout(
              metrics: metrics,
              child: widget.installHint && !c.library.installHintClosed
                  ? Column(
                      children: [
                        _InstallHint(
                          onClose: () => setState(
                            () => unawaited(c.library.closeInstallHint()),
                          ),
                        ),
                        Expanded(
                          child: MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            child: layout,
                          ),
                        ),
                      ],
                    )
                  : layout,
            );
          },
        ),
      ),
    );
  }

  Widget? _recording() {
    final button = widget.recordingButton;
    if (button == null || !isDesktopPlatform(Theme.of(context).platform)) {
      return null;
    }
    return KeyedSubtree(key: _recordingKey, child: button);
  }

  Widget _desktop() => Scaffold(
    key: const Key('layout:desktop'),
    body: SafeArea(
      child: Row(
        children: [
          Builder(
            builder: (context) => Container(
              width: 280,
              color: WsTheme.of(context).panel,
              child: LibraryView(controller: c),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _player(trailing: _recording())),
        ],
      ),
    ),
  );

  Widget _tablet() => Scaffold(
    key: _scaffold,
    drawer: Drawer(
      key: const Key('libraryDrawer'),
      width: 340,
      child: SafeArea(
        child: LibraryView(
          controller: c,
          onSelected: () => _scaffold.currentState?.closeDrawer(),
        ),
      ),
    ),
    body: SafeArea(
      key: const Key('layout:tablet'),
      child: _player(
        leading: BorderedButton(
          key: const Key('libraryToggle'),
          label: context.l10n.library,
          icon: WsIcons.sidebar,
          onPressed: () => _scaffold.currentState?.openDrawer(),
        ),
        trailing: _recording(),
      ),
    ),
  );

  Widget _phone() {
    final showPlayer = _phonePlayer;
    return PopScope(
      canPop: !showPlayer,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && showPlayer) setState(() => _phonePlayer = false);
      },
      child: Scaffold(
        key: const Key('layout:phone'),
        body: SafeArea(
          child: showPlayer
              ? _player(
                  leading: Builder(
                    builder: (context) => SizedBox.square(
                      dimension: WsLayout.of(context).target,
                      child: IconButton(
                        key: const Key('backToLibrary'),
                        tooltip: context.l10n.backToLibrary,
                        icon: const Icon(WsIcons.chevronLeft),
                        onPressed: () => setState(() => _phonePlayer = false),
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: LibraryView(
                        controller: c,
                        onSelected: () => setState(() => _phonePlayer = true),
                      ),
                    ),
                    _NowPlayingBar(
                      controller: c,
                      onOpen: () => setState(() => _phonePlayer = true),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _player({Widget? leading, Widget? trailing}) => ListenableBuilder(
    listenable: Listenable.merge([c.player, c.library]),
    builder: (context, _) {
      final p = c.player;
      final s = p.settings;
      final track = c.currentTrack;
      return Column(
        children: [
          if (p.isLoading)
            LinearProgressIndicator(
              key: const Key('loading'),
              value: p.loadProgress,
              minHeight: 2,
            ),
          Expanded(
            child: PlayerView(
              leading: leading,
              headerTrailing: trailing,
              metronome: MetronomeModule(controller: c.metronome),
              state: PlayerViewState(
                title: p.hasTrack ? c.currentTitle : null,
                artist: track?.artist,
                artwork: c.currentArtwork,
                position: p.position,
                duration: p.duration,
                playing: p.isPlaying,
                volume: p.volume,
                speedOn: s.speedEnabled,
                speed: s.speed,
                loopOn: s.loopEnabled,
                loopStart: s.loopStart,
                loopEnd: s.loopEnd,
                ramp: s,
                rampPasses: p.rampPasses,
                error: p.error,
                waveform: p.isLoading ? null : p.waveform,
                trackKey: p.path,
              ),
              actions: PlayerViewActions(
                open: () => c.pickAndImport(),
                playPause: c.session.toggleTitle,
                seek: p.seek,
                volume: p.setVolume,
                speedOn: p.setSpeedEnabled,
                speed: p.setSpeed,
                loopOn: p.setLoopEnabled,
                loopStart: p.setLoopStart,
                loopEnd: p.setLoopEnd,
                loopStartField: (v) =>
                    p.updateSettings((s) => s.copyWith(loopStart: v)),
                loopEndField: (v) =>
                    p.updateSettings((s) => s.copyWith(loopEnd: v)),
                ramp: p.setRamp,
                wholeTrack: () => p.updateSettings(
                  (s) => s.copyWith(loopStart: 0, loopEnd: p.duration),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Phone: Leiste unter der Bibliothek, öffnet die Übe-Seite (auch ohne Titel, fürs Metronom).
class _NowPlayingBar extends StatelessWidget {
  const _NowPlayingBar({required this.controller, required this.onOpen});
  final AppController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final m = WsLayout.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller.player, controller.library]),
      builder: (context, _) {
        final p = controller.player;
        return Material(
          color: ws.panel,
          child: InkWell(
            key: const Key('openPlayer'),
            onTap: onOpen,
            child: Container(
              constraints: BoxConstraints(minHeight: m.target + 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: ws.border)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: WsSpace.l),
              child: Row(
                spacing: WsSpace.m,
                children: [
                  Icon(
                    p.isPlaying ? WsIcons.pause : WsIcons.musicNote,
                    size: 18,
                    color: ws.amber,
                  ),
                  Expanded(
                    child: Text(
                      p.hasTrack
                          ? controller.currentTitle ?? ''
                          : context.l10n.practiceMetronome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(WsIcons.chevronRight, size: 16, color: ws.muted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// #39/AK6: how to install the app on iPhone and iPad (Share → Add to Home Screen); can be closed.
class _InstallHint extends StatelessWidget {
  const _InstallHint({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    return Material(
      key: const Key('installHint'),
      color: ws.panel2,
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: ws.border)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
          child: Row(
            spacing: WsSpace.s,
            children: [
              Icon(WsIcons.share, size: 18, color: ws.amber),
              Expanded(child: Text(context.l10n.installHint)),
              IconButton(
                key: const Key('installHintClose'),
                tooltip: context.l10n.close,
                icon: const Icon(WsIcons.close, size: 16),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
