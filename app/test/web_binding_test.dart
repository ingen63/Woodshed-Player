// #34: Teile der Web-Anbindung, die ohne Browser laufen: Wellenform aus der Zusammenfassung (die Getter im
// Browser sind synchron, das Worklet liefert nur Nachrichten). The browser library is tested in file_store_test.dart (#35).
// Wiedergabe, Tempo, Loop, Seek, Metronom und Pegel im echten Browser prüft tool/web_core_check.dart (AK3).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/player/audio_core.dart';
import 'package:woodshed_player/player/audio_core_ffi.dart';
import 'package:woodshed_player/player/waveform_summary.dart';

void main() {
  test('#34/AK1 AudioCore: FFI und Web, gewählt per bedingtem Import', () {
    // FFI-Implementierung (ohne sie anzulegen, das bräuchte die Kern-Bibliothek).
    expect(<AudioCore Function(Never)>[WpAudioCore.new], hasLength(1));
    final web = File('lib/player/audio_core_web.dart').readAsStringSync();
    expect(web, contains('class WebAudioCore implements AudioCore'));
    expect(web, contains("import 'dart:js_interop';"));
    final main = File('lib/main.dart').readAsStringSync();
    expect(
      main.replaceAll(RegExp(r'\s+'), ' '),
      contains(
        "import 'app/platform_native.dart' if (dart.library.js_interop) 'app/platform_web.dart';",
      ),
    );
    expect(
      File('lib/app/platform_native.dart').readAsStringSync(),
      contains('WpAudioCore('),
    );
    expect(
      File('lib/app/platform_web.dart').readAsStringSync(),
      contains('WebAudioCore.create('),
    );
  });

  group('#34/AK3 Wellenform im Browser aus der Zusammenfassung', () {
    // 10 s, 10 Abschnitte pro Sekunde: Abschnitt i hat Maximum i/100, Minimum −i/100.
    final n = 100;
    final summary = WaveformSummary(
      10,
      Float32List.fromList([for (var i = 0; i < n; i++) -i / 100]),
      Float32List.fromList([for (var i = 0; i < n; i++) i / 100]),
    );

    test('Übersicht fasst je Abschnitt Minimum und Maximum zusammen', () {
      final w = summary.query(0, 10, 10)!;
      expect(w.length, 10);
      for (var i = 0; i < 10; i++) {
        expect(w.max[i], closeTo((i * 10 + 9) / 100, 1e-6));
        expect(w.min[i], closeTo(-(i * 10 + 9) / 100, 1e-6));
      }
    });

    test(
      'Ausschnitt feiner als die Zusammenfassung nimmt den Abschnitt darunter',
      () {
        final w = summary.query(2, 3, 40)!;
        expect(w.length, 40);
        expect(w.max.first, closeTo(0.20, 1e-6));
        expect(w.max.last, closeTo(0.29, 1e-6));
      },
    );

    test('Grenzen werden auf die Dauer begrenzt, ungültige geben null', () {
      expect(summary.query(-5, 20, 5)!.max.last, closeTo(0.99, 1e-6));
      expect(summary.query(3, 3, 5), isNull);
      expect(summary.query(0, 10, 0), isNull);
      expect(
        WaveformSummary(0, Float32List(0), Float32List(0)).query(0, 1, 4),
        isNull,
      );
    });

    test('Anzahl Abschnitte: 200 pro Sekunde, begrenzt', () {
      expect(WaveformSummary.binsFor(3), 600);
      expect(WaveformSummary.binsFor(0), 1);
      expect(WaveformSummary.binsFor(36000), WaveformSummary.maxBins);
    });
  });
}
