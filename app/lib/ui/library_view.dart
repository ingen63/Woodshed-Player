// Bibliotheksliste (#17), Vorlage TrackListView.swift: Ordner als Abschnitte, Ziehen zum Sortieren und
// in Ordner, Kontextmenüs (Rechtsklick bzw. «⋯»), Bestätigung vor dem Löschen.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../app/app_controller.dart';
import '../library/library.dart';
import '../time_format.dart';
import 'messages.dart';
import 'style.dart';

class LibraryView extends StatefulWidget {
  LibraryView({
    super.key,
    required this.controller,
    this.onSelected,
    bool? touch,
  }) : touch =
           touch ??
           (kIsWeb
               ? !isDesktopPlatform(defaultTargetPlatform)
               : !(Platform.isMacOS || Platform.isWindows || Platform.isLinux));

  final AppController controller;

  /// Nach dem Wählen eines Titels (einspaltig: zum Player wechseln).
  final VoidCallback? onSelected;

  /// Touch: Ziehen nach langem Drücken; sonst sofort mit der Maus.
  final bool touch;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final _collapsed = <String>{};

  AppController get c => widget.controller;
  Library get lib => c.library;

  void _select(Track t) {
    c.select(t);
    widget.onSelected?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([lib, c.player]),
      builder: (context, _) {
        final folders = lib.sortedFolders;
        final loose = lib.sortedTracksIn(null);
        final empty = lib.tracks.isEmpty && folders.isEmpty;
        return Column(
          children: [
            _Header(controller: c),
            if (lib.isImporting) const LinearProgressIndicator(minHeight: 2),
            const Divider(height: 1),
            Expanded(
              child: empty
                  ? _EmptyLibrary(onAdd: () => c.pickAndImport())
                  : ListView(
                      key: const Key('libraryList'),
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        if (folders.isNotEmpty)
                          _SectionHeader(
                            key: const Key('section:none'),
                            label: context.l10n.noFolder,
                            icon: WsIcons.tray,
                            onDrop: (id) => lib.placeTrack(id, null),
                          ),
                        for (final t in loose) _row(t),
                        if (loose.isEmpty && folders.isNotEmpty)
                          _Placeholder(
                            context.l10n.noTracksWithoutFolder,
                            onDrop: (id) => lib.placeTrack(id, null),
                          ),
                        for (final f in folders) ..._folder(f),
                      ],
                    ),
            ),
            if (lib.storage case final s?)
              _StorageLine(storageLabel(context.l10n, s)),
          ],
        );
      },
    );
  }

  List<Widget> _folder(TrackFolder f) {
    final l = context.l10n;
    final open = !_collapsed.contains(f.id);
    final tracks = lib.sortedTracksIn(f.id);
    return [
      _SectionHeader(
        key: Key('folder:${f.name}'),
        label: f.name,
        icon: WsIcons.folder,
        expanded: open,
        onToggle: () => setState(
          () => open ? _collapsed.add(f.id) : _collapsed.remove(f.id),
        ),
        onDrop: (id) => lib.placeTrack(id, f.id),
        menu: (context) => [
          MenuItemButton(
            leadingIcon: const Icon(WsIcons.add, size: 16),
            onPressed: () => c.pickAndImport(folderId: f.id),
            child: Text(l.addMp3Ellipsis),
          ),
          MenuItemButton(
            leadingIcon: const Icon(WsIcons.pencil, size: 16),
            onPressed: () async {
              final name = await askName(
                context,
                l.renameFolder,
                initial: f.name,
              );
              if (name != null) lib.renameFolder(f.id, name);
            },
            child: Text(l.renameEllipsis),
          ),
          MenuItemButton(
            leadingIcon: const Icon(WsIcons.trash, size: 16),
            onPressed: () async {
              if (await confirm(
                context,
                title: l.deleteNamedTitle(f.name),
                text: l.deleteFolderText,
                action: l.deleteFolder,
              )) {
                lib.deleteFolder(f.id);
              }
            },
            child: Text(l.deleteFolder),
          ),
        ],
      ),
      if (open) ...[
        for (final t in tracks) _row(t, indent: true),
        if (tracks.isEmpty)
          _Placeholder(l.emptyFolder, onDrop: (id) => lib.placeTrack(id, f.id)),
      ],
    ];
  }

  Widget _row(Track t, {bool indent = false}) {
    final l = context.l10n;
    return _TrackRow(
      key: Key('track:${t.title}'),
      track: t,
      artwork: lib.artworkPath(t),
      selected: c.player.trackId == t.id,
      indent: indent,
      touch: widget.touch,
      onTap: () => _select(t),
      onDrop: (id) => lib.placeTrack(id, t.folderId, beforeId: t.id),
      menu: (context) => [
        MenuItemButton(
          key: const Key('editTrack'),
          leadingIcon: const Icon(WsIcons.pencil, size: 16),
          onPressed: () => editTrack(context, lib, t),
          child: Text(l.editTrackEllipsis),
        ),
        SubmenuButton(
          leadingIcon: const Icon(WsIcons.folder, size: 16),
          menuChildren: [
            MenuItemButton(
              onPressed: t.folderId == null
                  ? null
                  : () => lib.moveTracks({t.id}, null),
              child: Text(l.noFolder),
            ),
            for (final f in lib.sortedFolders)
              MenuItemButton(
                onPressed: t.folderId == f.id
                    ? null
                    : () => lib.moveTracks({t.id}, f.id),
                child: Text(f.name),
              ),
            const Divider(height: 1),
            MenuItemButton(
              onPressed: () async {
                final name = await askName(context, l.newFolder);
                if (name != null) {
                  lib.moveTracks({
                    t.id,
                  }, lib.createFolder(name, fallback: l.newFolder).id);
                }
              },
              child: Text(l.newFolderEllipsis),
            ),
          ],
          child: Text(l.moveToFolder),
        ),
        MenuItemButton(
          leadingIcon: const Icon(WsIcons.trash, size: 16),
          onPressed: () => confirmDeleteTrack(context, c, t),
          child: Text(l.delete),
        ),
      ],
    );
  }
}

/// Edits title and artist of an imported or recorded track (#24); the audio file stays unchanged.
Future<void> editTrack(BuildContext context, Library lib, Track t) async {
  final r = await showDialog<(String, String)>(
    context: context,
    builder: (context) => TrackEditDialog(track: t),
  );
  if (r != null) lib.editMetadata(t.id, title: r.$1, artist: r.$2);
}

/// Dialog for title and artist; «Save» is disabled while the title is blank (#24/AK5).
/// Pops (title, artist) or null on cancel.
class TrackEditDialog extends StatefulWidget {
  const TrackEditDialog({super.key, required this.track});
  final Track track;

  @override
  State<TrackEditDialog> createState() => _TrackEditDialogState();
}

class _TrackEditDialogState extends State<TrackEditDialog> {
  late final _title = TextEditingController(text: widget.track.title);
  late final _artist = TextEditingController(text: widget.track.artist ?? '');

  bool get _valid => _title.text.trim().isNotEmpty;

  void _save() {
    if (_valid) Navigator.pop(context, (_title.text, _artist.text));
  }

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.editTrackTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('titleField'),
            controller: _title,
            autofocus: true,
            decoration: InputDecoration(labelText: l.titleLabel),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: WsSpace.s),
          TextField(
            key: const Key('artistField'),
            controller: _artist,
            decoration: InputDecoration(labelText: l.artistLabel),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('editCancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TextButton(
          key: const Key('editSave'),
          onPressed: _valid ? _save : null,
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// Löschen mit Rückfrage (Kontextmenü, Entf-Taste).
Future<void> confirmDeleteTrack(
  BuildContext context,
  AppController c,
  Track t,
) async {
  final l = context.l10n;
  if (await confirm(
    context,
    title: l.deleteNamedTitle(t.title),
    text: l.deleteTrackText,
    action: l.delete,
  )) {
    c.deleteTracks({t.id});
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String text,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            key: const Key('confirm'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Name für einen Ordner abfragen; null bei Abbruch.
Future<String?> askName(
  BuildContext context,
  String title, {
  String initial = '',
}) {
  final text = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const Key('nameField'),
        controller: text,
        autofocus: true,
        decoration: InputDecoration(hintText: context.l10n.nameHint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          key: const Key('nameOk'),
          onPressed: () => Navigator.pop(context, text.text),
          child: Text(context.l10n.ok),
        ),
      ],
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final lib = controller.library;
    final l = context.l10n;
    final platform = Theme.of(context).platform;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            // One line; shrinks in narrow sidebars instead of breaking the word (#31: one more button).
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                l.library,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            key: const Key('addFiles'),
            tooltip: l.addMp3Shortcut(
              shortcutLabel(platform, 'O', command: true),
            ),
            icon: const Icon(WsIcons.add),
            onPressed: () => controller.pickAndImport(),
          ),
          IconButton(
            key: const Key('newFolder'),
            tooltip: l.newFolderShortcut(
              shortcutLabel(platform, 'N', command: true, shift: true),
            ),
            icon: const Icon(WsIcons.folderBadgePlus),
            onPressed: () => newFolder(context, lib),
          ),
          PopupMenuButton<TrackSortOrder>(
            key: const Key('sortMenu'),
            tooltip: l.sort,
            icon: const Icon(WsIcons.sort),
            onSelected: (o) => lib.sortOrder = o,
            itemBuilder: (_) => [
              for (final o in TrackSortOrder.values)
                CheckedPopupMenuItem(
                  value: o,
                  checked: lib.sortOrder == o,
                  child: Text(sortOrderLabel(l, o)),
                ),
            ],
          ),
          PopupMenuButton<Appearance>(
            key: const Key('appearanceMenu'),
            tooltip: l.appearance,
            icon: Icon(switch (lib.appearance) {
              Appearance.system => WsIcons.appearanceAuto,
              Appearance.light => WsIcons.sun,
              Appearance.dark => WsIcons.moon,
            }),
            onSelected: (a) => lib.appearance = a,
            itemBuilder: (_) => [
              for (final a in Appearance.values)
                CheckedPopupMenuItem(
                  key: Key('appearance-${a.name}'),
                  value: a,
                  checked: lib.appearance == a,
                  child: Text(appearanceLabel(l, a)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> newFolder(BuildContext context, Library lib) async {
  final l = context.l10n;
  final name = await askName(context, l.newFolder);
  if (name != null) lib.createFolder(name, fallback: l.newFolder);
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    final l = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(WsIcons.musicNoteList, size: 40, color: grey),
            const SizedBox(height: 10),
            Text(l.noTracks, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              !kIsWeb && Platform.isMacOS
                  ? l.emptyLibraryHintDrop
                  : l.emptyLibraryHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: grey),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('addFirst'),
              onPressed: onAdd,
              child: Text(l.addMp3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Abschnittskopf (Ordner bzw. «Ohne Ordner»); Titel lassen sich darauf ablegen.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    super.key,
    required this.label,
    required this.icon,
    required this.onDrop,
    this.expanded,
    this.onToggle,
    this.menu,
  });

  final String label;
  final IconData icon;
  final void Function(String trackId) onDrop;
  final bool? expanded;
  final VoidCallback? onToggle;
  final List<Widget> Function(BuildContext context)? menu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DragTarget<String>(
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) => _WithMenu(
        menu: menu,
        builder: (context, openMenu) => Material(
          type: candidates.isNotEmpty
              ? MaterialType.canvas
              : MaterialType.transparency,
          color: WsTheme.of(context).amberSoft,
          child: InkWell(
            onTap: onToggle,
            onSecondaryTapUp: openMenu == null
                ? null
                : (e) => openMenu(e.localPosition),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
              child: Row(
                children: [
                  if (expanded != null)
                    Icon(
                      expanded! ? WsIcons.chevronDown : WsIcons.chevronRight,
                      size: 12,
                    ),
                  const SizedBox(width: 6),
                  Icon(icon, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (openMenu != null)
                    IconButton(
                      tooltip: context.l10n.folderActions,
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      icon: const Icon(WsIcons.ellipsis),
                      onPressed: () => openMenu(null),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Storage usage in the library footer (#35/AK5), e.g. «1.2 GB used».
class _StorageLine extends StatelessWidget {
  const _StorageLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('storageLine'),
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 11,
      ),
    ),
  );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text, {required this.onDrop});
  final String text;
  final void Function(String trackId) onDrop;

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onAcceptWithDetails: (d) => onDrop(d.data),
    builder: (context, candidates, _) => Container(
      color: candidates.isNotEmpty
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
          : null,
      padding: const EdgeInsets.fromLTRB(44, 8, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
    ),
  );
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    super.key,
    required this.track,
    required this.artwork,
    required this.selected,
    required this.indent,
    required this.touch,
    required this.onTap,
    required this.onDrop,
    required this.menu,
  });

  final Track track;
  final String? artwork;
  final bool selected, indent, touch;
  final VoidCallback onTap;
  final void Function(String trackId) onDrop;
  final List<Widget> Function(BuildContext context) menu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ws = WsTheme.of(context);
    final st = track.settings;
    final speed = st.speedEnabled ? st.speed : 1.0;
    final loop =
        st.loopEnabled && track.duration > 0 && st.loopEnd > st.loopStart
        ? (st.loopStart / track.duration, st.loopEnd / track.duration)
        : null;
    Widget tile(
      String? openMenuHint,
      void Function(Offset?)? openMenu, {
      bool dropHint = false,
    }) => Material(
      type: selected ? MaterialType.canvas : MaterialType.transparency,
      color: ws.panel2,
      child: InkWell(
        onTap: onTap,
        onSecondaryTapUp: openMenu == null
            ? null
            : (e) => openMenu(e.localPosition),
        child: Container(
          decoration: BoxDecoration(
            border: dropHint
                ? Border(top: BorderSide(color: ws.amber, width: 2))
                : selected
                ? Border.all(color: ws.border)
                : null,
          ),
          constraints: BoxConstraints(minHeight: touch ? 48 : 0),
          padding: EdgeInsets.fromLTRB(indent ? 28 : 12, 6, 4, 6),
          child: Row(
            children: [
              TrackArtwork(path: artwork, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Row(
                      spacing: WsSpace.s,
                      children: [
                        Expanded(
                          child: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        Text(
                          formatTime(track.duration),
                          style: ws.number(
                            12,
                            color: ws.muted,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (track.artist != null)
                      Text(
                        track.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ws.muted,
                        ),
                      ),
                    Row(
                      spacing: WsSpace.s,
                      children: [
                        Expanded(child: _LoopStrip(loop: loop)),
                        Text(
                          context.l10n.rate(speed),
                          style: ws.number(
                            11,
                            color: (speed - 1).abs() < 0.001
                                ? ws.muted
                                : ws.amber,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (openMenu != null)
                IconButton(
                  key: Key('menu:${track.title}'),
                  tooltip: context.l10n.trackActions,
                  visualDensity: touch ? null : VisualDensity.compact,
                  iconSize: 16,
                  icon: const Icon(WsIcons.ellipsis),
                  onPressed: () => openMenu(null),
                ),
            ],
          ),
        ),
      ),
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != track.id,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) => _WithMenu(
        menu: menu,
        builder: (context, openMenu) {
          final feedback = Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(track.title),
            ),
          );
          final child = tile(null, openMenu, dropHint: candidates.isNotEmpty);
          final dimmed = Opacity(opacity: 0.4, child: tile(null, null));
          return touch
              ? LongPressDraggable<String>(
                  data: track.id,
                  feedback: feedback,
                  childWhenDragging: dimmed,
                  child: child,
                )
              : Draggable<String>(
                  data: track.id,
                  feedback: feedback,
                  childWhenDragging: dimmed,
                  child: child,
                );
        },
      ),
    );
  }
}

/// Gespeicherter Loop eines Titels als dünner Balken (Anteile 0–1).
class _LoopStrip extends StatelessWidget {
  const _LoopStrip({required this.loop});
  final (double, double)? loop;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    final l = loop;
    return SizedBox(
      height: 4,
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ws.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (l != null)
              Positioned(
                left: c.maxWidth * l.$1.clamp(0.0, 1.0),
                width: c.maxWidth * (l.$2 - l.$1).clamp(0.02, 1.0),
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: ws.amber,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Kontextmenü an einer Stelle (Rechtsklick) oder unter dem «⋯»-Knopf öffnen.
class _WithMenu extends StatefulWidget {
  const _WithMenu({required this.menu, required this.builder});
  final List<Widget> Function(BuildContext context)? menu;
  final Widget Function(
    BuildContext context,
    void Function(Offset? at)? openMenu,
  )
  builder;

  @override
  State<_WithMenu> createState() => _WithMenuState();
}

class _WithMenuState extends State<_WithMenu> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final items = widget.menu;
    if (items == null) return widget.builder(context, null);
    return MenuAnchor(
      controller: _menu,
      menuChildren: items(context),
      builder: (context, _, _) =>
          widget.builder(context, (at) => _menu.open(position: at)),
    );
  }
}

/// Cover aus der Bibliothek oder Notensymbol.
class TrackArtwork extends StatelessWidget {
  const TrackArtwork({super.key, required this.path, required this.size});
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = path;
    final placeholder = Container(
      width: size,
      height: size,
      color: WsTheme.of(context).panel2,
      child: Icon(
        WsIcons.musicNote,
        size: size * 0.5,
        color: WsTheme.of(context).muted,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size > 60 ? 4 : 3),
      child: p == null
          ? placeholder
          : Image.file(
              File(p),
              key: Key('artwork:$p'),
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * 2).round(),
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}
