// Device-local settings (#36/AK5): `device.json` next to `library.json`. They never go into the shared state
// and are never synced. Device-local are the device ID and, as they are added, the cloud account and tokens,
// the cache limit, the window frame and the output device, and whether this device has synced before (#104). File paths are not stored at all: the FileStore
// derives them on each device.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../app/file_platform.dart';

class DeviceSettings {
  const DeviceSettings({required this.deviceId, this.synced = false});

  static const fileName = 'device.json';

  /// Random ID of this device (16 hex digits); part of every stamp this device issues.
  final String deviceId;

  /// This device has merged or uploaded its shared state at least once (#104): from then on the purge
  /// horizon of other devices applies to its records. Written only once true, so older files stay valid.
  final bool synced;

  DeviceSettings copyWith({bool? synced}) =>
      DeviceSettings(deviceId: deviceId, synced: synced ?? this.synced);

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    if (synced) 'synced': true,
  };

  Future<void> save(FileStore store) => store.write(
    fileName,
    Uint8List.fromList(utf8.encode(jsonEncode(toJson()))),
  );

  static String newDeviceId([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(
      8,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// Reads `device.json`; creates it with a new device ID if it is missing or unreadable.
  static Future<DeviceSettings> load(FileStore store, {Random? random}) async {
    try {
      final raw = await store.read(fileName);
      if (raw != null) {
        final j = jsonDecode(utf8.decode(raw)) as Map;
        final id = j['deviceId'];
        if (id is String && RegExp(r'^[0-9a-f]{16}$').hasMatch(id)) {
          return DeviceSettings(deviceId: id, synced: j['synced'] == true);
        }
      }
    } catch (_) {}
    final d = DeviceSettings(deviceId: newDeviceId(random));
    try {
      await d.save(store);
    } catch (_) {}
    return d;
  }
}
