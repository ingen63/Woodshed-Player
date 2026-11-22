// HTTP in the browser (#54): fetch through package:web, no extra package. Connection problems (fetch throws
// a TypeError) become CloudOffline; the Content Security Policy of index.html allows only the API and
// sign-in hosts of the providers (#58).
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../cloud_provider.dart';
import 'http_transport.dart';

HttpTransport createTransport() => FetchTransport();

class FetchTransport implements HttpTransport {
  bool _closed = false;
  web.AbortController _abort = web.AbortController();

  @override
  Future<HttpReply> send(HttpCall call) async {
    if (_closed) throw const CloudOffline('signed out');
    final headers = web.Headers();
    call.headers.forEach((k, v) => headers.append(k, v));
    final body = call.body;
    try {
      final res = await web.window
          .fetch(
            call.url.toString().toJS,
            web.RequestInit(
              method: call.method,
              headers: headers,
              body: body?.toJS,
              mode: call.opaque ? 'no-cors' : 'cors',
              redirect: 'follow',
              signal: _abort.signal,
            ),
          )
          .toDart;
      final bytes = (await res.arrayBuffer().toDart).toDart.asUint8List();
      final out = <String, String>{};
      for (final name in const ['location', 'range', 'content-type']) {
        final v = res.headers.get(name);
        if (v != null) out[name] = v;
      }
      return HttpReply(
        res.status,
        headers: out,
        body: Uint8List.fromList(bytes),
      );
    } catch (e) {
      if (e is CloudOffline) rethrow;
      throw CloudOffline('$e');
    }
  }

  @override
  void close() {
    _closed = true;
    _abort.abort();
    _abort = web.AbortController();
  }
}
