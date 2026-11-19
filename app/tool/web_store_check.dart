// #35: Prüfung der Speicher-Schicht im echten Browser. Nimmt die Dienste der Web-App (createAppController
// aus platform_web.dart) mit der Bibliothek im Origin Private File System. Teil 1 leert die Bibliothek,
// übergibt eine erzeugte Sinusdatei wie die Dateiauswahl (WebFilePlatform.register) und prüft Ablage im
// OPFS, SHA-256, Doppel, Abspielen und Speicheranzeige. Dann lädt die Seite neu (?teil=2) und Teil 2 prüft,
// dass der Titel noch da ist und spielt. Keine fremden Audiodateien.
// Bau und Aufruf: app/tool/web_store_check.sh, dann im Browser «Prüfung starten» (zweimal, vor und nach dem
// Neuladen; der AudioContext braucht eine Bedienung). Ergebnis als JSON in #ergebnis, Titel der Seite
// «Prüfung: n von m bestanden» (nach Teil 2 über beide Teile).
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:web/web.dart' as web;
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/file_platform_web.dart';
import 'package:woodshed_player/app/file_store_web.dart';
import 'package:woodshed_player/app/platform_web.dart';
import 'package:woodshed_player/player/audio_core_web.dart';

/// 16-Bit-Mono-WAV, [seconds] 440 Hz mit Pegel 0,5.
Uint8List sineWav({double seconds = 2, int rate = 44100}) {
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
    final v = 0.5 * sin(2 * pi * 440 * i / rate);
    b.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

class Check {
  Check(this.name, this.ok, this.detail);
  final String name;
  final bool ok;
  final String detail;

  Map<String, Object> toJson() => {
    'kriterium': name,
    'ok': ok,
    'messung': detail,
  };

  static Check fromJson(Map j) =>
      Check(j['kriterium'] as String, j['ok'] as bool, j['messung'] as String);
}

Future<void> wait(int ms) => Future.delayed(Duration(milliseconds: ms));

late final AppController app;
late final WebFilePlatform files;
late final WebAudioCore core;

/// Ergebnis von Teil 1 und ID des Titels, über das Neuladen hinweg.
const _key = 'wp-store-check';

/// Lädt [id], spielt kurz und misst den Pegel.
Future<(bool, double, double)> playBriefly(String id) async {
  final t = app.library.track(id);
  if (t == null) return (false, 0.0, 0.0);
  final ok = await app.select(t);
  app.player.play();
  var peak = 0.0;
  final sub = core.states.listen((s) => peak = max(peak, s.peak));
  await wait(600);
  await sub.cancel();
  app.player.pause();
  return (ok, app.player.duration, peak);
}

Future<List<Check>> part1() async {
  final checks = <Check>[];
  void add(String name, bool ok, String detail) =>
      checks.add(Check(name, ok, detail));
  final lib = app.library;
  final wav = sineWav();
  final hash = crypto.sha256.convert(wav).toString();

  final r = await app.importFiles([files.register('Sinus 440.wav', wav)]);
  final t = r.imported.isEmpty ? null : r.imported.single;
  add(
    'AK3 Dateiauswahl fügt Titel hinzu',
    t != null && lib.tracks.length == 1 && t.title == 'Sinus 440',
    'Titel: ${lib.tracks.map((t) => t.title).toList()}',
  );
  if (t == null) return checks;

  final store = await OpfsFileStore.open(libraryDir);
  final stored = await store.read('Tracks/${t.fileName}');
  final index = await store.read('library.json');
  add(
    'AK1 Datei und library.json im OPFS',
    stored != null &&
        stored.length == wav.length &&
        index != null &&
        utf8.decode(index).contains(t.id),
    'Tracks/${t.fileName}: ${stored?.length} Bytes (erwartet ${wav.length}), '
        'library.json: ${index?.length} Bytes',
  );
  add(
    'AK2 SHA-256 als contentHash',
    t.contentHash == hash && utf8.decode(index!).contains(hash),
    'contentHash ${t.contentHash}, erwartet $hash',
  );

  final again = await app.importFiles([files.register('Kopie.wav', wav)]);
  final stillOne = await store.exists('Tracks/${t.fileName}');
  add(
    'AK2 gleiche Datei nur einmal',
    again.imported.isEmpty &&
        again.duplicates.single.id == t.id &&
        lib.tracks.length == 1 &&
        stillOne,
    'neu: ${again.imported.length}, schon da: ${again.duplicates.length}, '
        'Titel in der Bibliothek: ${lib.tracks.length}',
  );

  final (loaded, duration, peak) = await playBriefly(t.id);
  add(
    'AK3 Titel spielt aus dem OPFS',
    loaded && (duration - 2).abs() < 0.02 && peak > 0.3,
    'geladen: $loaded, Dauer ${duration.toStringAsFixed(3)} s, Spitze ${peak.toStringAsFixed(3)}',
  );

  await lib.refreshStorage();
  final s = lib.storage;
  add(
    'AK5 persist() angefragt, Speicher angezeigt',
    s != null && s.quota != null && s.persisted != null && s.used > 0,
    'Zeile: «${s?.label}»',
  );

  web.window.localStorage.setItem(
    _key,
    jsonEncode({'id': t.id, 'hash': hash, 'checks': checks}),
  );
  return checks;
}

Future<List<Check>> part2() async {
  final saved =
      jsonDecode(web.window.localStorage.getItem(_key) ?? '{}') as Map;
  final checks = [
    for (final c in (saved['checks'] as List? ?? const []))
      Check.fromJson(c as Map),
  ];
  void add(String name, bool ok, String detail) =>
      checks.add(Check(name, ok, detail));
  final id = saved['id'] as String?;
  final t = id == null ? null : app.library.track(id);
  add(
    'AK3 nach dem Neuladen noch in der Bibliothek',
    t != null && t.contentHash == saved['hash'],
    'Titel: ${app.library.tracks.map((t) => '${t.title} ${t.contentHash?.substring(0, 8)}').toList()}',
  );
  final (loaded, duration, peak) = id == null
      ? (false, 0.0, 0.0)
      : await playBriefly(id);
  add(
    'AK3 spielt nach dem Neuladen',
    loaded && (duration - 2).abs() < 0.02 && peak > 0.3,
    'geladen: $loaded, Dauer ${duration.toStringAsFixed(3)} s, Spitze ${peak.toStringAsFixed(3)}',
  );
  final s = app.library.storage;
  add(
    'AK5 Speicherzeile',
    s != null && s.label.contains('belegt') && s.label.contains('frei'),
    'Zeile: «${s?.label}»',
  );
  return checks;
}

Future<void> main() async {
  final second = web.window.location.search.contains('teil=2');
  final body = web.document.body!;
  final status = web.HTMLParagraphElement()
    ..textContent = 'Kern wird geladen …';
  final button = web.HTMLButtonElement()
    ..id = 'start'
    ..textContent = 'Prüfung starten'
    ..disabled = true;
  final out = web.HTMLPreElement.pre()..id = 'ergebnis';
  // Über der (leeren) Flutter-Ansicht, sonst fängt sie die Klicks ab.
  final page = web.HTMLDivElement()
    ..style.position = 'relative'
    ..style.zIndex = '10'
    ..style.padding = '16px'
    ..style.background = '#fff';
  page
    ..append(
      web.HTMLHeadingElement.h1()
        ..textContent = 'Speicher-Schicht #35, Teil ${second ? 2 : 1}',
    )
    ..append(status)
    ..append(button)
    ..append(out);
  body.append(page);
  web.document.title = 'Prüfung bereit (Teil ${second ? 2 : 1})';
  if (!second) await OpfsFileStore.clear(libraryDir);
  app = await createAppController();
  files = app.files as WebFilePlatform;
  core = app.player.core as WebAudioCore;
  status.textContent = 'Bereit.';
  button.disabled = false;
  button.onclick = ((web.Event _) {
    core.wake(); // in der Bedienung, sonst bleibt der AudioContext stumm
    button.disabled = true;
    status.textContent = 'läuft …';
    (second ? part2() : part1()).then(
      (checks) {
        final passed = checks.where((c) => c.ok).length;
        out.textContent = const JsonEncoder.withIndent('  ').convert(checks);
        if (second) {
          status.textContent = '$passed von ${checks.length} bestanden';
          web.document.title =
              'Prüfung: $passed von ${checks.length} bestanden';
        } else {
          status.textContent =
              'Teil 1: $passed von ${checks.length}, lade neu …';
          Timer(const Duration(milliseconds: 500), () {
            web.window.location.search = '?teil=2';
          });
        }
      },
      onError: (Object e, StackTrace st) {
        out.textContent = 'Fehler: $e\n$st';
        web.document.title = 'Prüfung: Fehler';
      },
    );
  }).toJS;
}
