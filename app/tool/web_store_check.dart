// #35: checks the storage layer in a real browser. Uses the web app's services (createAppController from
// platform_web.dart) with the library in the Origin Private File System. Part 1 clears the library, hands
// over a generated sine file the way the file picker does (WebFilePlatform.register) and checks storage in
// the OPFS, SHA-256, duplicates, playback and the storage line. Then the page reloads (?part=2) and part 2
// checks that the track is still there and plays. No third-party audio files.
// Build and run: app/tool/web_store_check.sh, then press «Start check» in the browser (twice, before and
// after the reload; the AudioContext needs a user gesture). Result as JSON in #result, page title
// «Check: n of m passed» (after part 2, covering both parts).
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:crypto/crypto.dart' as crypto;
import 'package:web/web.dart' as web;
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/file_platform_web.dart';
import 'package:woodshed_player/app/file_store_web.dart';
import 'package:woodshed_player/app/platform_web.dart';
import 'package:woodshed_player/player/audio_core_web.dart';
import 'package:woodshed_player/ui/messages.dart';

/// 16-bit mono WAV, [seconds] of 440 Hz at level 0.5.
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
    'criterion': name,
    'ok': ok,
    'measurement': detail,
  };

  static Check fromJson(Map j) => Check(
    j['criterion'] as String,
    j['ok'] as bool,
    j['measurement'] as String,
  );
}

Future<void> wait(int ms) => Future.delayed(Duration(milliseconds: ms));

late final AppController app;
late final WebFilePlatform files;
late final WebAudioCore core;

/// Result of part 1 and the track ID, kept across the reload.
const _key = 'wp-store-check';

/// The storage line is checked in German (#43).
final de = lookupAppLocalizations(const Locale('de'));

/// Loads [id], plays briefly and measures the level.
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
    'AK3 file picker adds the track',
    t != null && lib.tracks.length == 1 && t.title == 'Sinus 440',
    'tracks: ${lib.tracks.map((t) => t.title).toList()}',
  );
  if (t == null) return checks;

  final store = await OpfsFileStore.open(libraryDir);
  final stored = await store.read('Tracks/${t.fileName}');
  final index = await store.read('library.json');
  add(
    'AK1 file and library.json in the OPFS',
    stored != null &&
        stored.length == wav.length &&
        index != null &&
        utf8.decode(index).contains(t.id),
    'Tracks/${t.fileName}: ${stored?.length} Bytes (expected ${wav.length}), '
        'library.json: ${index?.length} Bytes',
  );
  add(
    'AK2 SHA-256 as contentHash',
    t.contentHash == hash && utf8.decode(index!).contains(hash),
    'contentHash ${t.contentHash}, expected $hash',
  );

  final again = await app.importFiles([files.register('Kopie.wav', wav)]);
  final stillOne = await store.exists('Tracks/${t.fileName}');
  add(
    'AK2 same file stored once',
    again.imported.isEmpty &&
        again.duplicates.single.id == t.id &&
        lib.tracks.length == 1 &&
        stillOne,
    'new: ${again.imported.length}, already there: ${again.duplicates.length}, '
        'tracks in the library: ${lib.tracks.length}',
  );

  final (loaded, duration, peak) = await playBriefly(t.id);
  add(
    'AK3 track plays from the OPFS',
    loaded && (duration - 2).abs() < 0.02 && peak > 0.3,
    'loaded: $loaded, duration ${duration.toStringAsFixed(3)} s, peak ${peak.toStringAsFixed(3)}',
  );

  await lib.refreshStorage();
  final s = lib.storage;
  add(
    'AK5 persist() requested, storage shown',
    s != null && s.quota != null && s.persisted != null && s.used > 0,
    'line: «${s == null ? null : storageLabel(de, s)}»',
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
    'AK3 still in the library after reload',
    t != null && t.contentHash == saved['hash'],
    'tracks: ${app.library.tracks.map((t) => '${t.title} ${t.contentHash?.substring(0, 8)}').toList()}',
  );
  final (loaded, duration, peak) = id == null
      ? (false, 0.0, 0.0)
      : await playBriefly(id);
  add(
    'AK3 plays after reload',
    loaded && (duration - 2).abs() < 0.02 && peak > 0.3,
    'loaded: $loaded, duration ${duration.toStringAsFixed(3)} s, peak ${peak.toStringAsFixed(3)}',
  );
  final s = app.library.storage;
  add(
    'AK5 storage line',
    s != null &&
        storageLabel(de, s).contains('belegt') &&
        storageLabel(de, s).contains('frei'),
    'line: «${s == null ? null : storageLabel(de, s)}»',
  );
  return checks;
}

Future<void> main() async {
  final second = web.window.location.search.contains('part=2');
  final body = web.document.body!;
  final status = web.HTMLParagraphElement()..textContent = 'Loading core …';
  final button = web.HTMLButtonElement()
    ..id = 'start'
    ..textContent = 'Start check'
    ..disabled = true;
  final out = web.HTMLPreElement.pre()..id = 'result';
  // Above the (empty) Flutter view, which would otherwise catch the clicks.
  final page = web.HTMLDivElement()
    ..style.position = 'relative'
    ..style.zIndex = '10'
    ..style.padding = '16px'
    ..style.background = '#fff';
  page
    ..append(
      web.HTMLHeadingElement.h1()
        ..textContent = 'Storage layer #35, part ${second ? 2 : 1}',
    )
    ..append(status)
    ..append(button)
    ..append(out);
  body.append(page);
  web.document.title = 'Check ready (part ${second ? 2 : 1})';
  if (!second) await OpfsFileStore.clear(libraryDir);
  app = await createAppController();
  files = app.files as WebFilePlatform;
  core = app.player.core as WebAudioCore;
  status.textContent = 'Ready.';
  button.disabled = false;
  button.onclick = ((web.Event _) {
    core.wake(); // inside the gesture, otherwise the AudioContext stays silent
    button.disabled = true;
    status.textContent = 'running …';
    (second ? part2() : part1()).then(
      (checks) {
        final passed = checks.where((c) => c.ok).length;
        out.textContent = const JsonEncoder.withIndent('  ').convert(checks);
        if (second) {
          status.textContent = '$passed of ${checks.length} passed';
          web.document.title = 'Check: $passed of ${checks.length} passed';
        } else {
          status.textContent =
              'Part 1: $passed of ${checks.length}, reloading …';
          Timer(const Duration(milliseconds: 500), () {
            web.window.location.search = '?part=2';
          });
        }
      },
      onError: (Object e, StackTrace st) {
        out.textContent = 'Error: $e\n$st';
        web.document.title = 'Check: error';
      },
    );
  }).toJS;
}
