// Playing a list from start to end (#114/AK5): which entry plays and which follows. Pure Dart, so the
// order can be tested without a player. #115: the list is a playlist or a folder; shuffle plays each row once
// per pass in a random order, repeat goes on with the list or the track, and «Next» and «Previous» move by
// hand through the same order.
import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals;

/// #115/AK8: repeat off, the list, or the track (in this order on each tap).
enum Repeat {
  off,
  list,
  track;

  /// The mode after this one on a tap: off → list → track → off.
  Repeat get following => values[(index + 1) % values.length];
}

/// Position in a list being played: [index] is the row now loaded, in `Library.playlistTracks` for a
/// playlist or in `Library.sortedTracksIn` for a folder.
class PlayQueue {
  /// A playlist (#114).
  const PlayQueue(String this.playlistId, this.index, {this.order = const []})
    : folderId = null;

  /// #115/AK9: the tracks of a folder; [folderId] null is the section without a folder.
  const PlayQueue.folder(this.folderId, this.index, {this.order = const []})
    : playlistId = null;

  final String? playlistId;
  final String? folderId;
  final int index;

  /// #115/AK10: the rows of this pass in their shuffled order; empty without shuffle.
  final List<int> order;

  bool get isPlaylist => playlistId != null;
  bool get shuffled => order.isNotEmpty;

  /// The same list at row [index], in [order] (or without shuffle).
  PlayQueue at(int index, {List<int> order = const []}) => isPlaylist
      ? PlayQueue(playlistId!, index, order: order)
      : PlayQueue.folder(folderId, index, order: order);

  /// #115/AK10: shuffle switched on: this row first, then the others of the [length] rows in a random order.
  PlayQueue shuffle(int length, Random random) =>
      at(index, order: _pass(length, random, first: index));

  /// Shuffle switched off: the list goes on in its own order after this row.
  PlayQueue unshuffle() => at(index);

  /// A random order of the rows `0..length-1`; [first] (if a row) leads, [notFirst] does not lead if there
  /// is another row to start with (a new pass does not start with the row just played).
  static List<int> _pass(
    int length,
    Random random, {
    int? first,
    int? notFirst,
  }) {
    final rest = [
      for (var i = 0; i < length; i++)
        if (i != first) i,
    ]..shuffle(random);
    if (notFirst != null && rest.length > 1 && rest.first == notFirst) {
      rest
        ..removeAt(0)
        ..insert(1 + random.nextInt(rest.length), notFirst);
    }
    return [if (first != null && first < length) first, ...rest];
  }

  /// The order of this pass for a list of [length] rows; a list that changed meanwhile gets a new pass
  /// that begins with this row.
  List<int> _orderFor(int length, Random random) =>
      order.length == length && order.contains(index)
      ? order
      : _pass(length, random, first: index);

  /// The queue at the row after this one in a list of [length] rows; null where playback ends (#114/AK5).
  /// [manual] is «Next» by hand, which never repeats the track. Repeat «track» plays the same row again at
  /// the end of the track; repeat «list» starts over after the last row, with shuffle in a new order.
  PlayQueue? next(
    int length, {
    Repeat repeat = Repeat.off,
    bool manual = false,
    Random? random,
  }) {
    if (index >= length) return null;
    if (repeat == Repeat.track && !manual) return this;
    final again = repeat != Repeat.off;
    if (!shuffled) {
      if (index + 1 < length) return at(index + 1);
      return again ? at(0) : null;
    }
    final r = random ?? Random();
    final o = _orderFor(length, r);
    final pos = o.indexOf(index);
    if (pos + 1 < o.length) return at(o[pos + 1], order: o);
    if (!again) return null;
    final pass = _pass(length, r, notFirst: index);
    return at(pass.first, order: pass);
  }

  /// #115/AK9: the row before this one, in the shuffled order with shuffle; null at the first row unless
  /// the list repeats (then the last row).
  PlayQueue? previous(
    int length, {
    Repeat repeat = Repeat.off,
    Random? random,
  }) {
    if (index >= length) return null;
    final again = repeat != Repeat.off;
    if (!shuffled) {
      if (index > 0) return at(index - 1);
      return again ? at(length - 1) : null;
    }
    final o = _orderFor(length, random ?? Random());
    final pos = o.indexOf(index);
    if (pos > 0) return at(o[pos - 1], order: o);
    return again ? at(o.last, order: o) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is PlayQueue &&
      other.playlistId == playlistId &&
      other.folderId == folderId &&
      other.index == index &&
      listEquals(other.order, order);

  @override
  int get hashCode =>
      Object.hash(playlistId, folderId, index, Object.hashAll(order));

  @override
  String toString() => isPlaylist
      ? 'PlayQueue($playlistId, $index${shuffled ? ', $order' : ''})'
      : 'PlayQueue.folder($folderId, $index${shuffled ? ', $order' : ''})';
}
