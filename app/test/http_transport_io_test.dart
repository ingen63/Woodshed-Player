// #54: HTTP on the desktop (dart:io) against a local server on 127.0.0.1, never a real provider (AK13).
// Requests and answers go through unchanged; a missing connection, a timeout and a closed transport become
// CloudOffline (the engine then waits as when offline, AK11: after sign-out nothing goes out).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/sync/cloud_provider.dart';
import 'package:woodshed_player/sync/providers/http_transport.dart';
import 'package:woodshed_player/sync/providers/http_transport_io.dart';

Future<HttpServer> serve(Future<void> Function(HttpRequest r) handle) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen(handle);
  return server;
}

void main() {
  test('#54/AK3 request and answer go through unchanged', () async {
    final seen = <String>[];
    final server = await serve((r) async {
      final body = await r.fold<List<int>>([], (a, b) => a..addAll(b));
      seen.add(
        '${r.method} ${r.uri} ${r.headers.value('x-test')} '
        '${r.headers.contentLength} ${utf8.decode(body)}',
      );
      r.response
        ..statusCode = r.method == 'PUT' ? 308 : 201
        ..headers.set('Range', 'bytes=0-9')
        ..write('answer');
      await r.response.close();
    });
    final t = IoTransport();
    addTearDown(t.close);
    final base = Uri.parse('http://127.0.0.1:${server.port}/p');
    final put = await t.send(
      HttpCall(
        'PUT',
        base.replace(queryParameters: {'a': '1'}),
        headers: {'X-Test': 'yes'},
        body: Uint8List.fromList(utf8.encode('data')),
      ),
    );
    expect(put.status, 308, reason: '308 of an upload is not followed');
    expect(put.headers['range'], 'bytes=0-9');
    expect(put.text, 'answer');
    final post = await t.send(HttpCall('POST', base));
    expect(post.status, 201);
    expect(post.ok, isTrue);
    final get = await t.send(HttpCall('GET', base));
    expect(get.text, 'answer');
    await t.send(HttpCall('DELETE', base));
    expect(seen, [
      'PUT /p?a=1 yes 4 data',
      'POST /p null 0 ',
      'GET /p null -1 ',
      'DELETE /p null -1 ',
    ]);
  });

  test('#54/AK3 GET follows a redirect (Drive media), PUT does not', () async {
    final server = await serve((r) async {
      if (r.uri.path == '/from') {
        r.response
          ..statusCode = 302
          ..headers.set('Location', '/to');
      } else {
        r.response.write('moved');
      }
      await r.response.close();
    });
    final t = IoTransport();
    addTearDown(t.close);
    final from = Uri.parse('http://127.0.0.1:${server.port}/from');
    expect((await t.send(HttpCall('GET', from))).text, 'moved');
    expect((await t.send(HttpCall('PUT', from))).status, 302);
  });

  test(
    '#54/AK5 no connection and no answer in time are CloudOffline',
    () async {
      final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close(force: true);
      final t = IoTransport(timeout: const Duration(milliseconds: 200));
      addTearDown(t.close);
      await expectLater(
        t.send(HttpCall('GET', Uri.parse('http://127.0.0.1:$port/'))),
        throwsA(isA<CloudOffline>()),
      );
      final never = Completer<void>();
      addTearDown(() => never.isCompleted ? null : never.complete());
      final slow = await serve((r) => never.future);
      await expectLater(
        t.send(HttpCall('GET', Uri.parse('http://127.0.0.1:${slow.port}/'))),
        throwsA(isA<CloudOffline>()),
      );
    },
  );

  test(
    '#54/AK11 after close nothing goes out, a running request ends',
    () async {
      var requests = 0;
      final started = Completer<void>();
      final server = await serve((r) async {
        requests++;
        if (!started.isCompleted) started.complete();
        await Completer<void>().future; // the answer never comes
      });
      final t = IoTransport();
      final running = t.send(
        HttpCall('GET', Uri.parse('http://127.0.0.1:${server.port}/')),
      );
      await started.future;
      t.close();
      await expectLater(running, throwsA(isA<CloudOffline>()));
      await expectLater(
        t.send(HttpCall('GET', Uri.parse('http://127.0.0.1:${server.port}/'))),
        throwsA(isA<CloudOffline>()),
      );
      expect(requests, 1);
    },
  );

  test('#54 helpers of the request and the answer', () {
    final f = HttpCall.form('POST', Uri.parse('https://x.test/'), {
      'a': '1 2',
      'b': 'ä',
    });
    expect(f.headers['Content-Type'], 'application/x-www-form-urlencoded');
    expect(utf8.decode(f.body!), 'a=1+2&b=%C3%A4');
    expect(f.toString(), 'POST https://x.test/');
    final j = HttpCall.json(
      'PATCH',
      Uri.parse('https://x.test/'),
      {'k': 1},
      headers: {'X': 'y'},
    );
    expect(j.headers, {
      'Content-Type': 'application/json; charset=UTF-8',
      'X': 'y',
    });
    expect(jsonDecode(utf8.decode(j.body!)), {'k': 1});
    expect(HttpCall('GET', Uri.parse('https://x.test/')).opaque, isFalse);
    final r = HttpReply(200, headers: {'Content-Type': 'a'});
    expect(r.headers, {'content-type': 'a'});
    expect(r.json, isEmpty);
    expect(
      HttpReply(200, body: Uint8List.fromList(utf8.encode('[1]'))).json,
      isEmpty,
    );
    expect(HttpReply.json(404, {'e': 1}).json, {'e': 1});
    expect(
      HttpReply(200, body: Uint8List.fromList([0xff, 0x41])).text,
      '\uFFFDA',
    );
    expect(HttpReply(199).ok, isFalse);
    expect(HttpReply(200).ok, isTrue);
    expect(HttpReply(299).ok, isTrue);
    expect(HttpReply(300).ok, isFalse);
  });
}
