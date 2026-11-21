// Interface to a storage (#37, #53, plan W5): the sync engine knows no provider, only these five calls.
// Google Drive (#54) and OneDrive (#55) follow; tests use the InMemoryProvider. All names are relative
// to the app's own folder at the provider and separated by «/» («devices/<id>.json», «audio/<hash>.mp3»).
import 'dart:typed_data';

/// One stored file: name, version tag (ETag / rev) and size in bytes.
class CloudEntry {
  const CloudEntry(this.name, this.version, this.size);
  final String name;
  final String version;
  final int size;
}

/// Contents of a file with the version tag they belong to.
class CloudFile {
  const CloudFile(this.bytes, this.version);
  final Uint8List bytes;
  final String version;
}

/// Storage used and granted at the provider; [total] is null if unlimited or unknown.
class CloudQuota {
  const CloudQuota({required this.used, this.total});
  final int used;
  final int? total;
}

/// No connection (offline, server not reachable): the engine stops this sync and tries again later.
class CloudOffline implements Exception {
  const CloudOffline([this.detail = '']);
  final String detail;
  @override
  String toString() => 'CloudOffline($detail)';
}

/// A conditional [CloudProvider.put] failed: the file changed (or appeared) in the meantime.
class VersionConflict implements Exception {
  const VersionConflict(this.name);
  final String name;
  @override
  String toString() => 'VersionConflict($name)';
}

/// Any other failure of a single request (aborted upload, server error); the engine retries the task.
class CloudError implements Exception {
  const CloudError(this.detail);
  final String detail;
  @override
  String toString() => 'CloudError($detail)';
}

abstract class CloudProvider {
  /// Files whose name starts with [prefix].
  Future<List<CloudEntry>> list(String prefix);

  /// Contents and version, or null if the file is missing.
  Future<CloudFile?> get(String name);

  /// Writes the whole file and returns its new version. With [ifVersion] only if the stored version is
  /// still that one, with [ifAbsent] only if there is no such file yet; otherwise throws
  /// [VersionConflict]. An aborted upload leaves the previous contents (or nothing). Since #53 the sync
  /// engine never writes conditionally (one file per device), so a storage without versions may refuse
  /// both conditions.
  Future<String> put(
    String name,
    Uint8List bytes, {
    String? ifVersion,
    bool ifAbsent = false,
  });

  /// Deletes the file if it exists.
  Future<void> delete(String name);

  Future<CloudQuota> quota();
}
