// The token store of the system through a small channel of the app (#54/AK1, «woodshed/keychain»): the
// keychain on macOS (SecItem in MainFlutterWindow.swift), #161: the Credential Manager on Windows
// (windows/runner/keychain_channel.cpp) and the Secret Service through libsecret on Linux
// (linux/runner/keychain_channel.cc). No extra package. Holds the refresh token of the cloud sign-in.
import 'package:flutter/services.dart';

import '../sync/secret_store.dart';

class KeychainStore implements SecretStore {
  KeychainStore([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('woodshed/keychain');

  final MethodChannel _channel;

  /// #161/AK2: whether the store can be used here. False on Linux without libsecret, and when the
  /// channel does not answer.
  Future<bool> available() async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

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
