// #17: Zusammenspiel von Bibliothek, Player und Metronom ohne Oberfläche; #22 Drag & Drop über den Kanal.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/file_platform.dart';
import 'package:woodshed_player/app/file_store_io.dart';
import 'package:woodshed_player/metronome/metronome_controller.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:wp_core/wp_core.dart';

import 'fakes.dart';

late Directory tmp;

File src(String name) => File('${tmp.path}/quelle/$name')
  ..createSync(recursive: true)
  ..writeAsStringSync(
    'audio $name',
  ); // distinct contents, otherwise a duplicate (#35)

/// Wartet, bis [done] gilt (Datei-Operationen laufen wirklich asynchron).
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'timeout');
}

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('wp_app_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<TestApp> app() async {
    final a = TestApp(Directory('${tmp.path}/lib'));
    await a.library.load();
    return a;
  }

  test(
    'Titel wählen lädt ihn mit seinen Einstellungen, ohne abzuspielen',
    () async {
      final a = await app();
      final t = (await a.library.importFiles([src('a.mp3').path]))
          .imported
          .single;
      a.library.updateSettings(
        t.id,
        const PlaybackSettings(speedEnabled: true, speed: 0.8),
      );
      a.player.unload();
      final f = a.controller.select(a.library.track(t.id)!);
      a.finishLoads(30);
      expect(await f, isTrue);
      expect(a.player.trackId, t.id);
      expect(a.player.title, 'a');
      expect(a.core.rateValue, closeTo(0.8, 1e-9));
      expect(a.player.isPlaying, isFalse);
      expect(a.controller.currentTrack?.id, t.id);
    },
  );

  /// Imports [file] through the controller (which loads the first track) and finishes the load with
  /// [loaded] seconds as the core reports them.
  Future<String> importAndLoad(TestApp a, String file, double loaded) async {
    final f = a.controller.importFiles([src(file).path]);
    await until(() => a.core.loadState == WpCode.loadRunning);
    a.finishLoads(loaded);
    return (await f).imported.single.id;
  }

  test('#42/AK5: a track without a duration gets the one found on loading, kept after reload', () async {
    final a = TestApp(Directory('${tmp.path}/lib'), duration: null);
    await a.library.load();
    final id = await importAndLoad(a, 'a.wav', 6);
    expect(a.library.track(id)!.duration, 6);
    await a.library.save();
    final reloaded = Library(
      IoFileStore(Directory('${tmp.path}/lib')),
      probe: (_) => null,
      readSource: readLocalFile,
    );
    await reloaded.load();
    expect(reloaded.track(id)!.duration, 6);
  });

  test('#42/AK5: a known duration stays as it is', () async {
    final a = await app();
    final id = await importAndLoad(a, 'a.mp3', 31);
    expect(a.player.trackId, id);
    expect(a.library.track(id)!.duration, 30);
  });

  test('Änderungen im Player landen in der Bibliothek', () async {
    final a = await app();
    final f = a.controller.importFiles([
      src('a.mp3').path,
    ]); // lädt den ersten Titel
    await until(() => a.core.loadState == WpCode.loadRunning);
    a.finishLoads(30);
    await f;
    a.player.setLoopStart(5);
    final id = a.player.trackId!;
    expect(a.library.track(id)!.settings.loopStart, 5);
    expect(a.library.track(id)!.settings.loopEnabled, isTrue);
  });

  test('Löschen des geladenen Titels entlädt den Player', () async {
    final a = await app();
    final f = a.controller.importFiles([src('a.mp3').path, src('b.mp3').path]);
    await until(() => a.core.loadState == WpCode.loadRunning);
    a.finishLoads();
    await f;
    final id = a.player.trackId!;
    a.player.play();
    a.controller.deleteTracks({id});
    expect(a.player.hasTrack, isFalse);
    expect(a.player.isPlaying, isFalse);
    expect(a.library.track(id), isNull);
    expect(a.library.tracks.length, 1);
  });

  test('ins Fenster gezogene Dateien kommen in die Bibliothek', () async {
    final a = await app();
    a.files.drop!([src('x.mp3').path, src('y.flac').path]);
    await until(() => a.library.tracks.length == 2);
    expect(a.library.tracks.map((t) => t.title), containsAll(['x', 'y']));
  });

  test(
    '#22/AK3 Regressionstest: «dropFiles» vom nativen Teil landet im Import',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final a = await app();
      final controller = AppController(
        library: a.library,
        player: a.player,
        metronome: MetronomeController(a.metronome),
        files: ChannelFilePlatform(),
      );
      addTearDown(controller.dispose);
      final paths = [src('x.mp3').path, src('y.flac').path];
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'woodshed/files',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('dropFiles', paths),
            ),
            (_) {},
          );
      await until(() => a.library.tracks.length == 2);
      expect(a.library.tracks.map((t) => t.title), containsAll(['x', 'y']));
    },
  );

  test('Importfehler werden als Meldung gezeigt', () async {
    final a = await app();
    await a.controller.importFiles(['${tmp.path}/fehlt.mp3']);
    expect((a.controller.message! as ImportFailed).files, ['fehlt.mp3']);
    a.controller.clearMessage();
    expect(a.controller.message, isNull);
  });
}
