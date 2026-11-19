// #34/AK3: Prüfung der Web-Anbindung im echten Browser. Nimmt die Dienste der Web-App (createAppController
// aus platform_web.dart: WASM-Kern im AudioWorklet, Sitzungs-Bibliothek, PlayerService, Metronom), lädt eine
// erzeugte Sinusdatei (WAV, 0–3 s 440 Hz mit Pegel 0,5, danach Stille) und die erzeugte sine440.m4a aus
// core/tests/audio (AAC, Dekodieren im Browser) und misst Position, Pegel, Wellenform, Tempo, Loop-Sprung,
// Seek und Metronom. Hören ist nicht nötig.
// Bau und Aufruf: app/tool/web_core_check.sh, dann im Browser «Prüfung starten» (der AudioContext braucht
// eine Bedienung). Ergebnis als JSON in #ergebnis, Titel der Seite «Prüfung: n von m bestanden».
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/file_platform_web.dart';
import 'package:woodshed_player/app/platform_web.dart';
import 'package:woodshed_player/player/audio_core_web.dart';

/// 16-Bit-Mono-WAV: [toneSeconds] 440 Hz mit Pegel [amplitude], danach Stille bis [seconds].
Uint8List toneThenSilenceWav({
  double seconds = 6,
  double toneSeconds = 3,
  double amplitude = 0.5,
  int rate = 44100,
}) {
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
  final tone = (toneSeconds * rate).round();
  for (var i = 0; i < n; i++) {
    final v = i < tone ? amplitude * sin(2 * pi * 440 * i / rate) : 0.0;
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
}

Future<void> wait(int ms) => Future.delayed(Duration(milliseconds: ms));
String f(double v) => v.toStringAsFixed(3);

late final AppController app;
late final WebFilePlatform files;
late final WebAudioCore core;

/// Sammelt die Zustände des Worklets während [ms] Millisekunden.
Future<List<WebCoreState>> record(int ms) async {
  final list = <WebCoreState>[];
  final sub = core.states.listen(list.add);
  await wait(ms);
  await sub.cancel();
  return list;
}

double maxPeak(List<WebCoreState> s) => s.fold(0.0, (m, x) => max(m, x.peak));

/// Fortschritt der Position pro Sekunde Audiozeit (1 = Originaltempo).
double positionRate(List<WebCoreState> s) {
  final a = s[s.length ~/ 5], b = s.last; // Anlauf auslassen
  return (b.position - a.position) / (b.time - a.time);
}

Future<List<Check>> run() async {
  final checks = <Check>[];
  void add(String name, bool ok, String detail) =>
      checks.add(Check(name, ok, detail));
  final p = app.player;

  // Laden (WAV, Kern dekodiert im Worklet)
  final wav = files.register('sinus-dann-stille.wav', toneThenSilenceWav());
  await app.importFiles([wav]);
  add(
    'Laden WAV',
    p.hasTrack && (p.duration - 6).abs() < 0.02 && p.error == null,
    'Dauer ${f(p.duration)} s (erwartet 6), Titel «${p.title}»',
  );

  // Wellenform: erste Hälfte ~0,5, zweite Hälfte still
  final w = p.waveform(0, p.duration, 60);
  if (w == null) {
    add('Wellenform', false, 'keine Wellenform');
  } else {
    final loud = [for (var i = 1; i < 29; i++) w.max[i]];
    final quiet = [for (var i = 31; i < 60; i++) max(w.max[i], -w.min[i])];
    final detail = p.waveform(1, 2, 300);
    final ok =
        loud.every((v) => v > 0.45 && v < 0.55) &&
        quiet.every((v) => v < 0.01) &&
        detail != null &&
        detail.length == 300;
    add(
      'Wellenform',
      ok,
      'Ton: ${f(loud.reduce(min))}–${f(loud.reduce(max))}, Stille bis ${f(quiet.reduce(max))}, '
          'Ausschnitt 1–2 s mit ${detail?.length} Abschnitten',
    );
  }

  // Wiedergabe: Position läuft in Echtzeit, Pegel wie in der Datei
  p.seek(0);
  p.play();
  await wait(150);
  var s = await record(1000);
  final rate1 = positionRate(s);
  add(
    'Wiedergabe/Position',
    (rate1 - 1).abs() < 0.05 && p.isPlaying && p.position > 0.9,
    'Position ${f(rate1)} s pro Sekunde, PlayerService.position ${f(p.position)} s',
  );
  final peak1 = maxPeak(s);
  p.setVolume(0.5);
  await wait(100);
  final peakHalf = maxPeak(await record(300));
  p.setVolume(1);
  add(
    'Pegel',
    (peak1 - 0.5).abs() < 0.06 && (peakHalf - 0.25).abs() < 0.04,
    'Spitze ${f(peak1)} bei Lautstärke 1 (erwartet 0,5), ${f(peakHalf)} bei 0,5 (erwartet 0,25)',
  );

  // Tempo 0,5×: Position halb so schnell, Pegel bleibt
  p.setSpeedEnabled(true);
  p.setSpeed(0.5);
  p.seek(0.2);
  await wait(200);
  s = await record(1000);
  final rateHalf = positionRate(s);
  add(
    'Tempo 0,5×',
    (rateHalf - 0.5).abs() < 0.04 && maxPeak(s) > 0.4,
    'Position ${f(rateHalf)} s pro Sekunde (erwartet 0,5), Spitze ${f(maxPeak(s))}',
  );
  p.setSpeed(1.5);
  p.seek(0.2);
  await wait(200);
  s = await record(800);
  final rateFast = positionRate(s);
  add(
    'Tempo 1,5×',
    (rateFast - 1.5).abs() < 0.08,
    'Position ${f(rateFast)} s pro Sekunde (erwartet 1,5)',
  );
  p.setSpeedEnabled(false);

  // Loop 0,5–1,5 s: Sprung zum Anfang, Durchgänge zählen
  p.setLoopStart(0.5);
  p.setLoopEnd(1.5);
  p.seek(1.2);
  final passes0 = core.loopPasses;
  await wait(50);
  s = await record(2600);
  final positions = s.map((x) => x.position);
  final lo = positions.reduce(min), hi = positions.reduce(max);
  final passes = core.loopPasses - passes0;
  add(
    'Loop-Sprung',
    lo >= 0.49 && hi <= 1.51 && passes >= 2 && p.activeLoop != null,
    'Position zwischen ${f(lo)} und ${f(hi)} s (Loop 0,5–1,5), $passes Durchgänge in 2,6 s',
  );
  p.setLoopEnabled(false);

  // Seek: in die Stille springen (Pegel 0), zurück in den Ton (Pegel 0,5)
  p.pause();
  p.seek(4);
  await wait(200);
  final pausedAt = core.position;
  p.play();
  await wait(100);
  s = await record(400);
  final silentPeak = maxPeak(s);
  final afterSeek = s.last.position;
  p.seek(1);
  await wait(100);
  final tonePeak = maxPeak(await record(300));
  p.pause();
  add(
    'Seek',
    (pausedAt - 4).abs() < 0.01 &&
        afterSeek > 4.3 &&
        afterSeek < 4.8 &&
        silentPeak < 0.01 &&
        tonePeak > 0.45,
    'pausiert bei ${f(pausedAt)} s, danach ${f(afterSeek)} s mit Spitze ${f(silentPeak)} (Stille), '
        'nach Seek auf 1 s Spitze ${f(tonePeak)}',
  );

  // Metronom 120 BPM: Klicks alle 0,5 s, still nach dem Stopp
  await wait(200);
  final m = app.metronome;
  m.setBpm(120);
  m.setSubdivision(1);
  m.start();
  s = await record(2700);
  final onsets = <double>[];
  var quietFor = 99;
  for (final x in s) {
    if (x.peak > 0.05 && quietFor >= 5) onsets.add(x.time);
    quietFor = x.peak < 0.02 ? quietFor + 1 : 0;
  }
  final gaps = [
    for (var i = 1; i < onsets.length; i++) onsets[i] - onsets[i - 1],
  ];
  final running = m.running;
  m.stop();
  await wait(200);
  final afterStop = maxPeak(await record(300));
  add(
    'Metronom',
    running &&
        gaps.length >= 3 &&
        gaps.every((g) => (g - 0.5).abs() < 0.03) &&
        afterStop < 0.01 &&
        !m.running,
    '${onsets.length} Klicks, Abstände ${gaps.map(f).join(', ')} s (erwartet 0,5), '
        'nach Stopp Spitze ${f(afterStop)}',
  );

  // AAC/M4A: der Browser dekodiert im Hauptthread, das PCM geht ins Worklet
  final response = await web.window.fetch('sine440.m4a'.toJS).toDart;
  if (!response.ok) {
    add('Laden M4A', false, 'sine440.m4a fehlt');
  } else {
    final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
    final r = await app.library.importFiles([
      files.register('sine440.m4a', bytes),
    ]);
    final loaded = r.imported.isNotEmpty && await app.select(r.imported.first);
    p.play();
    await wait(150);
    final peak = maxPeak(await record(500));
    p.pause();
    add(
      'Laden M4A',
      loaded && p.duration > 0.5 && peak > 0.1,
      'geladen: $loaded, Dauer ${f(p.duration)} s, Spitze ${f(peak)}',
    );
  }
  return checks;
}

Future<void> main() async {
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
    ..append(web.HTMLHeadingElement.h1()..textContent = 'Web-Anbindung #34')
    ..append(status)
    ..append(button)
    ..append(out);
  body.append(page);
  web.document.title = 'Prüfung bereit';
  app = await createAppController();
  files = app.files as WebFilePlatform;
  core = app.player.core as WebAudioCore;
  status.textContent = 'Bereit.';
  button.disabled = false;
  button.onclick = ((web.Event _) {
    core.wake(); // in der Bedienung, sonst bleibt der AudioContext stumm
    button.disabled = true;
    status.textContent = 'läuft …';
    run().then(
      (checks) {
        final passed = checks.where((c) => c.ok).length;
        out.textContent = const JsonEncoder.withIndent('  ').convert(checks);
        status.textContent = '$passed von ${checks.length} bestanden';
        web.document.title = 'Prüfung: $passed von ${checks.length} bestanden';
      },
      onError: (Object e, StackTrace st) {
        out.textContent = 'Fehler: $e\n$st';
        web.document.title = 'Prüfung: Fehler';
      },
    );
  }).toJS;
}
