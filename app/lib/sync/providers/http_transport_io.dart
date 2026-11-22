// HTTP on desktop (#54): dart:io, no extra package. Connection problems become CloudOffline.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../cloud_provider.dart';
import 'http_transport.dart';

HttpTransport createTransport() => IoTransport();

class IoTransport implements HttpTransport {
  IoTransport({this.timeout = const Duration(seconds: 60)});

  /// Longest wait for a response or the next part of it.
  final Duration timeout;
  HttpClient? _client;
  bool _closed = false;

  HttpClient get _http => _client ??= HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 15);

  @override
  Future<HttpReply> send(HttpCall call) async {
    if (_closed) throw const CloudOffline('signed out');
    try {
      final req = await _http.openUrl(call.method, call.url).timeout(timeout);
      req.followRedirects = call.method == 'GET';
      call.headers.forEach(req.headers.set);
      final body = call.body;
      if (body != null) {
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close().timeout(timeout);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(timeout)) {
        bytes.add(chunk);
      }
      final headers = <String, String>{};
      res.headers.forEach((name, values) => headers[name] = values.join(','));
      return HttpReply(
        res.statusCode,
        headers: headers,
        body: bytes.takeBytes(),
      );
    } on SocketException catch (e) {
      throw CloudOffline('$e');
    } on HandshakeException catch (e) {
      throw CloudOffline('$e');
    } on HttpException catch (e) {
      throw CloudOffline('$e');
    } on TimeoutException catch (e) {
      throw CloudOffline('$e');
    } on StateError catch (e) {
      // the client was closed while the request ran (sign-out)
      throw CloudOffline('$e');
    }
  }

  @override
  void close() {
    _closed = true;
    _client?.close(force: true);
    _client = null;
  }
}
