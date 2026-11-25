// Main window in the design «Studio» (#30) with the areas Player, Practice and Metronome (#115). By window
// width: desktop (> 1000) with the area switcher in the title bar and the library beside the player,
// tablet (600–1000) with the switcher on top and the library as a drawer, phone (< 600) with a tab bar at
// the bottom. On the desktop the edge of the library can be dragged (#129). All state lives in the
// controllers; neither a change of size nor of area loses playback, the metronome, position, loop or tempo
// (#115/AK3).
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/app_controller.dart';
import '../app/practice_arming.dart';
import '../app/sidebar_width.dart';
import '../metronome/practice_shortcuts.dart';
import 'about_dialog.dart';
import 'app_menu_bar.dart';
import 'areas.dart';
import 'file_drop.dart';
import 'help_page.dart';
import 'library_view.dart';
import 'messages.dart';
import 'player_screen.dart';
import 'player_view.dart';
import 'shortcut_table.dart';
import 'style.dart';
import 'sync_settings.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    this.recordingButton,
    this.practiceRecording,
    this.installHint = false,
  });
  final AppController controller;

  /// #147: the switch «Armed» of the armed practice recording; only on the Mac, null elsewhere.
  final ArmedSwitchSlot? practiceRecording;

  /// #39/AK6: hint «Add to Home Screen» on top until it is closed (iPhone/iPad in the browser); once
  /// closed it stays away on this device (#110).
  final bool installHint;

  /// Aufnahme-Knopf (#4); sichtbar nur auf macOS, Windows und Linux (#30/AK10).
  final Widget? recordingButton;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Phone, area Player: the full player instead of the library.
  bool _phonePlayer = false;
  Timer? _metronomeTicker;
  final _scaffold = GlobalKey<ScaffoldState>();

  /// #115/AK11: ⌘K puts the cursor into the search field of the library.
  final _searchFocus = FocusNode();

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
    c.cloud.addListener(_signInHint);
    c.player.addListener(_signInHint);
    // #121: files dragged in from outside go to the playlist or folder under them
    c.dropTargetAt = fileDropTargetAt;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    c.cloud.removeListener(_signInHint);
    c.player.removeListener(_signInHint);
    c.removeListener(_showMessage);
    c.metronome.removeListener(_updateTicker);
    _metronomeTicker?.cancel();
    _searchFocus.dispose();
    super.dispose();
  }

  /// #54/AK5: the hint is shown once per expired sign-in.
  bool _signInHinted = false;

  /// #54/AK5: the silent renewal of the sign-in failed: ask to sign in again, never during playback.
  void _signInHint() {
    if (!c.cloud.needsSignIn) {
      _signInHinted = false;
      return;
    }
    if (_signInHinted || c.player.isPlaying) return;
    _signInHinted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l = context.l10n;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const Key('signInHint'),
          content: Text(l.syncSignInAgain),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const Key('signInHintSettings'),
              onPressed: () {
                Navigator.pop(context);
                showSyncSettings(this.context, c);
              },
              child: Text(l.settings),
            ),
          ],
        ),
      );
    });
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

  /// #115/AK12: Play/Pause in the area Practice; a pause goes back to the loop start or the track start.
  void _practicePlayPause() {
    final p = c.player;
    if (!p.hasTrack) return;
    p.isPlaying ? p.pauseToStart() : c.session.playTitle();
  }

  void _deleteCurrent() {
    final t = c.currentTrack;
    if (t != null) confirmDeleteTrack(context, c, t);
  }

  void _setArea(AppArea a) => c.setArea(a);

  /// #148: the help or the shortcuts are open; a second call does not open them again.
  bool _helpOpen = false;

  /// #148/AK13: what this platform has, asked as the features ask it.
  Future<HelpTopics> _helpTopics() async {
    final platform = Theme.of(context).platform;
    final recording =
        (widget.recordingButton != null || widget.practiceRecording != null) &&
        isDesktopPlatform(platform);
    final keyboard = KeyboardPresence.available(platform);
    return HelpTopics(
      recording: recording,
      export: c.mp3 != null,
      commandLine: await c.files.commandSocket() != null,
      web: kIsWeb,
      keyboard: keyboard,
    );
  }

  Future<void> _openHelp() async {
    if (_helpOpen) return;
    _helpOpen = true;
    try {
      final topics = await _helpTopics();
      if (mounted) await showHelp(context, topics);
    } finally {
      _helpOpen = false;
    }
  }

  Future<void> _openShortcuts() async {
    if (_helpOpen) return;
    _helpOpen = true;
    try {
      await showShortcuts(context);
    } finally {
      _helpOpen = false;
    }
  }

  /// #148/AK3: «?» outside a text field.
  static bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null &&
        (ctx.widget is EditableText ||
            ctx.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  /// #115/AK11: ⌘K: the search field (on the tablet in the drawer, on the phone in the library instead of
  /// the full player); #148: from every area, which switches to Player.
  void _search() {
    if (c.area != AppArea.player) _setArea(AppArea.player);
    final state = _scaffold.currentState;
    if (state != null && state.hasDrawer && !state.isDrawerOpen) {
      state.openDrawer();
    }
    if (_phonePlayer) setState(() => _phonePlayer = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final meta = isApplePlatform(platform);
    SingleActivator command(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(key, meta: meta, control: !meta, shift: shift);
    // #144: the macOS menu bar in the UI language; «About» opens the dialog (#50/AK6)
    return AppMenuBar(
      files: c.files,
      onAbout: () => showAbout(context, c.files),
      onHelp: _openHelp,
      onShortcuts: _openShortcuts,
      child: CallbackShortcuts(
        bindings: {
          command(LogicalKeyboardKey.keyK): _search,
          // #148/AK1: on the Mac the Help menu has ⌘?
          if (!c.files.hasMenuBar) helpActivator(platform): _openHelp,
          command(LogicalKeyboardKey.keyO): () => c.pickAndImport(),
          command(LogicalKeyboardKey.keyN, shift: true): () =>
              newFolder(context, c.library),
          // #115: ⌘1, ⌘2, ⌘3 (Ctrl outside Apple) switch the area
          command(LogicalKeyboardKey.digit1): () => _setArea(AppArea.player),
          command(LogicalKeyboardKey.digit2): () => _setArea(AppArea.practice),
          command(LogicalKeyboardKey.digit3): () => _setArea(AppArea.metronome),
        },
        child: ListenableBuilder(
          listenable: Listenable.merge([c, c.player, c.metronome]),
          builder: (context, _) => LayoutBuilder(
            builder: (context, box) {
              final metrics = WsMetrics(
                WsSize.forWidth(box.maxWidth),
                platform,
              );
              final layout = switch (metrics.size) {
                WsSize.desktop => _desktop(),
                WsSize.tablet => _tablet(),
                WsSize.phone => _phone(),
              };
              return WsLayout(
                metrics: metrics,
                child: HelpActions(
                  onHelp: _openHelp,
                  onShortcuts: _openShortcuts,
                  child: _shortcuts(
                    widget.installHint && !c.library.installHintClosed
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
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// #115/AK11: the shortcuts of the area shown: like Spotify in Player, the practice shortcuts in Practice
  /// and Metronome (Space there starts and stops the metronome). One Focus for all areas, so that a switch
  /// keeps the widgets below (library, search, recording).
  Widget _shortcuts(Widget child) {
    final p = c.player;
    final area = c.area;
    final player = PlayerShortcuts(controller: c, child: const SizedBox());
    final practice = PracticeShortcuts(
      metronome: c.metronome,
      onPlayPause: area == AppArea.metronome
          ? c.metronome.toggle
          : _practicePlayPause,
      onLoopStart: () => p.hasTrack ? p.setLoopStart(p.position) : null,
      onLoopEnd: () => p.hasTrack ? p.setLoopEnd(p.position) : null,
      onSpeedStep: (n) => p.hasTrack ? p.adjustSpeed(n) : null,
      onDelete: _deleteCurrent,
      child: const SizedBox(),
    );
    final onKey = area == AppArea.player ? player.onKey : practice.onKey;
    return Focus(
      key: const Key('shortcuts'),
      autofocus: true,
      onKeyEvent: (node, event) {
        // #148/AK3: «?» opens the shortcuts in every area, whatever key types it
        if (!_typing() &&
            shortcutsActivator.accepts(event, HardwareKeyboard.instance)) {
          if (event is KeyDownEvent) unawaited(_openShortcuts());
          return KeyEventResult.handled;
        }
        final result = onKey(node, event);
        // #147/AK4: Space plays or pauses as before and ends a running take of «Armed».
        if (result == KeyEventResult.handled &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.practiceRecording?.arming.endTake();
        }
        return result;
      },
      child: child,
    );
  }

  /// #147: keeps the switch «Armed» across layout changes.
  final _armedKey = GlobalKey();

  Widget? _recording() {
    final button = widget.recordingButton;
    final armed = widget.practiceRecording;
    if ((button == null && armed == null) ||
        !isDesktopPlatform(Theme.of(context).platform)) {
      return null;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: WsSpace.m,
      children: [
        // #147/AK1, AK6: in Practice and Metronome; in Player only while it is on.
        if (armed != null)
          ListenableBuilder(
            listenable: armed.arming,
            builder: (context, _) => c.area != AppArea.player || armed.arming.on
                ? KeyedSubtree(key: _armedKey, child: armed.widget)
                : const SizedBox.shrink(),
          ),
        if (button != null) KeyedSubtree(key: _recordingKey, child: button),
      ],
    );
  }

  Set<AppArea> get _running => runningAreas(c);

  /// #115: what plays in another area: the track in the area Metronome, the metronome elsewhere.
  Widget? _miniBar({VoidCallback? onOpenTrack}) {
    final area = c.area;
    if (area == AppArea.metronome) {
      return c.player.hasTrack
          ? TrackMiniBar(controller: c, onOpen: onOpenTrack)
          : null;
    }
    if (c.metronome.running) {
      return MetronomeMiniBar(
        controller: c,
        onOpen: () => _setArea(AppArea.metronome),
      );
    }
    return null;
  }

  Widget _content({Widget? playerLeading}) => switch (c.area) {
    AppArea.player => PlayerScreen(controller: c, leading: playerLeading),
    AppArea.practice => _practice(),
    AppArea.metronome => MetronomeScreen(controller: c),
  };

  Widget _desktop() {
    final ws = WsTheme.of(context);
    final mini = _miniBar(onOpenTrack: () => _setArea(c.trackArea));
    return Scaffold(
      key: const Key('layout:desktop'),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: ws.panel,
                border: Border(bottom: BorderSide(color: ws.border)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Expanded(child: SizedBox()),
                  AreaSwitcher(
                    area: c.area,
                    running: _running,
                    onSelect: _setArea,
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _recording(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: c.area == AppArea.player
                  ? LayoutBuilder(
                      builder: (context, box) => _withSidebar(box.maxWidth),
                    )
                  : _content(),
            ),
            ?mini,
          ],
        ),
      ),
    );
  }

  /// #129: the width of the sidebar while its edge is dragged; saved when the drag ends.
  double? _draggedWidth;

  /// #129: width of the sidebar and position of the pointer when the drag began.
  (double, double)? _dragStart;

  /// #129: the library beside the player, its edge dragged with the mouse or a finger (AK1, AK5); a double
  /// click restores the default width (AK4). The width stays within its limits, also in a narrower window
  /// (AK2), and is kept on this device (AK3).
  Widget _withSidebar(double windowWidth) {
    final ws = WsTheme.of(context);
    final width = sidebarWidth(
      _draggedWidth ?? c.library.sidebarWidth,
      windowWidth,
    );
    // a finger needs a wider grip than the mouse pointer
    final touch = !isDesktopPlatform(Theme.of(context).platform);
    final grip = touch ? 24.0 : 8.0;
    return Stack(
      children: [
        Row(
          children: [
            Container(
              key: const Key('librarySidebar'),
              width: width,
              color: ws.panel,
              child: LibraryView(controller: c, searchFocus: _searchFocus),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _content()),
          ],
        ),
        Positioned(
          // mostly over the player, so that the scroll bar of the library stays free
          left: width - grip / 4,
          width: grip,
          top: 0,
          bottom: 0,
          child: MouseRegion(
            key: const Key('sidebarEdge'),
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              // the edge follows the pointer from where it went down, without the drag slop
              dragStartBehavior: DragStartBehavior.down,
              onHorizontalDragStart: (d) => setState(() {
                _dragStart = (width, d.globalPosition.dx);
                _draggedWidth = width;
              }),
              onHorizontalDragUpdate: (d) => setState(() {
                final (startWidth, startX) = _dragStart ?? (width, 0.0);
                _draggedWidth = sidebarWidth(
                  startWidth + d.globalPosition.dx - startX,
                  windowWidth,
                );
              }),
              onHorizontalDragEnd: (_) => _endDrag(),
              // also a click without a drag: the width stays
              onHorizontalDragCancel: _endDrag,
              onDoubleTap: () => _saveSidebarWidth(null),
            ),
          ),
        ),
      ],
    );
  }

  void _endDrag() {
    final dragged = _draggedWidth;
    if (dragged != null) _saveSidebarWidth(dragged);
  }

  void _saveSidebarWidth(double? width) {
    setState(() {
      _draggedWidth = null;
      _dragStart = null;
    });
    unawaited(c.library.setSidebarWidth(width?.roundToDouble()));
  }

  Widget _tablet() {
    final mini = _miniBar(onOpenTrack: () => _setArea(c.trackArea));
    return Scaffold(
      key: _scaffold,
      drawer: Drawer(
        key: const Key('libraryDrawer'),
        width: 340,
        child: SafeArea(
          child: LibraryView(
            controller: c,
            searchFocus: _searchFocus,
            onSelected: () => _scaffold.currentState?.closeDrawer(),
          ),
        ),
      ),
      body: SafeArea(
        key: const Key('layout:tablet'),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WsSpace.l,
                WsSpace.m,
                WsSpace.l,
                0,
              ),
              child: Row(
                spacing: WsSpace.m,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: BorderedButton(
                        key: const Key('libraryToggle'),
                        label: context.l10n.library,
                        icon: WsIcons.sidebar,
                        onPressed: () => _scaffold.currentState?.openDrawer(),
                      ),
                    ),
                  ),
                  AreaSwitcher(
                    area: c.area,
                    running: _running,
                    onSelect: _setArea,
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _recording(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _content()),
            ?mini,
          ],
        ),
      ),
    );
  }

  Widget _phone() {
    final area = c.area;
    final full = area == AppArea.player && _phonePlayer;
    final Widget content;
    Widget? mini;
    if (area == AppArea.player && !full) {
      content = LibraryView(
        controller: c,
        searchFocus: _searchFocus,
        onSelected: () => setState(() => _phonePlayer = true),
      );
      mini = c.player.hasTrack
          ? TrackMiniBar(
              key: const Key('openPlayer'),
              controller: c,
              onOpen: () => setState(() => _phonePlayer = true),
            )
          : null;
      if (c.metronome.running) {
        mini = Column(
          mainAxisSize: MainAxisSize.min,
          children: [?_miniBar(), ?mini],
        );
      }
    } else {
      content = _content(
        playerLeading: Builder(
          builder: (context) => SizedBox.square(
            dimension: WsLayout.of(context).target,
            child: IconButton(
              key: const Key('backToLibrary'),
              tooltip: context.l10n.backToLibrary,
              icon: const Icon(WsIcons.chevronDown),
              onPressed: () => setState(() => _phonePlayer = false),
            ),
          ),
        ),
      );
      mini = _miniBar(onOpenTrack: () => _setArea(c.trackArea));
    }
    return PopScope(
      canPop: !full,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && full) setState(() => _phonePlayer = false);
      },
      child: Scaffold(
        key: const Key('layout:phone'),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(child: content),
              ?mini,
              AreaTabBar(
                area: area,
                running: _running,
                onSelect: (a) {
                  if (a == area && a == AppArea.player) {
                    setState(() => _phonePlayer = false);
                  }
                  _setArea(a);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// #115/AK5: the area Practice: the practice screen without the metronome module.
  Widget _practice() => ListenableBuilder(
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
              onChooseTrack: () => _setArea(AppArea.player),
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
                playPause: _practicePlayPause,
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
