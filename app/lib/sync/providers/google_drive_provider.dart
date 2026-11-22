// Google Drive as storage of the sync (#54, M3 in docs/KONZEPT-SYNC.md). With the right `drive.file` the app
// sees only what it created itself. The first device creates the folder `WoodshedPlayer` in My Drive;
// further devices with the same account find it by its name (AK2). Paths of the layout from #53
// (`format.json`, `devices/…`, `backup/<id>/…`, `audio/…`) are real subfolders; the provider maps them to
// file IDs and remembers them. Drive allows two files of the same name in one folder: the second one (by
// creation time) is listed as `<name> (1).<ext>`, which the engine takes for a conflict copy (#53/AK6).
// Large files go up in blocks through a resumable session that continues after an abort (AK4).
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../cloud_provider.dart';
import 'google_auth.dart';
import 'http_transport.dart';

const _folderType = 'application/vnd.google-apps.folder';
final _api = Uri.parse('https://www.googleapis.com/drive/v3/');
final _upload = Uri.parse('https://www.googleapis.com/upload/drive/v3/');

/// A file or folder of Drive as the provider knows it.
class _Item {
  const _Item(this.id, this.version, this.size, {this.folder = false});
  final String id;
  final String version;
  final int size;
  final bool folder;
}

/// An upload session that was cut off: continued on the next put of the same file.
class _Session {
  const _Session(this.uri, this.length);
  final Uri uri;
  final int length;
}

class GoogleDriveProvider implements CloudProvider {
  GoogleDriveProvider({
    required this.transport,
    required this.auth,
    this.rootName = 'WoodshedPlayer',
    this.resumableAbove = 5 * 1024 * 1024,
    this.chunkSize = 8 * 1024 * 1024,
  }) : assert(chunkSize % (256 * 1024) == 0, 'Drive wants 256 KiB multiples');

  final HttpTransport transport;
  final GoogleAuth auth;

  /// Name of the app's folder in My Drive.
  final String rootName;

  /// Files larger than this go up in blocks (AK4).
  final int resumableAbove;

  /// Size of one block; a multiple of 256 KiB.
  final int chunkSize;

  String? _root;
  Future<String?>? _finding;

  /// Folder path (`''` = the app's folder, `devices`, `backup/<id>`) → ID.
  final _folders = <String, String>{};

  /// File path → item, from the last listing of its folder.
  final _files = <String, _Item>{};
  final _sessions = <String, _Session>{};
  bool _closed = false;

  /// Bytes sent in upload blocks (tests of AK4).
  int sentBytes = 0;

  /// Ends all traffic (sign-out, #54/AK11): every further call throws without a request.
  void close() {
    _closed = true;
    _sessions.clear();
    transport.close();
  }

  // ---- requests ----

  Future<HttpReply> _send(HttpCall Function() build) async {
    if (_closed) throw const CloudSignInRequired('signed out');
    for (var attempt = 0; ; attempt++) {
      final call = build();
      call.headers['Authorization'] = 'Bearer ${await auth.token()}';
      final reply = await transport.send(call);
      if (reply.status != 401) return reply;
      auth.rejected();
      if (attempt > 0) throw const CloudSignInRequired('token refused');
    }
  }

  static Never _fail(String what, HttpReply r) {
    final reason = switch (r.json['error']) {
      final Map<Object?, Object?> e => switch (e['errors']) {
        final List<Object?> l when l.isNotEmpty && l.first is Map =>
          (l.first as Map)['reason'],
        _ => e['message'],
      },
      _ => null,
    };
    throw CloudError('$what: ${r.status}${reason == null ? '' : ' $reason'}');
  }

  static String _quote(String s) =>
      "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

  // ---- folders and IDs ----

  /// ID of the app's folder; created only if [create] (the first write, AK2).
  Future<String?> _rootId({required bool create}) async {
    if (_root case final r?) return r;
    final found = await (_finding ??= _findRoot().whenComplete(
      () => _finding = null,
    ));
    if (found != null || !create) return found;
    final made = await _send(
      () => HttpCall.json('POST', _api.resolve('files?fields=id'), {
        'name': rootName,
        'mimeType': _folderType,
      }),
    );
    if (!made.ok) _fail('create folder', made);
    // two devices may create it at the same moment: the oldest one wins, the own empty one goes
    final oldest = await _findRoot();
    final mine = made.json['id'] as String;
    if (oldest != null && oldest != mine) {
      await _send(() => HttpCall('DELETE', _api.resolve('files/$mine')));
      return _root = oldest;
    }
    return _root = mine;
  }

  Future<String?> _findRoot() async {
    final q =
        'name = ${_quote(rootName)} and mimeType = ${_quote(_folderType)} '
        "and 'root' in parents and trashed = false";
    final r = await _send(
      () => HttpCall(
        'GET',
        _api
            .resolve('files')
            .replace(
              queryParameters: {
                'q': q,
                'spaces': 'drive',
                'orderBy': 'createdTime',
                'fields': 'files(id)',
                'pageSize': '10',
              },
            ),
      ),
    );
    if (!r.ok) _fail('find folder', r);
    final files = r.json['files'];
    final id = files is List && files.isNotEmpty
        ? (files.first as Map)['id'] as String?
        : null;
    if (id != null) _root = id;
    return id;
  }

  /// ID of the folder at [path]; missing folders are created only if [create].
  Future<String?> _folder(String path, {required bool create}) async {
    if (path.isEmpty) return _rootId(create: create);
    if (_folders[path] case final id?) return id;
    final slash = path.lastIndexOf('/');
    final parentPath = slash < 0 ? '' : path.substring(0, slash);
    final parent = await _folder(parentPath, create: create);
    if (parent == null) return null;
    await _children(parentPath, parent);
    if (_folders[path] case final id?) return id;
    if (!create) return null;
    final made = await _send(
      () => HttpCall.json('POST', _api.resolve('files?fields=id'), {
        'name': path.substring(slash + 1),
        'mimeType': _folderType,
        'parents': [parent],
      }),
    );
    if (!made.ok) _fail('create folder', made);
    return _folders[path] = made.json['id'] as String;
  }

  /// Lists the folder [path] (ID [id]) and refreshes what the provider knows of it. Returns the items by
  /// their path; a name found twice gets « (n)» before its extension.
  Future<Map<String, _Item>> _children(String path, String id) async {
    final items = <String, _Item>{};
    String? page;
    do {
      final r = await _send(
        () => HttpCall(
          'GET',
          _api
              .resolve('files')
              .replace(
                queryParameters: {
                  'q': '${_quote(id)} in parents and trashed = false',
                  'spaces': 'drive',
                  'orderBy': 'createdTime',
                  'fields': 'nextPageToken,files(id,name,mimeType,size,version,createdTime)',
                  'pageSize': '1000',
                  'pageToken': ?page,
                },
              ),
        ),
      );
      if (!r.ok) _fail('list', r);
      for (final f in (r.json['files'] as List? ?? const [])) {
        final m = f as Map;
        final name = m['name'] as String? ?? '';
        if (name.isEmpty || name.contains('/')) continue;
        final folder = m['mimeType'] == _folderType;
        var full = path.isEmpty ? name : '$path/$name';
        for (var n = 1; items.containsKey(full); n++) {
          full = _numbered(path, name, n);
        }
        items[full] = _Item(
          m['id'] as String,
          '${m['version'] ?? ''}',
          int.tryParse('${m['size'] ?? ''}') ?? 0,
          folder: folder,
        );
      }
      page = r.json['nextPageToken'] as String?;
    } while (page != null);
    final prefix = path.isEmpty ? '' : '$path/';
    bool direct(String p) =>
        p.startsWith(prefix) && !p.substring(prefix.length).contains('/');
    _files.removeWhere((p, _) => direct(p));
    _folders.removeWhere((p, _) => direct(p));
    for (final e in items.entries) {
      if (e.value.folder) {
        _folders[e.key] = e.value.id;
      } else {
        _files[e.key] = e.value;
      }
    }
    return items;
  }

  /// `devices/a.json` found a second time: `devices/a (1).json`.
  static String _numbered(String path, String name, int n) {
    final dot = name.lastIndexOf('.');
    final numbered = dot > 0
        ? '${name.substring(0, dot)} ($n)${name.substring(dot)}'
        : '$name ($n)';
    return path.isEmpty ? numbered : '$path/$numbered';
  }

  static String _dir(String name) {
    final slash = name.lastIndexOf('/');
    return slash < 0 ? '' : name.substring(0, slash);
  }

  /// The item of file [name], listing its folder if it is not known yet. Null if it is missing.
  Future<_Item?> _file(String name, {bool fresh = false}) async {
    final known = _files[name];
    if (!fresh && known != null) return known;
    final dir = _dir(name);
    final folder = await _folder(dir, create: false);
    if (folder == null) return null;
    await _children(dir, folder);
    return _files[name];
  }

  // ---- CloudProvider ----

  @override
  Future<List<CloudEntry>> list(String prefix) async {
    final dir = _dir(prefix);
    final id = await _folder(dir, create: false);
    if (id == null) return const [];
    final out = <CloudEntry>[];
    Future<void> walk(String path, String folderId) async {
      final items = await _children(path, folderId);
      for (final e in items.entries) {
        if (e.value.folder) {
          final sub = '${e.key}/';
          if (sub.startsWith(prefix) || prefix.startsWith(sub)) {
            await walk(e.key, e.value.id);
          }
        } else if (e.key.startsWith(prefix)) {
          out.add(CloudEntry(e.key, e.value.version, e.value.size));
        }
      }
    }

    await walk(dir, id);
    return out;
  }

  @override
  Future<CloudFile?> get(String name) async {
    for (final fresh in [false, true]) {
      final item = await _file(name, fresh: fresh);
      if (item == null) return null;
      final r = await _send(
        () => HttpCall(
          'GET',
          _api
              .resolve('files/${item.id}')
              .replace(queryParameters: {'alt': 'media'}),
        ),
      );
      if (r.status == 404) {
        _files.remove(name); // removed by another device: look again
        continue;
      }
      if (!r.ok) _fail('read $name', r);
      return CloudFile(r.body, item.version);
    }
    return null;
  }

  @override
  Future<String> put(
    String name,
    Uint8List bytes, {
    String? ifVersion,
    bool ifAbsent = false,
  }) async {
    // #53: the engine writes unconditionally; Drive's versions are not used for conditions
    if (ifVersion != null || ifAbsent) {
      throw UnsupportedError('no conditional writes');
    }
    final dir = _dir(name);
    final folder = await _folder(dir, create: true);
    final existing = await _file(name);
    final base = name.substring(name.lastIndexOf('/') + 1);
    final Map<String, Object?> done;
    if (bytes.length > resumableAbove) {
      done = await _resumable(name, base, folder!, existing, bytes);
    } else if (existing != null) {
      final r = await _send(
        () => HttpCall(
          'PATCH',
          _upload
              .resolve('files/${existing.id}')
              .replace(
                queryParameters: {
                  'uploadType': 'media',
                  'fields': 'id,version',
                },
              ),
          headers: {'Content-Type': 'application/octet-stream'},
          body: bytes,
        ),
      );
      if (r.status == 404) {
        _files.remove(name);
        return put(name, bytes);
      }
      if (!r.ok) _fail('write $name', r);
      done = r.json;
    } else {
      final boundary = 'wp${Random().nextInt(1 << 32).toRadixString(16)}';
      final r = await _send(
        () => HttpCall(
          'POST',
          _upload
              .resolve('files')
              .replace(
                queryParameters: {
                  'uploadType': 'multipart',
                  'fields': 'id,version',
                },
              ),
          headers: {'Content-Type': 'multipart/related; boundary=$boundary'},
          body: _multipart(boundary, {
            'name': base,
            'parents': [folder],
          }, bytes),
        ),
      );
      if (!r.ok) _fail('write $name', r);
      done = r.json;
    }
    final item = _Item(
      done['id'] as String? ?? existing?.id ?? '',
      '${done['version'] ?? ''}',
      bytes.length,
    );
    _files[name] = item;
    return item.version;
  }

  static Uint8List _multipart(
    String boundary,
    Map<String, Object?> meta,
    Uint8List bytes,
  ) {
    final b = BytesBuilder(copy: false)
      ..add(
        utf8.encode(
          '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'
          '${jsonEncode(meta)}\r\n'
          '--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));
    return b.takeBytes();
  }

  /// AK4: upload in blocks through a resumable session. A cut-off session is asked how much it has and
  /// continued from there; an expired one is started again.
  Future<Map<String, Object?>> _resumable(
    String name,
    String base,
    String folder,
    _Item? existing,
    Uint8List bytes,
  ) async {
    final total = bytes.length;
    var session = _sessions[name];
    if (session != null && session.length != total) session = null;
    var offset = 0;
    if (session != null) {
      final r = await _send(
        () => HttpCall(
          'PUT',
          session!.uri,
          headers: {'Content-Range': 'bytes */$total'},
        ),
      );
      if (r.ok) {
        _sessions.remove(name);
        return r.json;
      }
      if (r.status == 308) {
        offset = _received(r);
      } else {
        session = null; // expired (404/410) or refused: start again
      }
    }
    if (session == null) {
      final start = await _send(
        () => HttpCall.json(
          existing == null ? 'POST' : 'PATCH',
          _upload
              .resolve(existing == null ? 'files' : 'files/${existing.id}')
              .replace(
                queryParameters: {
                  'uploadType': 'resumable',
                  'fields': 'id,version',
                },
              ),
          existing == null
              ? {
                  'name': base,
                  'parents': [folder],
                }
              : <String, Object?>{},
          headers: {
            'X-Upload-Content-Type': 'application/octet-stream',
            'X-Upload-Content-Length': '$total',
          },
        ),
      );
      final location = start.headers['location'];
      if (!start.ok || location == null) _fail('start upload of $name', start);
      session = _sessions[name] = _Session(Uri.parse(location), total);
      offset = 0;
    }
    while (true) {
      final end = min(offset + chunkSize, total);
      final from = offset;
      final s = session;
      final r = await _send(
        () => HttpCall(
          'PUT',
          s.uri,
          headers: {
            'Content-Range': 'bytes $from-${end - 1}/$total',
            'Content-Type': 'application/octet-stream',
          },
          body: Uint8List.sublistView(bytes, from, end),
        ),
      );
      sentBytes += end - from;
      if (r.ok) {
        _sessions.remove(name);
        return r.json;
      }
      if (r.status == 308) {
        offset = _received(r);
        continue;
      }
      // an expired session (404, 410) answers so again to the next status query and is started anew
      _fail('upload of $name', r);
    }
  }

  /// Bytes the session holds, from `Range: bytes=0-<last>` (none without the header).
  static int _received(HttpReply r) {
    final m = RegExp(r'bytes=0-(\d+)').firstMatch(r.headers['range'] ?? '');
    return m == null ? 0 : int.parse(m.group(1)!) + 1;
  }

  @override
  Future<void> delete(String name) async {
    final item = await _file(name);
    if (item == null) return;
    final r = await _send(
      () => HttpCall('DELETE', _api.resolve('files/${item.id}')),
    );
    _files.remove(name);
    if (!r.ok && r.status != 404) _fail('delete $name', r);
  }

  @override
  Future<CloudQuota> quota() async {
    final r = await _send(
      () => HttpCall(
        'GET',
        _api
            .resolve('about')
            .replace(queryParameters: {'fields': 'storageQuota'}),
      ),
    );
    if (!r.ok) _fail('quota', r);
    final q = r.json['storageQuota'] as Map? ?? const {};
    return CloudQuota(
      used: int.tryParse('${q['usage'] ?? ''}') ?? 0,
      total: int.tryParse('${q['limit'] ?? ''}'),
    );
  }
}
