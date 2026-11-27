// Command line of the desktop app on Windows (#140, #60). dart:io has no Unix domain sockets on
// Windows, so the runner listens on the socket file (app/windows/runner/command_bridge.cpp) and
// hands every connection to Dart over the channel «woodshed/commands»; each one is served by
// serveLines like a socket on macOS and Linux (command_server.dart).
//   Dart -> runner: listen(path) -> bool, write({id, text}), close(id)
//   runner -> Dart: open(id), line({id, text}), closed(id)
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'command_line.dart';
import 'command_server.dart';

class ChannelCommandServer {
  ChannelCommandServer._(this._channel, this._handler);

  final MethodChannel _channel;
  final CommandHandler _handler;
  final _connections = <int, StreamController<String>>{};

  /// The runner listens on the socket file [path] and hands its connections to [handler]. Null if
  /// it cannot listen there or the runner has no command line (the app works without it).
  static Future<ChannelCommandServer?> start(
    String path,
    CommandHandler handler, {
    MethodChannel channel = const MethodChannel('woodshed/commands'),
  }) async {
    final s = ChannelCommandServer._(channel, handler);
    channel.setMethodCallHandler(s._onCall);
    bool? listening;
    try {
      listening = await channel.invokeMethod<bool>('listen', path);
    } on Object catch (e) {
      debugPrint('Command line: not available: $e');
    }
    if (listening != true) {
      channel.setMethodCallHandler(null);
      return null;
    }
    return s;
  }

  /// Connections that are open now.
  @visibleForTesting
  int get openConnections => _connections.length;

  Future<void> _onCall(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'open':
        if (args is! int) return;
        final lines = StreamController<String>();
        _connections[args] = lines;
        unawaited(
          serveLines(
            lines.stream,
            (text) => unawaited(
              _channel
                  .invokeMethod<void>('write', {'id': args, 'text': text})
                  .catchError((Object _) {}),
            ),
            () => _channel
                .invokeMethod<void>('close', args)
                .catchError((Object _) {}),
            _handler,
          ),
        );
      case 'line':
        if (args case {'id': final int id, 'text': final String text}) {
          _connections[id]?.add(text);
        }
      case 'closed':
        if (args is int) await _connections.remove(args)?.close();
    }
  }
}
