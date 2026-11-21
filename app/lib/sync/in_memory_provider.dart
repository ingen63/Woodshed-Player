// Cloud storage in memory for tests (#37/AK7, #53): never a real account. It can go offline, abort uploads and
// let «another device» write between reading and writing, and it counts every request.
import 'dart:typed_data';

import 'cloud_provider.dart';

class InMemoryProvider implements CloudProvider {
  /// With [conditional] false the storage knows no versions (#53/AK3): every version is empty and a
  /// conditional put throws [UnsupportedError].
  InMemoryProvider({this.conditional = true});

  final bool conditional;
  final _files = <String, CloudFile>{};
  int _version = 0;

  /// Every request: «list prefix», «get name», «put name», «delete name», «quota».
  final requests = <String>[];

  /// No connection: every request throws [CloudOffline].
  bool offline = false;

  /// Uploads of names for which this returns true are aborted ([CloudError], nothing stored).
  bool Function(String name)? abortPut;

  /// Called before a put is applied, e.g. to let another device write in between.
  Future<void> Function(String name)? beforePut;

  /// Stored files (name → contents), for checks in tests.
  Map<String, Uint8List> get files => {
    for (final e in _files.entries) e.key: e.value.bytes,
  };

  String? versionOf(String name) => _files[name]?.version;

  String _next() => conditional ? 'v${++_version}' : '';

  int countOf(String request) => requests.where((r) => r == request).length;

  void _call(String request) {
    requests.add(request);
    if (offline) throw const CloudOffline('in-memory provider offline');
  }

  @override
  Future<List<CloudEntry>> list(String prefix) async {
    _call('list $prefix');
    return [
      for (final e in _files.entries)
        if (e.key.startsWith(prefix))
          CloudEntry(e.key, e.value.version, e.value.bytes.length),
    ];
  }

  @override
  Future<CloudFile?> get(String name) async {
    _call('get $name');
    return _files[name];
  }

  @override
  Future<String> put(
    String name,
    Uint8List bytes, {
    String? ifVersion,
    bool ifAbsent = false,
  }) async {
    _call('put $name');
    if (!conditional && (ifVersion != null || ifAbsent)) {
      throw UnsupportedError('no conditional writes');
    }
    await beforePut?.call(name);
    if (abortPut?.call(name) ?? false) {
      throw CloudError('upload of $name aborted');
    }
    final current = _files[name];
    if ((ifAbsent && current != null) ||
        (ifVersion != null && current?.version != ifVersion)) {
      throw VersionConflict(name);
    }
    final v = _next();
    _files[name] = CloudFile(Uint8List.fromList(bytes), v);
    return v;
  }

  /// Writes as another device would, without counting it as a request.
  void putDirect(String name, Uint8List bytes) =>
      _files[name] = CloudFile(Uint8List.fromList(bytes), _next());

  @override
  Future<void> delete(String name) async {
    _call('delete $name');
    _files.remove(name);
  }

  @override
  Future<CloudQuota> quota() async {
    _call('quota');
    return CloudQuota(
      used: _files.values.fold(0, (s, f) => s + f.bytes.length),
    );
  }
}
