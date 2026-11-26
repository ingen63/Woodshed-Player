// #54/AK7: the storage chosen for the sync is kept per device in device.json, never in the shared state.
// #129/AK3: the width of the library sidebar, too. #147/AK9: threshold and pause of «Armed».
// #156/AK1: whether «Armed» stays on after a take.
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

  test(
    '#129/AK3 device.json: kept with the other fields, odd values ignored',
    () async {
      final store = MemoryFileStore();
      final d = const DeviceSettings(
        deviceId: '0123456789abcdef',
        sidebarWidth: 312.5,
        area: 'practice',
      );
      await d.save(store);
      final back = await DeviceSettings.load(store, random: Random(1));
      expect(back.sidebarWidth, 312.5);
      expect(back.area, 'practice');
      expect(back.copyWith().sidebarWidth, 312.5);
      expect(back.copyWith(sidebarWidth: () => null).sidebarWidth, isNull);
      expect(back.copyWith(area: 'player').sidebarWidth, 312.5);
      expect(
        const DeviceSettings(deviceId: '0123456789abcdef').toJson(),
        isNot(contains('sidebarWidth')),
      );
      for (final odd in ['"wide"', '0', '-10', 'null']) {
        store.files[DeviceSettings.fileName] = Uint8List.fromList(
          utf8.encode('{"deviceId":"0123456789abcdef","sidebarWidth":$odd}'),
        );
        final o = await DeviceSettings.load(store);
        expect(o.sidebarWidth, isNull, reason: odd);
        expect(o.deviceId, '0123456789abcdef');
      }
      store.files[DeviceSettings.fileName] = Uint8List.fromList(
        utf8.encode('{"deviceId":"0123456789abcdef","sidebarWidth":300}'),
      );
      expect((await DeviceSettings.load(store)).sidebarWidth, 300);
    },
  );

  test('#147/AK9 device.json: threshold and pause of «Armed» are kept, odd values ignored', () async {
    final store = MemoryFileStore();
    const d = DeviceSettings(
      deviceId: '0123456789abcdef',
      synced: true,
      armThresholdDb: -42,
      armSilenceSeconds: 7.5,
    );
    await d.save(store);
    final j =
        jsonDecode(utf8.decode(store.files[DeviceSettings.fileName]!)) as Map;
    expect(j['synced'], isTrue);
    final back = await DeviceSettings.load(store, random: Random(1));
    expect(back.synced, isTrue);
    expect(back.armThresholdDb, -42);
    expect(back.armSilenceSeconds, 7.5);
    expect(back.libraryOpen, isFalse);
    expect(back.copyWith(area: 'player').armThresholdDb, -42);
    final none = const DeviceSettings(deviceId: '0123456789abcdef');
    expect(none.libraryOpen, isFalse);
    expect(none.synced, isFalse);
    expect(none.toJson(), isNot(contains('armThresholdDb')));
    expect(none.toJson(), isNot(contains('armSilenceSeconds')));
    expect(none.toJson(), isNot(contains('synced')));
    for (final odd in ['"loud"', 'null', '[]']) {
      store.files[DeviceSettings.fileName] = Uint8List.fromList(
        utf8.encode(
          '{"deviceId":"0123456789abcdef","armThresholdDb":$odd,"armSilenceSeconds":$odd}',
        ),
      );
      final o = await DeviceSettings.load(store);
      expect(o.armThresholdDb, isNull, reason: odd);
      expect(o.armSilenceSeconds, isNull, reason: odd);
    }
  });

  test(
    '#156/AK1 device.json: «Armed» goes off after a take unless kept on',
    () async {
      final store = MemoryFileStore();
      const off = DeviceSettings(deviceId: '0123456789abcdef');
      expect(off.armKeepsOn, isFalse);
      expect(off.toJson(), isNot(contains('armKeepsOn')));
      final on = off.copyWith(armKeepsOn: true);
      expect(on.toJson()['armKeepsOn'], isTrue);
      await on.save(store);
      expect((await DeviceSettings.load(store)).armKeepsOn, isTrue);
      expect(on.copyWith(area: 'player').armKeepsOn, isTrue);
      for (final odd in ['false', '"true"', '1', 'null']) {
        store.files[DeviceSettings.fileName] = Uint8List.fromList(
          utf8.encode('{"deviceId":"0123456789abcdef","armKeepsOn":$odd}'),
        );
        expect(
          (await DeviceSettings.load(store)).armKeepsOn,
          isFalse,
          reason: odd,
        );
      }
    },
  );
}
