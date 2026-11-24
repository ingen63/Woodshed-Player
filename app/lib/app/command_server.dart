// Command line of the desktop app (#140): the running app listens on a Unix domain socket, a file in
// its own folder, for the requests of its program started from the shell (protocol in
// command_line.dart). A Unix domain socket never leaves the computer: no TCP, no port, no network
// (#58, docs/KONZEPT-SYNC.md). Only on the desktop; on iPhone/iPad and in the browser there is none.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'command_line.dart';

/// Longest path of a Unix domain socket (sun_path of macOS, 104 bytes with the closing zero).
const maxSocketPath = 103;

class CommandServer {
  CommandServer._(this._server, this.path);

  // network-free: local unix socket, bound to a file path (InternetAddressType.unix), never TCP
  final ServerSocket _server;
  final String path;

  /// Listens on the socket file [path] and answers each request with [handler]. A file left there by
  /// an earlier run is replaced. Null if the socket cannot be opened (the app works without it).
  static Future<CommandServer?> start(
    String path,
    CommandHandler handler,
  ) async {
    if (utf8.encode(path).length > maxSocketPath) {
      debugPrint('Command line: socket path too long: $path');
      return null;
    }
    try {
      final stale = File(path);
      if (FileSystemEntity.typeSync(path) ==
          FileSystemEntityType.unixDomainSock) {
        stale.deleteSync();
      }
      // network-free: local unix socket, a file path (InternetAddressType.unix), never TCP
      final server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      final s = CommandServer._(server, path);
      server.listen((client) => unawaited(_serve(client, handler)));
      return s;
    } on Object catch (e) {
      debugPrint('Command line: socket not available: $e');
      return null;
    }
  }

  // network-free: local unix socket, the connection of one call of the command line
  static Future<void> _serve(Socket client, CommandHandler handler) async {
    final interrupt = Completer<void>();
    final request = Completer<String?>();
    final lines = client
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    // The program went away (closed, or the connection broke): no request, or Ctrl-C.
    void gone([Object? _]) {
      if (!request.isCompleted) request.complete(null);
      if (!interrupt.isCompleted) interrupt.complete();
    }

    final sub = lines.listen(
      (line) {
        if (!request.isCompleted) {
          request.complete(line);
        } else if (line.trim() == 'stop' && !interrupt.isCompleted) {
          interrupt.complete();
        }
      },
      onDone: gone,
      onError: gone,
      cancelOnError: true,
    );
    final out = _SocketOutput(client);
    var code = CliExit.usage;
    try {
      final line = await request.future;
      Object? json;
      try {
        json = line == null ? null : jsonDecode(line);
      } on FormatException {
        json = null;
      }
      final r = CommandRequest.fromJson(json);
      if (r == null) {
        out.err(
          'The app did not understand the request; are the app and the command the same version?',
        );
      } else {
        code = await handler.run(r, out, interrupt.future);
      }
    } on Object catch (e) {
      out.err('Internal error: $e');
      code = CliExit.failed;
    }
    out.line('exit $code');
    try {
      await client.flush();
      await client.close();
    } on Object {
      // the command is gone (closed terminal)
    }
    await sub.cancel();
  }

  Future<void> close() async {
    await _server.close();
    try {
      File(path).deleteSync();
    } on FileSystemException {
      // already gone
    }
  }
}

/// Lines to the client: `out` and `err` with one line each, newlines split.
class _SocketOutput implements CommandOutput {
  _SocketOutput(this._client);
  // network-free: local unix socket, see CommandServer
  final Socket _client;

  void line(String text) {
    try {
      _client.write('$text\n');
    } on Object {
      // the command is gone
    }
  }

  @override
  void out(String text) => text.split('\n').forEach((l) => line('out $l'));
  @override
  void err(String text) => text.split('\n').forEach((l) => line('err $l'));
}
