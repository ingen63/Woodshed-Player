// HTTP for the cloud providers (#54, #58): the only place of the app that talks to a server. One small
// interface with an implementation on dart:io (desktop, http_transport_io.dart) and on fetch (browser,
// http_transport_web.dart); tests answer with recorded or simulated responses and never reach an account.
import 'dart:convert';
import 'dart:typed_data';

/// One request.
class HttpCall {
  HttpCall(
    this.method,
    this.url, {
    Map<String, String>? headers,
    this.body,
    this.opaque = false,
  }) : headers = headers ?? {};

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Uint8List? body;

  /// The answer is not needed (e.g. revoking a token): in the browser it is sent without CORS and the
  /// reply has status 0.
  final bool opaque;

  /// A request with a form body (`application/x-www-form-urlencoded`).
  factory HttpCall.form(String method, Uri url, Map<String, String> fields) =>
      HttpCall(
        method,
        url,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: Uint8List.fromList(
          utf8.encode(Uri(queryParameters: fields).query),
        ),
      );

  /// A request with a JSON body.
  factory HttpCall.json(
    String method,
    Uri url,
    Object? json, {
    Map<String, String>? headers,
  }) => HttpCall(
    method,
    url,
    headers: {'Content-Type': 'application/json; charset=UTF-8', ...?headers},
    body: Uint8List.fromList(utf8.encode(jsonEncode(json))),
  );

  @override
  String toString() => '$method $url';
}

/// One response; header names in lower case.
class HttpReply {
  HttpReply(this.status, {Map<String, String>? headers, Uint8List? body})
    : headers = {
        for (final e in (headers ?? const {}).entries)
          e.key.toLowerCase(): e.value,
      },
      body = body ?? Uint8List(0);

  /// A JSON response (for tests and simulated servers).
  factory HttpReply.json(
    int status,
    Object? json, {
    Map<String, String>? headers,
  }) => HttpReply(
    status,
    headers: {'content-type': 'application/json', ...?headers},
    body: Uint8List.fromList(utf8.encode(jsonEncode(json))),
  );

  final int status;
  final Map<String, String> headers;
  final Uint8List body;

  bool get ok => status >= 200 && status < 300;

  String get text => utf8.decode(body, allowMalformed: true);

  /// The body as JSON object; empty if it is none.
  Map<String, Object?> get json {
    try {
      final j = jsonDecode(text);
      if (j is Map<String, Object?>) return j;
    } on FormatException {
      // not JSON
    }
    return const {};
  }
}

/// Sends requests. A missing connection (no network, host not reachable, timeout, connection cut off)
/// throws `CloudOffline`; every answer of the server, errors included, comes back as [HttpReply].
abstract class HttpTransport {
  Future<HttpReply> send(HttpCall call);

  /// Ends every request still running and refuses new ones (sign-out, #54/AK11).
  void close();
}
