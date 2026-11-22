// #54/AK13: a simulated Google Drive and Google token endpoint for tests. It answers the requests the app
// sends (files.list with the queries of the provider, folder creation, multipart, media and resumable
// uploads, alt=media, delete, about, token, revoke) like Google does, in memory. Never a real account.
import 'dart:convert';
import 'dart:typed_data';

import 'package:woodshed_player/sync/cloud_provider.dart';
import 'package:woodshed_player/sync/providers/google_auth.dart';
import 'package:woodshed_player/sync/providers/http_transport.dart';

const folderType = 'application/vnd.google-apps.folder';

class DriveFile {
  DriveFile(
    this.id,
    this.name,
    this.parent,
    this.created, {
    this.folder = false,
  });
  final String id;
  String name;
  final String parent;
  final int created;
  final bool folder;
  Uint8List bytes = Uint8List(0);
  int version = 1;
}

class UploadSession {
  UploadSession(this.target, this.name, this.parent, this.total);
  final String? target; // file ID for an update, null for a new file
  final String? name;
  final String? parent;
  final int total;
  final received = BytesBuilder();
}

/// One Drive account, shared by all devices of a test.
class FakeDrive {
  final files = <String, DriveFile>{};
  final sessions = <String, UploadSession>{};
  int _next = 0;
  int _clock = 0;

  /// Access tokens Google accepts.
  final valid = <String>{'token-1'};

  /// Refresh token → access token handed out on refresh; empty: refused.
  final refresh = <String, String>{};
  int issued = 1;

  /// Every request: «METHOD path?query».
  final calls = <HttpCall>[];

  /// Throws CloudOffline instead of answering the call for which this returns true.
  bool Function(HttpCall c)? cut;

  /// Answers instead of Drive where it returns a reply (server errors in tests).
  HttpReply? Function(HttpCall c)? respond;

  /// A session keeps at most this many bytes of a block (simulates a partly received block).
  int? keepAtMost;

  int limit = 15000000000;

  String _id() => 'id${++_next}';

  /// Path of a file from the folder below the root (`WoodshedPlayer/devices/a.json`).
  String pathOf(DriveFile f) {
    final parts = [f.name];
    var p = files[f.parent];
    while (p != null) {
      parts.insert(0, p.name);
      p = files[p.parent];
    }
    return parts.join('/');
  }

  /// Paths of every file (not folder), e.g. `WoodshedPlayer/format.json`.
  Set<String> get paths => {
    for (final f in files.values)
      if (!f.folder) pathOf(f),
  };

  List<DriveFile> get roots => [
    for (final f in files.values)
      if (f.folder && f.parent == 'root' && f.name == 'WoodshedPlayer') f,
  ];

  DriveFile addFolder(String name, String parent) {
    final f = DriveFile(_id(), name, parent, ++_clock, folder: true);
    files[f.id] = f;
    return f;
  }

  DriveFile addFile(String name, String parent, List<int> bytes) {
    final f = DriveFile(_id(), name, parent, ++_clock)
      ..bytes = Uint8List.fromList(bytes);
    files[f.id] = f;
    return f;
  }

  /// A transport for one device.
  HttpTransport transport() => DriveTransport(this);

  HttpReply answer(HttpCall c) {
    calls.add(c);
    if (cut?.call(c) ?? false) throw const CloudOffline('cut');
    if (respond?.call(c) case final r?) return r;
    final u = c.url;
    if (u.host == 'oauth2.googleapis.com') return _oauth(c);
    final auth = c.headers['Authorization'] ?? '';
    if (!auth.startsWith('Bearer ') || !valid.contains(auth.substring(7))) {
      return HttpReply.json(401, {
        'error': {'code': 401, 'message': 'Invalid Credentials'},
      });
    }
    final path = u.path;
    if (u.queryParameters['upload_id'] case final id?) return _chunk(c, id);
    if (path == '/drive/v3/about') {
      final used = files.values.fold(0, (s, f) => s + f.bytes.length);
      return HttpReply.json(200, {
        'storageQuota': {'limit': '$limit', 'usage': '$used'},
      });
    }
    if (path == '/drive/v3/files' && c.method == 'GET') return _list(u);
    if (path == '/drive/v3/files' && c.method == 'POST') {
      final j = jsonDecode(utf8.decode(c.body!)) as Map;
      final parents = j['parents'] as List?;
      final f = addFolder(
        j['name'] as String,
        parents == null ? 'root' : parents.first as String,
      );
      return HttpReply.json(200, {'id': f.id});
    }
    if (path.startsWith('/drive/v3/files/')) {
      final f = files[path.substring('/drive/v3/files/'.length)];
      if (f == null) {
        return HttpReply.json(404, {
          'error': {'code': 404},
        });
      }
      if (c.method == 'DELETE') {
        files.remove(f.id);
        return HttpReply(204);
      }
      return HttpReply(200, body: f.bytes);
    }
    if (path == '/upload/drive/v3/files' ||
        path.startsWith('/upload/drive/v3/files/')) {
      return _upload(c);
    }
    return HttpReply.json(400, {'error': 'unknown request'});
  }

  HttpReply _oauth(HttpCall c) {
    if (c.url.path == '/revoke') {
      final t =
          c.url.queryParameters['token'] ??
          Uri.splitQueryString(utf8.decode(c.body ?? Uint8List(0)))['token'];
      refresh.remove(t);
      valid.remove(t);
      return HttpReply(200);
    }
    final f = Uri.splitQueryString(utf8.decode(c.body!));
    if (f['grant_type'] == 'refresh_token') {
      if (!refresh.containsKey(f['refresh_token'])) {
        return HttpReply.json(400, {'error': 'invalid_grant'});
      }
      final t = 'token-${++issued}';
      valid.add(t);
      return HttpReply.json(200, {
        'access_token': t,
        'expires_in': 3599,
        'scope': googleScope,
        'token_type': 'Bearer',
      });
    }
    if (f['grant_type'] == 'authorization_code') {
      lastExchange = f;
      final t = 'token-${++issued}';
      valid.add(t);
      refresh['refresh-$issued'] = t;
      return HttpReply.json(200, {
        'access_token': t,
        'expires_in': 3599,
        'refresh_token': 'refresh-$issued',
        'scope': grantedScope,
        'token_type': 'Bearer',
      });
    }
    return HttpReply.json(400, {'error': 'unsupported_grant_type'});
  }

  /// The form of the last code exchange.
  Map<String, String>? lastExchange;
  String grantedScope = googleScope;

  HttpReply _list(Uri u) {
    final q = u.queryParameters['q']!;
    final byName = RegExp(r"name = '([^']*)'").firstMatch(q)?.group(1);
    final parent = RegExp(r"'([^']*)' in parents").firstMatch(q)!.group(1)!;
    final folderOnly = q.contains("mimeType = '$folderType'");
    final all = [
      for (final f in files.values)
        if (f.parent == parent &&
            (byName == null || f.name == byName) &&
            (!folderOnly || f.folder))
          f,
    ]..sort((a, b) => a.created.compareTo(b.created));
    final size = int.parse(u.queryParameters['pageSize'] ?? '100');
    final from = int.tryParse(u.queryParameters['pageToken'] ?? '') ?? 0;
    final page = all.skip(from).take(size).toList();
    return HttpReply.json(200, {
      if (from + size < all.length) 'nextPageToken': '${from + size}',
      'files': [
        for (final f in page)
          {
            'id': f.id,
            'name': f.name,
            'mimeType': f.folder ? folderType : 'application/octet-stream',
            if (!f.folder) 'size': '${f.bytes.length}',
            'version': '${f.version}',
          },
      ],
    });
  }

  HttpReply _upload(HttpCall c) {
    final type = c.url.queryParameters['uploadType'];
    final id = c.url.pathSegments.length > 4 ? c.url.pathSegments.last : null;
    if (type == 'resumable') {
      // like Drive: POST creates, PATCH updates the file with the ID
      if (c.method != (id == null ? 'POST' : 'PATCH')) {
        return HttpReply.json(404, {'error': 'method'});
      }
      final meta = jsonDecode(utf8.decode(c.body!)) as Map;
      if (id != null && !files.containsKey(id)) {
        return HttpReply.json(404, {
          'error': {'code': 404},
        });
      }
      final s = '${++_next}';
      sessions[s] = UploadSession(
        id,
        meta['name'] as String?,
        (meta['parents'] as List?)?.first as String?,
        int.parse(c.headers['X-Upload-Content-Length']!),
      );
      return HttpReply(
        200,
        headers: {
          'Location':
              'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=$s',
        },
      );
    }
    if (type == 'media') {
      if (c.method != 'PATCH') return HttpReply.json(404, {'error': 'method'});
      final f = files[id];
      if (f == null) {
        return HttpReply.json(404, {
          'error': {'code': 404},
        });
      }
      f
        ..bytes = Uint8List.fromList(c.body!)
        ..version += 1;
      return HttpReply.json(200, {'id': f.id, 'version': '${f.version}'});
    }
    if (type == 'multipart') {
      final boundary = RegExp(r'boundary=(\S+)')
          .firstMatch(c.headers['Content-Type']!)!
          .group(1)!;
      final (meta, data) = parseMultipart(c.body!, boundary);
      final f = addFile(
        meta['name'] as String,
        (meta['parents'] as List).first as String,
        data,
      );
      return HttpReply.json(200, {'id': f.id, 'version': '${f.version}'});
    }
    return HttpReply.json(400, {'error': 'uploadType'});
  }

  HttpReply _chunk(HttpCall c, String id) {
    if (finished[id] case final f?) {
      // a finished session answers with the file (also to a status query)
      return HttpReply.json(200, {'id': f.id, 'version': '${f.version}'});
    }
    final s = sessions[id];
    if (s == null) {
      return HttpReply.json(404, {
        'error': {'code': 404},
      });
    }
    final range = c.headers['Content-Range']!;
    HttpReply status() {
      final n = s.received.length;
      return HttpReply(308, headers: {if (n > 0) 'Range': 'bytes=0-${n - 1}'});
    }

    if (range.startsWith('bytes */')) {
      return s.received.length == s.total ? _finish(id, s) : status();
    }
    final m = RegExp(r'bytes (\d+)-(\d+)/(\d+)').firstMatch(range)!;
    final start = int.parse(m.group(1)!);
    if (start != s.received.length) {
      return HttpReply.json(400, {'error': 'wrong offset $start'});
    }
    var body = c.body!;
    if (keepAtMost case final k? when body.length > k) {
      body = Uint8List.sublistView(body, 0, k);
    }
    s.received.add(body);
    return s.received.length == s.total ? _finish(id, s) : status();
  }

  HttpReply _finish(String id, UploadSession s) {
    sessions.remove(id);
    final bytes = s.received.toBytes();
    final DriveFile f;
    if (s.target case final t?) {
      f = files[t]!
        ..bytes = bytes
        ..version += 1;
    } else {
      f = addFile(s.name!, s.parent!, bytes);
    }
    finished[id] = f;
    return HttpReply.json(200, {'id': f.id, 'version': '${f.version}'});
  }

  /// Sessions whose upload is complete.
  final finished = <String, DriveFile>{};

  /// Every request: «METHOD /path», for checks.
  List<String> get log => [
    for (final c in calls) '${c.method} ${c.url.host}${c.url.path}',
  ];
}

(Map<String, Object?>, Uint8List) parseMultipart(
  Uint8List body,
  String boundary,
) {
  final text = latin1.decode(body);
  final parts = text.split('--$boundary');
  final meta = parts[1].substring(parts[1].indexOf('\r\n\r\n') + 4).trim();
  final raw = parts[2].substring(parts[2].indexOf('\r\n\r\n') + 4);
  final data = latin1.encode(raw.substring(0, raw.length - 2));
  return (
    jsonDecode(utf8.decode(latin1.encode(meta))) as Map<String, Object?>,
    data,
  );
}

class DriveTransport implements HttpTransport {
  DriveTransport(this.drive);
  final FakeDrive drive;
  bool closed = false;

  @override
  Future<HttpReply> send(HttpCall call) async {
    if (closed) throw const CloudOffline('closed');
    return drive.answer(call);
  }

  @override
  void close() => closed = true;
}

/// Sign-in that always has a token (tests of the provider alone).
class FixedAuth extends GoogleAuth {
  FixedAuth([this.value = 'token-1']);
  String value;
  int rejections = 0;

  @override
  Future<void> load() async {}
  @override
  bool get signedIn => true;
  @override
  bool get needsSignIn => false;
  @override
  Future<String> token() async => value;
  @override
  void rejected() => rejections++;
  @override
  Future<SignInResult> signIn({String doneText = ''}) async =>
      SignInResult.signedIn;
  @override
  Future<void> signOut() async {}
}
