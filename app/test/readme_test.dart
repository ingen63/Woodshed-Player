// #145: English README.md with a German README.de.md; the detailed reference lives in docs/.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File('../$path').readAsStringSync();

List<String> headings(String text) => RegExp(
  r'^## (.+)$',
  multiLine: true,
).allMatches(text).map((m) => m[1]!).toList();

/// Relative targets of Markdown links and images and of HTML src/srcset.
Iterable<String> relativeTargets(String text) sync* {
  final patterns = [
    RegExp(r'\]\(([^)\s]+)\)'),
    RegExp(r'(?:src|srcset)="([^"]+)"'),
  ];
  for (final p in patterns) {
    for (final m in p.allMatches(text)) {
      final target = m[1]!;
      if (RegExp(r'^(https?:|mailto:|#)').hasMatch(target)) continue;
      yield target.split('#').first;
    }
  }
}

void main() {
  const en = 'README.md', de = 'README.de.md';

  test('#145/AK1 each README links to the other at the top', () {
    String top(String f) => read(f).split('\n## ').first;
    expect(top(en), contains('[Deutsch](README.de.md)'));
    expect(top(de), contains('[English](README.md)'));
  });

  // #160: «Features» and «New in 1.0» for the 1.0 release.
  test('#145/AK2 both READMEs have the same sections in the same order', () {
    final english = headings(read(en));
    final german = headings(read(de));
    expect(english, [
      'Why Woodshed Player?',
      'Features',
      'New in 1.0',
      'Platforms',
      'Installation',
      'Command line (Mac)',
      'Privacy',
      'Under the hood',
      'Contributing',
      'License',
    ]);
    expect(german, [
      'Warum Woodshed Player?',
      'Funktionen',
      'Neu in 1.0',
      'Plattformen',
      'Installation',
      'Kommandozeile (Mac)',
      'Datenschutz',
      'Unter der Haube',
      'Mitarbeit',
      'Lizenz',
    ]);
  });

  test('#145/AK3 header with icon, web app, releases and badges only from github.com', () {
    for (final f in [en, de]) {
      final top = read(f).split('\n## ').first;
      expect(top, contains('app/web/icons/Icon-192.png'), reason: f);
      expect(
        top,
        contains('https://ingen63.github.io/Woodshed-Player/app/'),
        reason: f,
      );
      expect(
        top,
        contains('https://github.com/ingen63/Woodshed-Player/releases'),
        reason: f,
      );
      final badges = RegExp(r'\[!\[[^\]]*\]\(([^)]+)\)')
          .allMatches(top)
          .map((m) => m[1]!);
      expect(badges, isNotEmpty, reason: f);
      for (final b in badges) {
        expect(
          b,
          startsWith('https://github.com/ingen63/Woodshed-Player/'),
          reason: '$f: $b',
        );
      }
    }
  });

  test('#145/AK4 screenshots are the existing ones from docs/screenshots', () {
    for (final f in [en, de]) {
      final images = RegExp(r'(?:src|srcset)="([^"]+\.png)"')
          .allMatches(read(f))
          .map((m) => m[1]!)
          .toSet();
      expect(
        images.where((i) => i.startsWith('docs/screenshots/studio-')),
        hasLength(6),
        reason: f,
      );
    }
  });

  test('#145/AK6 privacy summary links to the policy and the details', () {
    for (final f in [en, de]) {
      final text = read(f);
      expect(
        text,
        contains('https://ingen63.github.io/Woodshed-Player/datenschutz.html'),
        reason: f,
      );
      expect(
        text,
        contains('docs/FUNKTIONEN.md#datenschutz-im-detail'),
        reason: f,
      );
    }
  });

  test('#145/AK8 the reference in docs/ keeps features, technique, release and privacy', () {
    final features = read('docs/FUNKTIONEN.md');
    final development = read('docs/ENTWICKLUNG.md');
    expect(headings(features), contains('Datenschutz im Detail'));
    expect(features, contains('| Abgleich über Google Drive (#54) |'));
    expect(
      headings(development),
      containsAll([
        'Release',
        'Swift-Altprojekt starten',
        'Technik',
        'Lizenzen im Detail',
      ]),
    );
    for (final f in [en, de]) {
      expect(read(f), contains('docs/FUNKTIONEN.md'), reason: f);
      expect(read(f), contains('docs/ENTWICKLUNG.md'), reason: f);
    }
  });

  test(
    '#145/AK11 every relative link and image points to an existing file',
    () {
      for (final f in [en, de, 'docs/FUNKTIONEN.md', 'docs/ENTWICKLUNG.md']) {
        final dir = File('../$f').parent.path;
        for (final target in relativeTargets(read(f))) {
          final path = '$dir/$target';
          expect(
            FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound,
            isTrue,
            reason: '$f → $target',
          );
        }
      }
    },
  );
}
