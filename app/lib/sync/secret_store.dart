// Where the sign-in of a cloud provider is kept (#54/AK1): the keychain on macOS (lib/app/keychain_store.dart),
// IndexedDB in the browser (providers/google_auth_web.dart). Never in library.json or device.json, so the
// tokens never go into the sync and never into a backup.

abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);

  /// Removes the entry if there is one.
  Future<void> delete(String key);
}

/// In memory, for tests and platforms without a keychain.
class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
