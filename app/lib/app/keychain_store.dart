// The macOS keychain through a small channel of the app (#54/AK1, «woodshed/keychain», SecItem in
// MainFlutterWindow.swift); no extra package. Holds the refresh token of the cloud sign-in.
import 'package:flutter/services.dart';

import '../sync/secret_store.dart';

class KeychainStore implements SecretStore {
  KeychainStore([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('woodshed/keychain');

  final MethodChannel _channel;

  @override
  Future<String?> read(String key) =>
      _channel.invokeMethod<String>('read', {'key': key});

  @override
  Future<void> write(String key, String value) =>
      _channel.invokeMethod<void>('write', {'key': key, 'value': value});

  @override
  Future<void> delete(String key) =>
      _channel.invokeMethod<void>('delete', {'key': key});
}
