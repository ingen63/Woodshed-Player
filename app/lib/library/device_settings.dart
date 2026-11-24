// Device-local settings (#36/AK5): `device.json` next to `library.json`. They never go into the shared state
// and are never synced. Device-local are the device ID and, as they are added, the cloud account and tokens,
// the cache limit, the window frame and the output device, and whether this device has synced before (#104).
// File paths are not stored at all: the FileStore derives them on each device.
// #39/AK3: the audio cache of this device: its limit, the tracks kept offline, the tracks whose file was
// removed to stay below the limit (they stay in the library, their file is in the cloud) and when each
// track was last used here (the oldest go first).
// #110: whether the hint «Add to Home Screen» (#39/AK6) was closed in this browser on this device.
// #115: the area (Player, Practice, Metronome) last chosen on this device, opened again after a restart.
// #113: the recording source (system audio or microphone) last chosen on this device.
// #54: the storage chosen for the sync on this device (the tokens are in the keychain or IndexedDB, never here).
// #123: whether the section with all tracks («Library») is open in the library list; closed by default.
// #129: the width of the library sidebar chosen on this device.
// #107: own tracks and folders (#114: and playlists) held back from the sync until the user keeps or removes
// them.
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
    this.installHintClosed = false,
    this.heldTracks = const {},
    this.heldFolders = const {},
    this.heldPlaylists = const {},
    this.area,
    this.recordingSource,
    this.syncProvider,
    this.libraryOpen = false,
    this.sidebarWidth,
    this.yearsRead = false,
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

  /// The hint «Add to Home Screen» was closed here and stays away (#110). Written only once true.
  final bool installHintClosed;

  /// #107: own tracks and folders, never synced, that a merge would remove because they were last changed
  /// before the purge horizon of the other devices. They stay here and are not synced until the user
  /// keeps or removes them.
  final Set<String> heldTracks;
  final Set<String> heldFolders;

  /// #114: playlists held back like [heldTracks] and [heldFolders].
  final Set<String> heldPlaylists;

  /// #115/AK7: name of the area last chosen here (`player`, `practice`, `metronome`); null until one is chosen.
  final String? area;

  /// #113/AK1: name of the recording source last chosen here (`system`, `microphone`); null until one is
  /// chosen.
  final String? recordingSource;

  /// #54/AK7: the storage chosen on this device (`google`); null: no sync, no connection (AK6).
  final String? syncProvider;

  /// #123/AK1, AK3: the section «Library» (all tracks) is open on this device. Closed unless the user opened
  /// it, so the playlists show without scrolling. Written only while true.
  final bool libraryOpen;

  /// #129/AK3: width of the library sidebar (points) chosen on this device; null: the default width.
  final double? sidebarWidth;

  /// #141/AK3: the years of the tracks already in the library were read from their files here. Written
  /// only once true.
  final bool yearsRead;

  DeviceSettings copyWith({
    bool? synced,
    int? cacheLimit,
    Set<String>? keepOffline,
    Set<String>? evicted,
    Map<String, int>? lastUsed,
    String? libraryId,
    bool? installHintClosed,
    Set<String>? heldTracks,
    Set<String>? heldFolders,
    Set<String>? heldPlaylists,
    String? area,
    String? recordingSource,
    String? Function()? syncProvider,
    bool? libraryOpen,
    double? Function()? sidebarWidth,
    bool? yearsRead,
  }) => DeviceSettings(
    deviceId: deviceId,
    synced: synced ?? this.synced,
    cacheLimit: cacheLimit ?? this.cacheLimit,
    keepOffline: keepOffline ?? this.keepOffline,
    evicted: evicted ?? this.evicted,
    lastUsed: lastUsed ?? this.lastUsed,
    libraryId: libraryId ?? this.libraryId,
    installHintClosed: installHintClosed ?? this.installHintClosed,
    heldTracks: heldTracks ?? this.heldTracks,
    heldFolders: heldFolders ?? this.heldFolders,
    heldPlaylists: heldPlaylists ?? this.heldPlaylists,
    area: area ?? this.area,
    recordingSource: recordingSource ?? this.recordingSource,
    syncProvider: syncProvider == null ? this.syncProvider : syncProvider(),
    libraryOpen: libraryOpen ?? this.libraryOpen,
    sidebarWidth: sidebarWidth == null ? this.sidebarWidth : sidebarWidth(),
    yearsRead: yearsRead ?? this.yearsRead,
  );

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    if (synced) 'synced': true,
    if (cacheLimit != defaultCacheLimit) 'cacheLimit': cacheLimit,
    if (keepOffline.isNotEmpty) 'keepOffline': [...keepOffline]..sort(),
    if (evicted.isNotEmpty) 'evicted': [...evicted]..sort(),
    if (lastUsed.isNotEmpty) 'lastUsed': lastUsed,
    if (libraryId != null) 'libraryId': libraryId,
    if (installHintClosed) 'installHintClosed': true,
    if (heldTracks.isNotEmpty) 'heldTracks': [...heldTracks]..sort(),
    if (heldFolders.isNotEmpty) 'heldFolders': [...heldFolders]..sort(),
    if (heldPlaylists.isNotEmpty) 'heldPlaylists': [...heldPlaylists]..sort(),
    if (area != null) 'area': area,
    if (recordingSource != null) 'recordingSource': recordingSource,
    if (syncProvider != null) 'syncProvider': syncProvider,
    if (libraryOpen) 'libraryOpen': true,
    if (sidebarWidth != null) 'sidebarWidth': sidebarWidth,
    if (yearsRead) 'yearsRead': true,
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
            installHintClosed: j['installHintClosed'] == true,
            heldTracks: _ids(j['heldTracks']),
            heldFolders: _ids(j['heldFolders']),
            heldPlaylists: _ids(j['heldPlaylists']),
            area: switch (j['area']) {
              final String v when v.isNotEmpty => v,
              _ => null,
            },
            recordingSource: switch (j['recordingSource']) {
              final String v when v.isNotEmpty => v,
              _ => null,
            },
            syncProvider: switch (j['syncProvider']) {
              final String v when v.isNotEmpty => v,
              _ => null,
            },
            libraryOpen: j['libraryOpen'] == true,
            sidebarWidth: switch (j['sidebarWidth']) {
              final num v when v > 0 && v.isFinite => v.toDouble(),
              _ => null,
            },
            yearsRead: j['yearsRead'] == true,
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
