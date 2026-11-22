// Playing a playlist from start to end (#114/AK5): which entry plays and which follows. Pure Dart, so the
// order can be tested without a player. #115 adds repeat and shuffle here, in [PlayQueue.next].

/// Position in a playlist being played: [index] is the row of `Library.playlistTracks` now loaded.
class PlayQueue {
  const PlayQueue(this.playlistId, this.index);

  final String playlistId;
  final int index;

  /// The queue at the row after this one in a playlist of [length] rows; null after the last row, where
  /// playback ends (#114/AK5).
  PlayQueue? next(int length) =>
      index + 1 < length ? PlayQueue(playlistId, index + 1) : null;

  @override
  bool operator ==(Object other) =>
      other is PlayQueue &&
      other.playlistId == playlistId &&
      other.index == index;

  @override
  int get hashCode => Object.hash(playlistId, index);

  @override
  String toString() => 'PlayQueue($playlistId, $index)';
}
