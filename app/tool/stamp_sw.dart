// #39/AK1: stamps the built web app for the offline start. Writes the version (hash over the files) and the
// list of files to cache on install into sw.js of the build (line `const SHELL = …; // @shell`). A new
// build with other files gets another version, so browsers install the new worker and drop the old cache.
// Not cached up front: source maps and debug symbols, Flutter's own (empty) service worker, sw.js itself
// and the renderer variants under canvaskit/ (the browser picks one at run time; the worker caches the
// one it fetches).
//
// Usage (from app/, after `flutter build web`): dart run tool/stamp_sw.dart [<build directory>]
// (default build/web). Exit code 0: stamped; 2: directory, sw.js or the marker is missing.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Marks the line of sw.js that this tool replaces.
const marker = '// @shell';

/// Files cached on install, from all files of the build (paths relative to it, with «/»), sorted.
List<String> shellFiles(Iterable<String> paths) {
  bool skip(String p) =>
      p == 'sw.js' ||
      p == 'flutter_service_worker.js' ||
      p.endsWith('.map') ||
      p.endsWith('.symbols') ||
      p.startsWith('canvaskit/') ||
      p.split('/').any((part) => part.startsWith('.'));
  return [
    for (final p in paths)
      if (!skip(p)) p,
  ]..sort();
}

/// Version of the build: the first 16 hex digits of a SHA-256 over the names and contents of all its
/// files (also those not cached up front, so a new renderer gives a new version as well).
String buildVersion(Map<String, List<int>> files) {
  final names = files.keys.toList()..sort();
  final all = BytesBuilder(copy: false);
  for (final n in names) {
    all
      ..add(utf8.encode('$n\n${files[n]!.length}\n'))
      ..add(files[n]!);
  }
  return sha256.convert(all.takeBytes()).toString().substring(0, 16);
}

/// sw.js with [version] and [files] in the marked line; null if the marker is missing.
String? stamp(String source, String version, List<String> files) {
  final lines = const LineSplitter().convert(source);
  final i = lines.indexWhere((l) => l.trimRight().endsWith(marker));
  if (i < 0) return null;
  final shell = jsonEncode({'version': version, 'files': files});
  lines[i] = 'const SHELL = $shell; $marker';
  return '${lines.join('\n')}\n';
}

void main(List<String> args) {
  final dir = Directory(args.isEmpty ? 'build/web' : args.first);
  final sw = File('${dir.path}/sw.js');
  if (!sw.existsSync()) {
    stderr.writeln('stamp_sw: ${sw.path} is missing (run flutter build web)');
    exit(2);
  }
  final files = <String, List<int>>{};
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = e.path.substring(dir.path.length + 1).replaceAll(r'\', '/');
    if (rel == 'sw.js') continue;
    files[rel] = e.readAsBytesSync();
  }
  final version = buildVersion(files);
  final list = shellFiles(files.keys);
  final out = stamp(sw.readAsStringSync(), version, list);
  if (out == null) {
    stderr.writeln('stamp_sw: no line ending in «$marker» in ${sw.path}');
    exit(2);
  }
  sw.writeAsStringSync(out);
  final bytes = list.fold(0, (s, p) => s + files[p]!.length);
  stdout.writeln(
    'stamp_sw: version $version, ${list.length} files '
    '(${(bytes / 1e6).toStringAsFixed(1)} MB) cached on install',
  );
}
