// Hauptfenster (#17): Desktop und iPad zweispaltig (Bibliothek | Player/Metronom), iPhone und
// Android-Telefon einspaltig mit Navigationsleiste. Tastenkürzel für Player, Metronom und Bibliothek.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/app_controller.dart';
import '../metronome/metronome_panel.dart';
import '../metronome/practice_shortcuts.dart';
import 'library_view.dart';
import 'player_view.dart';
import 'style.dart';

/// Ab dieser Breite zwei Spalten.
const wideLayoutWidth = 700.0;

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller, this.recordingCard});
  final AppController controller;

  /// Aufnahme-Karte (nur macOS), am Ende des Player-Reiters.
  final Widget? recordingCard;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0; // einspaltig: 0 Bibliothek, 1 Player, 2 Metronom
  Timer? _metronomeTicker;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_showMessage);
    c.metronome.addListener(_updateTicker);
  }

  @override
  void dispose() {
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
    final text = c.message;
    if (text == null) return;
    c.clearMessage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(text, key: const Key('message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
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
    final meta = Theme.of(context).platform == TargetPlatform.macOS;
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
          builder: (context, box) =>
              box.maxWidth >= wideLayoutWidth ? _wide() : _narrow(),
        ),
      ),
    );
  }

  Widget _wide() => Scaffold(
    key: const Key('layout:wide'),
    body: SafeArea(
      child: Row(
        children: [
          SizedBox(width: 320, child: LibraryView(controller: c)),
          const VerticalDivider(width: 1),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(icon: Icon(WsIcons.musicNote), text: 'Player'),
                      Tab(icon: Icon(WsIcons.metronome), text: 'Metronom'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [_playerTab(), _metronomeTab()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _narrow() => Scaffold(
    key: const Key('layout:narrow'),
    body: SafeArea(
      child: IndexedStack(
        index: _tab,
        children: [
          LibraryView(
            controller: c,
            onSelected: () => setState(() => _tab = 1),
          ),
          _playerTab(),
          _metronomeTab(),
        ],
      ),
    ),
    bottomNavigationBar: ExcludeFocus(
      child: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(WsIcons.musicNoteList),
            label: 'Bibliothek',
          ),
          NavigationDestination(icon: Icon(WsIcons.musicNote), label: 'Player'),
          NavigationDestination(
            icon: Icon(WsIcons.metronome),
            label: 'Metronom',
          ),
        ],
      ),
    ),
  );

  Widget _metronomeTab() => ExcludeFocus(
    child: AccentBackground(
      child: CardColumn(children: [MetronomePanel(controller: c.metronome)]),
    ),
  );

  Widget _playerTab() => ListenableBuilder(
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
              state: PlayerViewState(
                title: p.hasTrack ? p.title : null,
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
                rampLabel: p.rampLabel,
                error: p.error,
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
              extraCards: [
                if (widget.recordingCard != null) widget.recordingCard!,
              ],
            ),
          ),
        ],
      );
    },
  );
}
