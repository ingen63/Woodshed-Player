// #122: several tracks of the library selected together: ⌘/Ctrl-click toggles one, ⇧-click a range,
// on touch devices a selection mode with check marks. The view shows it; the library acts on [ids].
import 'package:flutter/foundation.dart';

class TrackSelection extends ChangeNotifier {
  final _ids = <String>{};
  String? _anchor;
  bool _mode = false;

  /// The selected track IDs in the order they were selected.
  Set<String> get ids => Set.unmodifiable(_ids);

  bool get isEmpty => _ids.isEmpty;
  int get length => _ids.length;
  bool contains(String id) => _ids.contains(id);

  /// #122/AK2: the selection mode of touch devices (check marks, a tap toggles).
  bool get mode => _mode;

  /// Where a range selection starts: the track clicked last.
  String? get anchor => _anchor;

  /// #122/AK1: ⌘/Ctrl-click adds the track or takes it out.
  void toggle(String id) {
    if (!_ids.remove(id)) _ids.add(id);
    _anchor = id;
    notifyListeners();
  }

  /// #122/AK1: ⇧-click selects the rows from the anchor to [id] in the list [order]; the tracks chosen
  /// before with ⌘-click stay. Without an anchor (or one no longer listed) it selects [id] only.
  void extend(String id, List<String> order) {
    final from = _anchor == null ? -1 : order.indexOf(_anchor!);
    final to = order.indexOf(id);
    if (from < 0 || to < 0) {
      _ids.add(id);
      _anchor = id;
    } else {
      final (a, b) = from <= to ? (from, to) : (to, from);
      _ids.addAll(order.sublist(a, b + 1));
    }
    notifyListeners();
  }

  /// A plain click: no selection, the track becomes the anchor of the next ⇧-click.
  void click(String id) {
    final changed = _ids.isNotEmpty || _mode;
    _ids.clear();
    _mode = false;
    _anchor = id;
    if (changed) notifyListeners();
  }

  /// #122/AK2: long press or «Select» starts the selection mode, with [id] selected if given.
  void start([String? id]) {
    _mode = true;
    if (id != null) {
      _ids.add(id);
      _anchor = id;
    }
    notifyListeners();
  }

  /// #122/AK6: Escape, a click on an empty area or «Done» ends the selection (and its mode).
  void clear() {
    if (_ids.isEmpty && !_mode) return;
    _ids.clear();
    _mode = false;
    notifyListeners();
  }

  /// Drops tracks no longer in the library (deleted here or on another device).
  void retain(bool Function(String id) exists) {
    final before = _ids.length;
    _ids.removeWhere((id) => !exists(id));
    if (_ids.length != before) notifyListeners();
  }

  /// #122/AK3: the selected tracks in the order of the list [order]; selected tracks it does not show
  /// (e.g. in a closed folder) follow in the order they were selected.
  List<String> inOrder(List<String> order) {
    final shown = order.toSet();
    return [
      for (final id in order)
        if (_ids.contains(id)) id,
      for (final id in _ids)
        if (!shown.contains(id)) id,
    ];
  }
}
