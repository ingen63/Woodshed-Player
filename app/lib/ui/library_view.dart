// Bibliotheksliste (#17), Vorlage TrackListView.swift: Ordner als Abschnitte, Ziehen zum Sortieren und
// in Ordner, Kontextmenüs (Rechtsklick bzw. «⋯»), Bestätigung vor dem Löschen.
// #114: playlists below the folders, each with its tracks in its own order, shared or only on this device.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app/app_controller.dart';
import '../app/file_drop.dart';
import '../library/library.dart';
import '../player/play_queue.dart';
import '../time_format.dart';
import 'about_dialog.dart';
import 'file_drop.dart';
import 'sync_settings.dart';
import 'messages.dart';
import 'style.dart';
import 'trim_view.dart';

class LibraryView extends StatefulWidget {
  LibraryView({
    super.key,
    required this.controller,
    this.onSelected,
    bool? touch,
    this.cacheControls = kIsWeb,
    this.searchFocus,
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

  /// #39/AK3: the device is a cache of the cloud (browser): the storage line opens the cache limit and
  /// tracks can be kept offline. Desktop and mobile keep every file.
  final bool cacheControls;

  /// #115/AK11: focus of the search field, given by the window so that ⌘K reaches it.
  final FocusNode? searchFocus;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final _collapsed = <String>{};

  /// #114: playlists are collapsed until opened (a library may have many).
  final _openPlaylists = <String>{};

  AppController get c => widget.controller;
  Library get lib => c.library;

  /// #115/AK11: the search (⌘K): tracks whose title or artist contain it, as one list.
  final _search = TextEditingController();
  FocusNode? _ownSearchFocus;
  FocusNode get _searchFocus =>
      widget.searchFocus ?? (_ownSearchFocus ??= FocusNode());

  @override
  void dispose() {
    _search.dispose();
    _ownSearchFocus?.dispose();
    super.dispose();
  }

  /// #115/AK9: a track chosen in the library plays within its folder.
  void _select(Track t) {
    c.selectInFolder(t);
    widget.onSelected?.call();
  }

  List<Track> _matches(String query) {
    final q = query.toLowerCase();
    return [
      for (final t in lib.sortedTracks)
        if (t.title.toLowerCase().contains(q) ||
            (t.artist?.toLowerCase().contains(q) ?? false))
          t,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([c, lib, c.player, c.sync, c.fileDropHover]),
      builder: (context, _) {
        final folders = lib.sortedFolders;
        final loose = lib.sortedTracksIn(null);
        final empty =
            lib.tracks.isEmpty && folders.isEmpty && lib.playlists.isEmpty;
        final query = _search.text.trim();
        return Column(
          children: [
            _Header(controller: c),
            if (!empty)
              _SearchField(
                controller: _search,
                focus: _searchFocus,
                onChanged: () => setState(() {}),
              ),
            if (lib.isImporting) const LinearProgressIndicator(minHeight: 2),
            const Divider(height: 1),
            if (lib.heldNames case final names when names.isNotEmpty)
              _HeldHint(
                count: names.length,
                onDecide: () => showHeldDialog(context, lib),
              ),
            Expanded(
              child: empty
                  ? _EmptyLibrary(onAdd: () => c.pickAndImport())
                  : query.isNotEmpty
                  ? _searchResults(query)
                  : ListView(
                      key: const Key('libraryList'),
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        // #123: all tracks in one section, closed by default
                        _SectionHeader(
                          key: const Key('section:library'),
                          label: context.l10n.library,
                          icon: WsIcons.musicNote,
                          expanded: lib.libraryOpen,
                          onToggle: () => lib.setLibraryOpen(!lib.libraryOpen),
                          // #123/AK5: files from outside go in without a folder
                          accepts: (_) => false,
                          onDrop: (_) {},
                          fileTarget: const FolderDropTarget(null),
                          fileHover: _hovered(const FolderDropTarget(null)),
                          trailing: [
                            Text(
                              '${lib.tracks.length}',
                              style: WsTheme.of(context)
                                  .number(12, color: WsTheme.of(context).muted),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                        if (lib.libraryOpen) ..._allTracks(folders, loose),
                        _PlaylistsHeader(
                          onAdd: () => newPlaylist(context, lib),
                        ),
                        for (final p in lib.sortedPlaylists) ..._playlist(p),
                      ],
                    ),
            ),
            // #54/AK7, AK8: the sync status; a tap opens the settings
            _SyncLine(controller: widget.controller),
            if (lib.storage case final s?)
              _StorageLine(
                [
                  storageLabel(context.l10n, s),
                  if (widget.cacheControls)
                    context.l10n.storageCacheLimit(
                      formatBytes(lib.cacheLimit, context.l10n.localeName),
                    ),
                ].join(' · '),
                onTap: widget.cacheControls
                    ? () => showCacheLimitDialog(context, lib)
                    : null,
              ),
          ],
        );
      },
    );
  }

  Widget _searchResults(String query) {
    final found = _matches(query);
    if (found.isEmpty) {
      return _Placeholder(context.l10n.noSearchResults, onDrop: (_) {});
    }
    return ListView(
      key: const Key('searchResults'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [for (final t in found) _row(t)],
    );
  }

  /// #123: the section «Library»: tracks without a folder, then the folders.
  List<Widget> _allTracks(List<TrackFolder> folders, List<Track> loose) => [
    if (folders.isNotEmpty)
      _SectionHeader(
        key: const Key('section:none'),
        label: context.l10n.noFolder,
        icon: WsIcons.tray,
        onDrop: (id) => lib.placeTrack(id as String, null),
        fileTarget: const FolderDropTarget(null),
        fileHover: _hovered(const FolderDropTarget(null)),
      ),
    for (final t in loose) _row(t, fileTarget: const FolderDropTarget(null)),
    if (loose.isEmpty && folders.isNotEmpty)
      _Placeholder(
        context.l10n.noTracksWithoutFolder,
        onDrop: (id) => lib.placeTrack(id, null),
        fileTarget: const FolderDropTarget(null),
        fileHover: _hovered(const FolderDropTarget(null)),
      ),
    for (final f in folders) ..._folder(f),
  ];

  /// #121/AK4: files dragged in from outside are over [target].
  bool _hovered(FileDropTarget target) => c.fileDropHover.value == target;

  List<Widget> _folder(TrackFolder f) {
    final l = context.l10n;
    final open = !_collapsed.contains(f.id);
    final tracks = lib.sortedTracksIn(f.id);
    final files = FolderDropTarget(f.id);
    return [
      _SectionHeader(
        key: Key('folder:${f.name}'),
        label: f.name,
        icon: WsIcons.folder,
        expanded: open,
        onToggle: () => setState(
          () => open ? _collapsed.add(f.id) : _collapsed.remove(f.id),
        ),
        onDrop: (id) => lib.placeTrack(id as String, f.id),
        fileTarget: files,
        fileHover: _hovered(files),
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
          CheckboxMenuButton(
            key: Key('syncFolder:${f.name}'),
            value: f.sync,
            onChanged: (v) => lib.setFolderSync(f.id, v ?? true),
            child: Text(l.syncFolder),
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
        for (final t in tracks) _row(t, indent: true, fileTarget: files),
        if (tracks.isEmpty)
          _Placeholder(
            l.emptyFolder,
            onDrop: (id) => lib.placeTrack(id, f.id),
            fileTarget: files,
            fileHover: _hovered(files),
          ),
      ],
    ];
  }

  /// #114/AK9: a playlist kept on this device gets a new ID; it stays open if it was.
  void _setShared(String id, bool shared) {
    final next = c.setPlaylistShared(id, shared);
    if (_openPlaylists.remove(id)) setState(() => _openPlaylists.add(next));
  }

  /// #114: a playlist as a section: its tracks in its order, repeats included.
  List<Widget> _playlist(Playlist p) {
    final l = context.l10n;
    final ws = WsTheme.of(context);
    final open = _openPlaylists.contains(p.id);
    final tracks = lib.playlistTracks(p.id);
    final q = c.queue;
    final files = PlaylistDropTarget(p.id);
    void drop(Object d, int at) => switch (d) {
      final String id => lib.addToPlaylist(p.id, [id], at: at),
      _EntryDrag(:final playlistId, :final index) when playlistId == p.id =>
        lib.movePlaylistEntry(p.id, index, at),
      _EntryDrag(:final trackId) => lib.addToPlaylist(p.id, [trackId], at: at),
      _ => null,
    };
    return [
      _SectionHeader(
        key: Key('playlist:${p.name}'),
        label: p.name,
        icon: WsIcons.musicNoteList,
        expanded: open,
        onToggle: () => setState(
          () => open ? _openPlaylists.remove(p.id) : _openPlaylists.add(p.id),
        ),
        accepts: (d) => d is String || d is _EntryDrag,
        onDrop: (d) => drop(d, tracks.length),
        fileTarget: files,
        fileHover: _hovered(files),
        menuTooltip: l.playlistActions,
        trailing: [
          // #114/AK11: cloud = on all devices, device = only here
          Tooltip(
            message: p.shared ? l.playlistOnAllDevices : l.playlistOnThisDevice,
            child: Icon(
              p.shared
                  ? WsIcons.cloud
                  : (widget.touch ? WsIcons.phone : WsIcons.laptop),
              key: Key('${p.shared ? 'shared' : 'local'}:${p.name}'),
              size: 14,
              color: ws.muted,
              semanticLabel: p.shared
                  ? l.playlistOnAllDevices
                  : l.playlistOnThisDevice,
            ),
          ),
          const SizedBox(width: 6),
          Text('${tracks.length}', style: ws.number(12, color: ws.muted)),
          IconButton(
            key: Key('playPlaylist:${p.name}'),
            tooltip: l.playPlaylist,
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            icon: const Icon(WsIcons.play),
            onPressed: tracks.isEmpty ? null : () => c.playPlaylist(p.id),
          ),
        ],
        menu: (context) => [
          MenuItemButton(
            leadingIcon: const Icon(WsIcons.play, size: 16),
            onPressed: tracks.isEmpty ? null : () => c.playPlaylist(p.id),
            child: Text(l.playPlaylist),
          ),
          MenuItemButton(
            leadingIcon: const Icon(WsIcons.pencil, size: 16),
            onPressed: () async {
              final name = await askName(
                context,
                l.renamePlaylist,
                initial: p.name,
              );
              if (name != null) lib.renamePlaylist(p.id, name);
            },
            child: Text(l.renameEllipsis),
          ),
          CheckboxMenuButton(
            key: Key('shareAll:${p.name}'),
            value: p.shared,
            onChanged: (_) => _setShared(p.id, true),
            child: Text(l.playlistOnAllDevices),
          ),
          CheckboxMenuButton(
            key: Key('shareLocal:${p.name}'),
            value: !p.shared,
            onChanged: (_) => _setShared(p.id, false),
            child: Text(l.playlistOnThisDevice),
          ),
          MenuItemButton(
            key: Key('deletePlaylist:${p.name}'),
            leadingIcon: const Icon(WsIcons.trash, size: 16),
            onPressed: () async {
              if (await confirm(
                context,
                title: l.deleteNamedTitle(p.name),
                text: l.deletePlaylistText,
                action: l.deletePlaylist,
              )) {
                lib.deletePlaylist(p.id);
              }
            },
            child: Text(l.deletePlaylist),
          ),
        ],
      ),
      if (open) ...[
        for (final (i, t) in tracks.indexed)
          _TrackRow(
            key: Key('entry:${p.name}:$i'),
            track: t,
            artwork: lib.artworkPath(t),
            selected: q == PlayQueue(p.id, i) && c.player.trackId == t.id,
            onlyElsewhere: !lib.hasFile(t.id) && !c.sync.inCloud(t.id),
            onlyInCloud: !lib.hasFile(t.id) && c.sync.inCloud(t.id),
            fetching: c.fetching == t.id,
            indent: true,
            touch: widget.touch,
            onTap: () {
              c.playPlaylist(p.id, index: i, play: false);
              widget.onSelected?.call();
            },
            dragData: _EntryDrag(p.id, i, t.id),
            accepts: (d) =>
                d is String ||
                (d is _EntryDrag && (d.playlistId != p.id || d.index != i)),
            onDrop: (d) => drop(d, i),
            fileTarget: PlaylistDropTarget(p.id, i),
            fileHover: _hovered(PlaylistDropTarget(p.id, i)),
            menu: (context) => [
              MenuItemButton(
                key: const Key('removeFromPlaylist'),
                leadingIcon: const Icon(WsIcons.close, size: 16),
                onPressed: () => lib.removeFromPlaylist(p.id, i),
                child: Text(l.removeFromPlaylist),
              ),
              MenuItemButton(
                leadingIcon: const Icon(WsIcons.pencil, size: 16),
                onPressed: () => editTrack(context, lib, t),
                child: Text(l.editTrackEllipsis),
              ),
              trimMenuItem(context, c, t),
            ],
          ),
        if (tracks.isEmpty)
          _Placeholder(
            l.emptyPlaylist,
            onDrop: (id) => lib.addToPlaylist(p.id, [id]),
            fileTarget: files,
            fileHover: _hovered(files),
          ),
      ],
    ];
  }

  /// [fileTarget]: where files dropped on the row go (#121), the row's folder; none in the search.
  Widget _row(Track t, {bool indent = false, FileDropTarget? fileTarget}) {
    final l = context.l10n;
    return _TrackRow(
      key: Key('track:${t.title}'),
      track: t,
      artwork: lib.artworkPath(t),
      selected: c.player.trackId == t.id,
      onlyElsewhere: !lib.hasFile(t.id) && !c.sync.inCloud(t.id),
      onlyInCloud: !lib.hasFile(t.id) && c.sync.inCloud(t.id),
      fetching: c.fetching == t.id,
      indent: indent,
      touch: widget.touch,
      onTap: () => _select(t),
      onDrop: (id) => lib.placeTrack(id as String, t.folderId, beforeId: t.id),
      fileTarget: fileTarget,
      menu: (context) => [
        MenuItemButton(
          key: const Key('editTrack'),
          leadingIcon: const Icon(WsIcons.pencil, size: 16),
          onPressed: () => editTrack(context, lib, t),
          child: Text(l.editTrackEllipsis),
        ),
        trimMenuItem(context, c, t),
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
        // #114/AK2: add to a playlist; the same track may go in several times (AK3)
        SubmenuButton(
          key: const Key('addToPlaylist'),
          leadingIcon: const Icon(WsIcons.musicNoteList, size: 16),
          menuChildren: [
            for (final p in lib.sortedPlaylists)
              MenuItemButton(
                key: Key('addTo:${p.name}'),
                onPressed: () => lib.addToPlaylist(p.id, [t.id]),
                child: Text(p.name),
              ),
            if (lib.playlists.isNotEmpty) const Divider(height: 1),
            MenuItemButton(
              key: const Key('addToNewPlaylist'),
              onPressed: () async {
                final name = await askName(context, l.newPlaylist);
                if (name != null) {
                  lib.addToPlaylist(
                    lib.createPlaylist(name, fallback: l.newPlaylist).id,
                    [t.id],
                  );
                }
              },
              child: Text(l.newPlaylistEllipsis),
            ),
          ],
          child: Text(l.addToPlaylist),
        ),
        CheckboxMenuButton(
          key: const Key('dontUpload'),
          value: t.noUpload,
          onChanged: (v) => lib.setNoUpload({t.id}, v ?? false),
          child: Text(l.dontUpload),
        ),
        if (widget.cacheControls)
          CheckboxMenuButton(
            key: const Key('keepOffline'),
            value: lib.keptOffline(t.id),
            onChanged: (v) => lib.setKeepOffline({t.id}, v ?? false),
            child: Text(l.keepOffline),
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
/// #116/AK1: «Trim start and end …»; greyed out for file types the core cannot trim, with the reason below it
/// (#120: M4A can be trimmed).
Widget trimMenuItem(BuildContext context, AppController c, Track t) {
  final l = context.l10n;
  final can = Library.trimmable(t);
  return MenuItemButton(
    key: const Key('trimTrack'),
    leadingIcon: const Icon(WsIcons.scissors, size: 16),
    onPressed: can ? () => openTrimView(context, c, t) : null,
    child: can
        ? Text(l.trimTrackEllipsis)
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.trimTrackEllipsis),
              Text(
                l.trimUnavailable,
                key: const Key('trimUnavailable'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
  );
}

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
                  key: Key('sort-${o.name}'),
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
          IconButton(
            key: const Key('aboutButton'),
            tooltip: l.aboutApp,
            icon: const Icon(WsIcons.info),
            onPressed: () => showAbout(context, controller.files),
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

/// #114/AK1: a new playlist, shared on all devices (AK9).
Future<void> newPlaylist(BuildContext context, Library lib) async {
  final l = context.l10n;
  final name = await askName(context, l.newPlaylist);
  if (name != null) lib.createPlaylist(name, fallback: l.newPlaylist);
}

/// #115/AK11: search field of the library; ⌘K puts the cursor into it, Esc empties it.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onChanged,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final platform = Theme.of(context).platform;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            controller.clear();
            focus.unfocus();
            onChanged();
          },
        },
        child: TextField(
          key: const Key('librarySearch'),
          controller: controller,
          focusNode: focus,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(WsIcons.search, size: 16),
            hintText: KeyboardPresence.available(platform)
                ? '${l.searchLibrary}  ${shortcutLabel(platform, 'K', command: true)}'
                : l.searchLibrary,
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    key: const Key('librarySearchClear'),
                    tooltip: l.close,
                    icon: const Icon(WsIcons.close, size: 14),
                    onPressed: () {
                      controller.clear();
                      onChanged();
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// #114: a row of a playlist being dragged: moved within its playlist, copied into another one. Library
/// rows drag the track ID (a String) instead, which folders accept.
class _EntryDrag {
  const _EntryDrag(this.playlistId, this.index, this.trackId);
  final String playlistId;
  final int index;
  final String trackId;
}

/// #114: heading of the playlists with «New playlist».
class _PlaylistsHeader extends StatelessWidget {
  const _PlaylistsHeader({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.playlists.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          IconButton(
            key: const Key('newPlaylist'),
            tooltip: context.l10n.newPlaylist,
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            icon: const Icon(WsIcons.add),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
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
              emptyLibraryHint(l, currentHintPlatform),
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
    this.accepts = _isTrackId,
    this.expanded,
    this.onToggle,
    this.menu,
    this.menuTooltip,
    this.trailing = const [],
    this.fileTarget,
    this.fileHover = false,
  });

  final String label;
  final IconData icon;

  /// Called with the dragged data: a track ID (String), or a playlist row (#114) where [accepts] allows it.
  final void Function(Object data) onDrop;
  final bool Function(Object data) accepts;
  final bool? expanded;
  final VoidCallback? onToggle;
  final List<Widget> Function(BuildContext context)? menu;

  /// Tooltip of the «⋯» button; folder actions unless given.
  final String? menuTooltip;

  /// Shown before the «⋯» button (#114: sharing, count, play).
  final List<Widget> trailing;

  /// #121: where files dropped from outside go; [fileHover] while they are over it.
  final FileDropTarget? fileTarget;
  final bool fileHover;

  static bool _isTrackId(Object d) => d is String;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = DragTarget<Object>(
      onWillAcceptWithDetails: (d) => accepts(d.data),
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) => _WithMenu(
        menu: menu,
        builder: (context, openMenu) => Material(
          type: candidates.isNotEmpty || fileHover
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
                  ...trailing,
                  if (openMenu != null)
                    IconButton(
                      tooltip: menuTooltip ?? context.l10n.folderActions,
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
    return FileDropRegion(target: fileTarget, child: target);
  }
}

/// #54/AK8: the sync status in the library footer, e.g. «Sync: Up to date»; a tap opens the settings.
class _SyncLine extends StatelessWidget {
  const _SyncLine({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListenableBuilder(
      listenable: controller.cloud,
      builder: (context, _) => InkWell(
        key: const Key('syncButton'),
        onTap: () => showSyncSettings(context, controller),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: WsLayout.of(context).target),
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Icon(WsIcons.cloud, size: 16, color: muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.syncLine(syncStatusText(l, controller.cloud)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Storage usage in the library footer (#35/AK5), e.g. «1.2 GB used». With [onTap] it opens the cache
/// limit (#39/AK3).
class _StorageLine extends StatelessWidget {
  const _StorageLine(this.text, {this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      key: const Key('storageLine'),
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: onTap == null ? 0 : WsLayout.of(context).target,
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Text(
        text,
        maxLines: onTap == null ? 1 : 2, // phone: the limit must stay readable
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
        ),
      ),
    ),
  );
}

/// #107: own tracks and folders are held back from the sync; the button opens the question. Shown in the
/// library instead of a dialog in the middle of practising.
class _HeldHint extends StatelessWidget {
  const _HeldHint({required this.count, required this.onDecide});
  final int count;
  final VoidCallback onDecide;

  @override
  Widget build(BuildContext context) {
    final ws = WsTheme.of(context);
    return Container(
      key: const Key('heldHint'),
      color: ws.panel2,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      // text above the button: the library column may be narrow
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            spacing: WsSpace.s,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(WsIcons.warning, size: 18, color: ws.amber),
              Expanded(child: Text(context.l10n.heldHint(count))),
            ],
          ),
          TextButton(
            key: const Key('heldDecide'),
            onPressed: onDecide,
            child: Text(context.l10n.heldDecide),
          ),
        ],
      ),
    );
  }
}

/// Names shown in the question about held tracks and folders (#107); the rest is counted.
const heldNamesShown = 10;

/// #107: asks whether to keep or remove the held tracks and folders. «Later» or closing leaves them held,
/// and the hint stays.
Future<void> showHeldDialog(BuildContext context, Library lib) async {
  final names = lib.heldNames;
  if (names.isEmpty) return;
  final keep = await showDialog<bool>(
    context: context,
    builder: (context) => HeldDialog(names: names),
  );
  if (keep == true) {
    await lib.keepHeld();
  } else if (keep == false) {
    await lib.removeHeld();
  }
}

/// The question of [showHeldDialog]: pops true for «Keep», false for «Remove», null for «Later».
class HeldDialog extends StatelessWidget {
  const HeldDialog({super.key, required this.names});
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final more = names.length - heldNamesShown;
    return AlertDialog(
      key: const Key('heldDialog'),
      title: Text(l.heldTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: WsSpace.s,
          children: [
            Text(l.heldText(names.length)),
            Text(
              [
                for (final n in names.take(heldNamesShown)) '• $n',
                if (more > 0) l.heldMore(more),
              ].join('\n'),
              key: const Key('heldNames'),
            ),
            Text(l.heldExplain),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('heldLater'),
          onPressed: () => Navigator.pop(context),
          child: Text(l.heldLater),
        ),
        TextButton(
          key: const Key('heldRemove'),
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.heldRemove),
        ),
        TextButton(
          key: const Key('heldKeep'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.heldKeep),
        ),
      ],
    );
  }
}

/// Limits offered for the audio cache (#39/AK3), in bytes.
const cacheLimitChoices = [
  500000000,
  1000000000,
  2000000000,
  5000000000,
  10000000000,
  20000000000,
];

/// #39/AK3: chooses the device-local limit of the audio cache.
Future<void> showCacheLimitDialog(BuildContext context, Library lib) async {
  final l = context.l10n;
  final used = await lib.cacheSize();
  if (!context.mounted) return;
  final choices = {...cacheLimitChoices, lib.cacheLimit}.toList()..sort();
  final chosen = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('cacheLimitDialog'),
      title: Text(l.cacheLimitTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.cacheLimitHint),
            const SizedBox(height: 8),
            Text(
              l.cacheLimitUsed(formatBytes(used, l.localeName)),
              key: const Key('cacheUsed'),
            ),
            RadioGroup<int>(
              groupValue: lib.cacheLimit,
              onChanged: (v) => Navigator.pop(context, v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in choices)
                    RadioListTile<int>(
                      key: Key('cacheLimit:$c'),
                      value: c,
                      title: Text(formatBytes(c, l.localeName)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    ),
  );
  if (chosen != null) await lib.setCacheLimit(chosen);
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(
    this.text, {
    required this.onDrop,
    this.fileTarget,
    this.fileHover = false,
  });
  final String text;
  final void Function(String trackId) onDrop;

  /// #121: where files dropped from outside go; [fileHover] while they are over it.
  final FileDropTarget? fileTarget;
  final bool fileHover;

  @override
  Widget build(BuildContext context) =>
      FileDropRegion(target: fileTarget, child: _target(context));

  Widget _target(BuildContext context) => DragTarget<String>(
    onAcceptWithDetails: (d) => onDrop(d.data),
    builder: (context, candidates, _) => Container(
      color: candidates.isNotEmpty || fileHover
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
    this.onlyElsewhere = false,
    this.onlyInCloud = false,
    this.fetching = false,
    required this.indent,
    required this.touch,
    required this.onTap,
    required this.onDrop,
    required this.menu,
    this.dragData,
    this.accepts,
    this.fileTarget,
    this.fileHover = false,
  });

  final Track track;
  final String? artwork;
  final bool selected, indent, touch;

  /// The audio file is on another device only (#37/AK5).
  final bool onlyElsewhere;

  /// The audio file is in the cloud only and loads when played (#39/AK4); [fetching] while it does.
  final bool onlyInCloud, fetching;
  final VoidCallback onTap;

  /// Called with the dragged data: a track ID (String) or a playlist row (#114).
  final void Function(Object data) onDrop;
  final List<Widget> Function(BuildContext context) menu;

  /// What a drag of this row carries; the track ID unless given (#114: a playlist row).
  final Object? dragData;

  /// Which drops this row takes; by default another track of the library.
  final bool Function(Object data)? accepts;

  /// #121: where files dropped from outside go; [fileHover] while they are over this row.
  final FileDropTarget? fileTarget;
  final bool fileHover;

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
                    if (onlyElsewhere)
                      Text(
                        context.l10n.fileOnOneDevice,
                        key: Key('onlyElsewhere:${track.title}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ws.amber,
                        ),
                      ),
                    if (onlyInCloud)
                      Row(
                        key: Key('onlyInCloud:${track.title}'),
                        spacing: WsSpace.s,
                        children: [
                          if (fetching)
                            const SizedBox.square(
                              dimension: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
                            )
                          else
                            Icon(WsIcons.cloud, size: 12, color: ws.muted),
                          Flexible(
                            child: Text(
                              fetching
                                  ? context.l10n.loadingFromCloud
                                  : context.l10n.onlyInCloud,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ws.muted,
                              ),
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

    final data = dragData ?? track.id;
    final target = DragTarget<Object>(
      onWillAcceptWithDetails: (d) =>
          accepts?.call(d.data) ?? (d.data is String && d.data != track.id),
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
          final child = tile(
            null,
            openMenu,
            dropHint: candidates.isNotEmpty || fileHover,
          );
          final dimmed = Opacity(opacity: 0.4, child: tile(null, null));
          return touch
              ? LongPressDraggable<Object>(
                  data: data,
                  feedback: feedback,
                  childWhenDragging: dimmed,
                  child: child,
                )
              : Draggable<Object>(
                  data: data,
                  feedback: feedback,
                  childWhenDragging: dimmed,
                  child: child,
                );
        },
      ),
    );
    return FileDropRegion(target: fileTarget, child: target);
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
