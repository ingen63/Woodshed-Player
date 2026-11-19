// #17/AK7, #30/AK13: Rauchtest der echten App mit echtem Audio-Kern: Start, Datei laden, Play/Pause,
// je Grösse (Desktop, Tablet, Phone).
// Läuft in einem eigenen temporären Ordner, nie in der echten Bibliothek. Testaudio wird erzeugt (Sinus).
// Aufruf: cd app && flutter test integration_test -d macos
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/main.dart';

/// 16-Bit-Mono-WAV, 440 Hz.
Uint8List sineWav(double seconds, {int rate = 44100}) {
  final n = (seconds * rate).round();
  final b = ByteData(44 + n * 2);
  void str(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  b.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVEfmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  str(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    b.setInt16(
      44 + i * 2,
      (sin(2 * pi * 440 * i / rate) * 8000).round(),
      Endian.little,
    );
  }
  return b.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late File wav;
  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('wp_smoke');
    wav = File('${dir.path}/Sinus Testton.wav')..writeAsBytesSync(sineWav(3));
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  testWidgets('#17/AK7 Start, Datei laden, Play/Pause', (tester) async {
    final controller = await createAppController(
      baseDir: Directory('${dir.path}/app'),
    );
    controller.player.setVolume(0); // leise testen
    tester.view.physicalSize = const Size(1280, 800); // Desktop
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      WoodshedApp(controller: controller, locale: const Locale('de')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bibliothek'), findsWidgets); // Start

    await controller.importFiles([wav.path]); // wie Ziehen ins Fenster
    for (var i = 0; i < 100 && !controller.player.hasTrack; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('track:Sinus Testton')), findsOneWidget);
    expect(controller.player.hasTrack, isTrue);
    expect(controller.player.duration, closeTo(3.0, 0.01));
    expect(find.byKey(const Key('card:loop')), findsOneWidget);

    // #30/AK13: Rauchtest je Grösse mit echtem Kern und echter Wellenform (#28).
    for (final (name, size) in [
      ('desktop', const Size(1280, 800)),
      ('tablet', const Size(820, 1100)),
      ('phone', const Size(390, 844)),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      if (name == 'phone') {
        await tester.tap(find.byKey(const Key('openPlayer')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(Key('layout:$name')), findsOneWidget, reason: name);
      expect(find.byKey(const Key('waveformOverview')), findsOneWidget);
      expect(find.byKey(const Key('waveformDetail')), findsOneWidget);

      controller.player.seek(0);
      await tester.tap(find.byKey(const Key('playPause')));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(controller.player.isPlaying, isTrue, reason: name);
      expect(controller.player.position, greaterThan(0.2), reason: name);

      await tester.tap(find.byKey(const Key('playPause')));
      await tester.pump(const Duration(milliseconds: 200));
      final stopped = controller.player.position;
      expect(controller.player.isPlaying, isFalse, reason: name);
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.player.position, stopped, reason: name);
    }
  });
}
