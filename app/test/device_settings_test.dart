// #54/AK7: the storage chosen for the sync is kept per device in device.json, never in the shared state.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/device_settings.dart';

import 'fakes.dart';

void main() {
  group('#54/AK7 the chosen storage is kept per device (device.json)', () {
    test('written and read back; missing fields stay missing', () async {
      final store = MemoryFileStore();
      final d = DeviceSettings(
        deviceId: '0123456789abcdef',
        syncProvider: 'google',
        area: 'practice',
        installHintClosed: true,
      );
      await d.save(store);
      final j =
          jsonDecode(utf8.decode(store.files[DeviceSettings.fileName]!)) as Map;
      expect(j['syncProvider'], 'google');
      expect(j['area'], 'practice');
      final back = await DeviceSettings.load(store, random: Random(1));
      expect(back.syncProvider, 'google');
      expect(back.area, 'practice');
      expect(back.installHintClosed, isTrue);
      final none = const DeviceSettings(deviceId: '0123456789abcdef').toJson();
      expect(none.containsKey('syncProvider'), isFalse);
      expect(none.containsKey('area'), isFalse);
      expect(d.copyWith(syncProvider: () => null).syncProvider, isNull);
      expect(d.copyWith().syncProvider, 'google');
      store.files[DeviceSettings.fileName] = Uint8List.fromList(
        utf8.encode(
          '{"deviceId":"0123456789abcdef","syncProvider":"","installHintClosed":"yes"}',
        ),
      );
      final odd = await DeviceSettings.load(store);
      expect(odd.syncProvider, isNull);
      expect(odd.installHintClosed, isFalse);
    });
  });
}
