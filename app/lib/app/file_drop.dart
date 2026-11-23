// #121: where files dragged in from outside the app (Finder, file explorer) are dropped.

/// A place in the library that takes dropped files; equal targets are the same place.
sealed class FileDropTarget {
  const FileDropTarget();
}

/// Into playlist [playlistId] before row [at] of its visible list; at its end if [at] is null.
final class PlaylistDropTarget extends FileDropTarget {
  const PlaylistDropTarget(this.playlistId, [this.at]);
  final String playlistId;
  final int? at;

  @override
  bool operator ==(Object other) =>
      other is PlaylistDropTarget &&
      other.playlistId == playlistId &&
      other.at == at;

  @override
  int get hashCode => Object.hash(playlistId, at);
}

/// Into folder [folderId]; null is «Without folder».
final class FolderDropTarget extends FileDropTarget {
  const FolderDropTarget(this.folderId);
  final String? folderId;

  @override
  bool operator ==(Object other) =>
      other is FolderDropTarget && other.folderId == folderId;

  @override
  int get hashCode => folderId.hashCode;
}
