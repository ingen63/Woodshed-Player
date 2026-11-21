// Device-local settings (#36/AK5): `device.json` next to `library.json`. They never go into the shared state
// and are never synced. Device-local are the device ID and, as they are added, the cloud account and tokens,
// the cache limit, the window frame and the output device, and whether this device has synced before (#104).
// File paths are not stored at all: the FileStore derives them on each device.
// #39/AK3: the audio cache of this device: its limit, the tracks kept offline, the tracks whose file was
// removed to stay below the limit (they stay in the library, their file is in the cloud) and when each
// track was last used here (the oldest go first).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../app/file_platform.dart';

class DeviceSettings {
  const DeviceSettings({
    required this.deviceId,
    this.synced = false,
    this.cacheLimit = defaultCacheLimit,
    this.keepOffline = const {},
    this.evicted = const {},
    this.lastUsed = const {},
    this.libraryId,
  });

  static const fileName = 'device.json';

  /// #39/AK3: 2 GB unless the user chose another limit.
  static const defaultCacheLimit = 2000000000;

  /// Random ID of this device (16 hex digits); part of every stamp this device issues.
  final String deviceId;

  /// This device has merged or uploaded its shared state at least once (#104): from then on the purge
  /// horizon of other devices applies to its records. Written only once true, so older files stay valid.
  final bool synced;

  /// Bytes of audio files this device keeps before the oldest are removed (#39/AK3).
  final int cacheLimit;

  /// Tracks whose file is never removed to keep the limit («Keep offline», #39/AK3).
  final Set<String> keepOffline;

  /// Tracks whose file was removed to keep the limit; loaded again when played (#39/AK4).
  final Set<String> evicted;

  /// Track ID → milliseconds since the epoch when the track was last used on this device.
  final Map<String, int> lastUsed;

  /// ID of the library this device syncs with (#53, `format.json`); null until the first sync. A storage
  /// holding another library ID is not merged.
  final String? libraryId;

  DeviceSettings copyWith({
    bool? synced,
    int? cacheLimit,
    Set<String>? keepOffline,
    Set<String>? evicted,
    Map<String, int>? lastUsed,
    String? libraryId,
  }) => DeviceSettings(
    deviceId: deviceId,
    synced: synced ?? this.synced,
    cacheLimit: cacheLimit ?? this.cacheLimit,
    keepOffline: keepOffline ?? this.keepOffline,
    evicted: evicted ?? this.evicted,
    lastUsed: lastUsed ?? this.lastUsed,
    libraryId: libraryId ?? this.libraryId,
  );

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    if (synced) 'synced': true,
    if (cacheLimit != defaultCacheLimit) 'cacheLimit': cacheLimit,
    if (keepOffline.isNotEmpty) 'keepOffline': [...keepOffline]..sort(),
    if (evicted.isNotEmpty) 'evicted': [...evicted]..sort(),
    if (lastUsed.isNotEmpty) 'lastUsed': lastUsed,
    if (libraryId != null) 'libraryId': libraryId,
  };

  static String newDeviceId([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(
      8,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// Reads `device.json`; creates it with a new device ID if it is missing or unreadable. Unreadable cache
  /// fields fall back to their defaults, the device ID stays.
  static Future<DeviceSettings> load(FileStore store, {Random? random}) async {
    try {
      final raw = await store.read(fileName);
      if (raw != null) {
        final j = jsonDecode(utf8.decode(raw)) as Map;
        final id = j['deviceId'];
        if (id is String && RegExp(r'^[0-9a-f]{16}$').hasMatch(id)) {
          return DeviceSettings(
            deviceId: id,
            synced: j['synced'] == true,
            cacheLimit: switch (j['cacheLimit']) {
              final int v when v > 0 => v,
              _ => defaultCacheLimit,
            },
            keepOffline: _ids(j['keepOffline']),
            evicted: _ids(j['evicted']),
            lastUsed: {
              if (j['lastUsed'] case final Map<Object?, Object?> m)
                for (final e in m.entries)
                  if (e.key is String && e.value is int)
                    e.key as String: e.value as int,
            },
            libraryId: switch (j['libraryId']) {
              final String v when v.isNotEmpty => v,
              _ => null,
            },
          );
        }
      }
    } catch (_) {}
    final d = DeviceSettings(deviceId: newDeviceId(random));
    try {
      await d.save(store);
    } catch (_) {}
    return d;
  }

  static Set<String> _ids(Object? v) => {
    if (v is List)
      for (final x in v)
        if (x is String) x,
  };

  Future<void> save(FileStore store) => store.write(
    fileName,
    Uint8List.fromList(utf8.encode(jsonEncode(toJson()))),
  );
}
