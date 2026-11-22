// #113: the recording source chosen on this device (device.json) and the microphone permission
// asked through the platform channel of the macOS runner.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/file_platform.dart';
import 'package:woodshed_player/library/library.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('wp_rec_source'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('#113/AK1 the recording source chosen last', () {
    test(
      'none until one is chosen; the choice is written to device.json',
      () async {
        final app = TestApp(Directory('${dir.path}/lib'));
        final Library library = app.library;
        await library.load();
        expect(library.recordingSource, isNull);
        await app.library.setRecordingSource('microphone');
        expect(app.library.recordingSource, 'microphone');
        final file = File('${dir.path}/lib/${DeviceSettings.fileName}');
        expect(
          file.readAsStringSync(),
          contains('"recordingSource":"microphone"'),
        );
        // The same choice again writes nothing.
        file.deleteSync();
        await app.library.setRecordingSource('microphone');
        expect(file.existsSync(), isFalse);
        await app.library.setRecordingSource('system');
        expect(file.readAsStringSync(), contains('"recordingSource":"system"'));

        final again = TestApp(Directory('${dir.path}/lib'));
        await again.library.load();
        expect(again.library.recordingSource, 'system');
      },
    );

    test(
      'device.json keeps the source; an empty or wrong value is none',
      () async {
        final app = TestApp(Directory('${dir.path}/lib'));
        await app.library.load();
        final store = app.library.store;
        const d = DeviceSettings(
          deviceId: '0123456789abcdef',
          recordingSource: 'microphone',
        );
        await d.save(store);
        expect(
          (await DeviceSettings.load(store)).recordingSource,
          'microphone',
        );
        expect(d.copyWith().recordingSource, 'microphone');
        expect(
          const DeviceSettings(deviceId: '0123456789abcdef').toJson(),
          isNot(contains('recordingSource')),
        );
        for (final bad in ['""', '3']) {
          await store.write(
            DeviceSettings.fileName,
            Uint8List.fromList(
              '{"deviceId":"0123456789abcdef","recordingSource":$bad}'
                  .codeUnits,
            ),
          );
          expect((await DeviceSettings.load(store)).recordingSource, isNull);
        }
      },
    );
  });

  group('#113/AK4 microphone permission through the channel', () {
    const channel = MethodChannel('woodshed/files');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<bool> answer(Object? reply) {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return reply;
      });
      return ChannelFilePlatform().microphoneAccess().whenComplete(
        () => expect(calls, ['microphoneAccess']),
      );
    }

    test('granted and refused as the runner answers', () async {
      expect(await answer(true), isTrue);
      expect(await answer(false), isFalse);
    });

    test('no answer counts as refused', () async {
      expect(await answer(null), isFalse);
    });

    test(
      'a platform without the method (iPhone/iPad) counts as refused',
      () async {
        messenger.setMockMethodCallHandler(channel, null);
        expect(await ChannelFilePlatform().microphoneAccess(), isFalse);
      },
    );
  });
}
