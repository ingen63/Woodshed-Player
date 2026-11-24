// #61: rules of smaller parts (natural sort order, device settings, file store, platform channel, cloud
// in memory), one per test; found by mutation testing (make mutants). Temporary folders and stores in
// memory only, never the real library.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/file_platform.dart';
import 'package:woodshed_player/app/file_store_io.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/library/natural_compare.dart';
import 'package:woodshed_player/player/waveform_summary.dart';
import 'package:woodshed_player/sync/in_memory_provider.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#16/AK5 natural sort order', () {
    test('numbers compare by value, then by their length (leading zeros)', () {
      int cmp(String a, String b) => NaturalKey(a).compareTo(NaturalKey(b));
      expect(cmp('Etüde 009', 'Etüde 10'), lessThan(0));
      expect(cmp('Etüde 10', 'Etüde 009'), greaterThan(0));
      expect(cmp('Etüde 1', 'Etüde 01'), lessThan(0));
      expect(cmp('Etüde 01', 'Etüde 1'), greaterThan(0));
    });
  });

  group('#36/AK5 device settings', () {
    test('a device ID that is not 16 hex digits is replaced', () async {
      for (final bad in ['xyz', 42, null]) {
        final store = MemoryFileStore()
          ..files['device.json'] = Uint8List.fromList(
            utf8.encode(jsonEncode({'deviceId': bad})),
          );
        final d = await DeviceSettings.load(store);
        expect(d.deviceId, matches(RegExp(r'^[0-9a-f]{16}$')), reason: '$bad');
      }
      final good = MemoryFileStore()
        ..files['device.json'] = Uint8List.fromList(
          utf8.encode(jsonEncode({'deviceId': '0123456789abcdef'})),
        );
      expect((await DeviceSettings.load(good)).deviceId, '0123456789abcdef');
    });
  });

  group('#35 file store on the file system', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('wp_support_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test(
      'used storage counts the files of the library, not linked ones',
      () async {
        final base = Directory('${tmp.path}/lib')..createSync();
        final outside = File('${tmp.path}/outside.bin')
          ..writeAsBytesSync(List.filled(5000, 1));
        File('${base.path}/a.bin').writeAsBytesSync(List.filled(100, 1));
        Link('${base.path}/link.bin').createSync(outside.path);
        final info = await IoFileStore(base).storageInfo();
        expect(info.used, 100);
      },
      skip: Platform.isWindows
          ? 'symbolic links need extra rights on Windows (#125: skip with reason)'
          : null,
    );
  });

  group('#61 platform channel of the app', () {
    Future<void> send(MethodCall call) => TestDefaultBinaryMessengerBinding
        .instance
        .defaultBinaryMessenger
        .handlePlatformMessage(
          'woodshed/files',
          const StandardMethodCodec().encodeMethodCall(call),
          (_) {},
        );

    test('dropped files reach their handler', () async {
      final p = ChannelFilePlatform();
      final dropped = <List<String>>[];
      p.onFileDrag = (e) {
        if (e is FileDragDrop) dropped.add(e.paths);
      };
      await send(const MethodCall('dropFiles', ['a.mp3', 'b.flac']));
      await send(const MethodCall('dropFiles', 'not a list'));
      await send(const MethodCall('somethingElse'));
      await send(const MethodCall('somethingElse', ['c.mp3']));
      expect(dropped, [
        ['a.mp3', 'b.flac'],
      ]);
    });
  });

  group('#144/AK1 menu bar through the platform channel', () {
    test('only macOS has a menu bar', () {
      final p = ChannelFilePlatform();
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          p.hasMenuBar,
          platform == TargetPlatform.macOS,
          reason: '$platform',
        );
      }
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'the titles go to «localizeMenuBar»; without a native side nothing fails',
      () async {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const channel = MethodChannel('woodshed/files');
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final p = ChannelFilePlatform();
        p.localizeMenuBar(const {'terminate:': 'Woodshed Player beenden'});
        await pumpEventQueue();
        expect(calls.single.method, 'localizeMenuBar');
        expect(calls.single.arguments, {
          'terminate:': 'Woodshed Player beenden',
        });
        messenger.setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(code: 'x'),
        );
        p.localizeMenuBar(const {});
        await pumpEventQueue();
      },
    );
  });

  group('#34 waveform in the browser', () {
    test('a summary without bins answers nothing, whatever the duration', () {
      final empty = WaveformSummary(5, Float32List(0), Float32List(0));
      expect(empty.query(0, 1, 4), isNull);
    });

    test('each section shows only its own fine bins', () {
      // 1 s with 200 bins; a spike only in the very first bin
      final maxs = Float32List(200)..fillRange(0, 200, 0.1);
      final mins = Float32List(200)..fillRange(0, 200, -0.1);
      maxs[0] = 0.9;
      mins[0] = -0.9;
      final w = WaveformSummary(1, mins, maxs).query(0, 1, 4)!;
      expect(w.max.first, closeTo(0.9, 1e-6));
      expect(w.max.skip(1), everyElement(closeTo(0.1, 1e-6)));
      expect(w.min.skip(1), everyElement(closeTo(-0.1, 1e-6)));
      expect(w.min.first, closeTo(-0.9, 1e-6));
    });
  });

  group('#37/AK7 cloud in memory', () {
    test('the quota counts the bytes of every file', () async {
      final c = InMemoryProvider();
      await c.put('a', Uint8List(3));
      await c.put('b', Uint8List(4));
      expect((await c.quota()).used, 7);
    });
  });
}
