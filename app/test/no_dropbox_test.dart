// #84: Dropbox is dropped (docs/KONZEPT-SYNC.md). Code and plan no longer announce it as a provider.
// Same scope as `grep -ri dropbox app docs`; runs from app/ like the other tests.
// #60: «repo» = checks of the repository's files, scripts and workflows (POSIX paths and shells);
// they run on Linux and macOS, the Windows job leaves them out (--exclude-tags repo).
@Tags(['repo'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _skipDirs = {
  'build',
  '.dart_tool',
  'Pods',
  'ephemeral',
  '.symlinks',
  'node_modules',
};
const _textExtensions = {
  '.dart',
  '.md',
  '.html',
  '.js',
  '.json',
  '.arb',
  '.yaml',
  '.txt',
  '.css',
  '.swift',
  '.cc',
  '.h',
  '.cmake',
};

Iterable<File> _textFiles(Directory dir) sync* {
  for (final entity in dir.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entity is Directory) {
      if (!_skipDirs.contains(name)) yield* _textFiles(entity);
    } else if (entity is File &&
        _textExtensions.any((ext) => name.endsWith(ext))) {
      yield entity;
    }
  }
}

/// Mentions that #84 explicitly keeps: reasons in the concepts, tests that forbid Dropbox,
/// the note on #71 in TESTS.md and the deletion note in the plan.
bool _allowed(String path, String line) {
  if (RegExp(r'^\.\./docs/KONZEPT-[^/]*\.md$').hasMatch(path)) return true;
  if (path.startsWith('test/')) return true;
  if (path.startsWith('tool/') && path.endsWith('_test.dart')) return true;
  if (path == '../docs/TESTS.md') return line.contains('#71');
  if (path == '../docs/PLAN-WEB-UND-SYNC.md') {
    return line.contains('gestrichen') || line.contains('entfällt');
  }
  return false;
}

void main() {
  test(
    '#84/AK4 grep for Dropbox in app and docs finds only allowed mentions',
    () {
      final hits = <String>[];
      for (final root in ['.', '../docs']) {
        for (final file in _textFiles(Directory(root))) {
          final path = file.path.startsWith('./')
              ? file.path.substring(2)
              : file.path;
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            if (!lines[i].toLowerCase().contains('dropbox')) continue;
            if (!_allowed(path, lines[i])) hits.add('$path:${i + 1}');
          }
        }
      }
      expect(hits, isEmpty);
    },
  );
}
