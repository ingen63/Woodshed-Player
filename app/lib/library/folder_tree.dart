// #146: folders nest. Pure helpers for the tree: a valid tree from any set of parent links (missing parents
// and cycles from concurrent moves on two devices resolved), descendants, and the order of the list.
import 'stamps.dart';
import 'track.dart';

/// Every folder with a parent that exists and no cycle. A folder whose parent is missing (deleted, maybe
/// on another device) or itself lies on the top level. #146/AK8: a cycle can only come from moves on two
/// devices at once; the later move wins, so the folder of the cycle whose parent was set first (oldest
/// [parentStamp], ties by ID) goes to the top level. The result depends only on the folders and stamps,
/// so every device ends with the same tree.
List<TrackFolder> validFolderTree(
  List<TrackFolder> folders,
  Hlc? Function(String id) parentStamp,
) {
  final byId = {for (final f in folders) f.id: f};
  final parent = <String, String?>{
    for (final f in folders)
      f.id: byId.containsKey(f.parentId) && f.parentId != f.id
          ? f.parentId
          : null,
  };
  // Each folder has at most one parent, so every cycle is its own; walking up from each folder finds it.
  final done = <String>{};
  for (final start in [...parent.keys]..sort()) {
    final path = <String>[];
    final onPath = <String>{};
    String? at = start;
    while (at != null && !done.contains(at) && onPath.add(at)) {
      path.add(at);
      at = parent[at];
    }
    if (at != null && !done.contains(at)) {
      final cycle = path.sublist(path.indexOf(at));
      String oldest = cycle.first;
      for (final id in cycle.skip(1)) {
        if (_older(id, oldest, parentStamp)) oldest = id;
      }
      parent[oldest] = null;
    }
    done.addAll(path);
  }
  return [
    for (final f in folders)
      f.parentId == parent[f.id] ? f : f.copyWith(parentId: () => parent[f.id]),
  ];
}

/// The parent link of [a] was set before the one of [b]; a link without stamp counts as oldest.
bool _older(String a, String b, Hlc? Function(String id) stamp) {
  final sa = stamp(a);
  final sb = stamp(b);
  if (sa != sb) {
    if (sa == null) return true;
    if (sb == null) return false;
    return sa < sb;
  }
  return a.compareTo(b) < 0;
}

/// [id] and every folder below it, at any depth.
Set<String> folderSubtree(List<TrackFolder> folders, String id) {
  final children = <String?, List<String>>{};
  for (final f in folders) {
    (children[f.parentId] ??= []).add(f.id);
  }
  final found = <String>{};
  final todo = [id];
  while (todo.isNotEmpty) {
    final next = todo.removeLast();
    if (found.add(next)) todo.addAll(children[next] ?? const []);
  }
  return found;
}

/// The folders as the library lists them: each followed by its subfolders, siblings in [sorted] order
/// (already sorted by name); [depth] 0 for the top level. A folder whose parent is not among them shows
/// on the top level.
List<({TrackFolder folder, int depth})> folderTreeOrder(
  List<TrackFolder> sorted,
) {
  final ids = {for (final f in sorted) f.id};
  final children = <String?, List<TrackFolder>>{};
  for (final f in sorted) {
    (children[ids.contains(f.parentId) ? f.parentId : null] ??= []).add(f);
  }
  final out = <({TrackFolder folder, int depth})>[];
  void add(String? parent, int depth) {
    for (final f in children[parent] ?? const <TrackFolder>[]) {
      out.add((folder: f, depth: depth));
      add(f.id, depth + 1);
    }
  }

  add(null, 0);
  return out;
}
