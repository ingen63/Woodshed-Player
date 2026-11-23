// The sign-in window of macOS (#54/AK1, «woodshed/webauth», ASWebAuthenticationSession in
// MainFlutterWindow.swift); no extra package.
import 'package:flutter/services.dart';

import '../sync/system_sign_in.dart';

class WebAuthChannel implements SystemSignIn {
  WebAuthChannel([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('woodshed/webauth');

  final MethodChannel _channel;

  @override
  Future<Uri?> authenticate(Uri url, String callbackScheme) async {
    final answer = await _channel.invokeMethod<String>('start', {
      'url': url.toString(),
      'scheme': callbackScheme,
    });
    return answer == null ? null : Uri.tryParse(answer);
  }

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}
