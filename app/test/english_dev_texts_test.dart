// #45/AK5: Developer texts (exceptions, logs, check output) in code are English.
//
// Scans the string literals of app/lib, app/packages, app/tool, app/web (index.html, manifest.json), app/pubspec.yaml and core/
// (without third_party and the closed W0 feasibility test) for umlauts, «ß» and common German words. In app/test
// only `reason:` texts are scanned, because test names and test data may stay German. UI texts live in the ARB
// files and are not scanned. Run again with: cd app && flutter test test/english_dev_texts_test.dart
// #60: «repo» = checks of the repository's files, scripts and workflows (POSIX paths and shells);
// they run on Linux and macOS, the Windows job leaves them out (--exclude-tags repo).
@Tags(['repo'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Umlauts and «ß».
final _umlauts = RegExp('[äöüÄÖÜß]');

/// German words that are not English words, matched case-sensitively (so the license name «MIT» stays allowed).
final _germanWords = RegExp(
  r'\b(und|oder|nicht|kein|keine|keinen|ist|sind|wird|werden|mit|bei|beim|von|nach|zum|zur|auf|aus|der|das|den|dem|'
  r'ein|eine|einen|noch|statt|ohne|zwischen|danach|alle|erst|bitte|'
  r'[Ff]ehler|FEHLER|[Dd]atei|[Dd]ateien|[Kk]ern|[Gg]eladen|[Ll]aden|[Pp]rüfung|[Pp]rüfungen|AUSNAHME|[Aa]usnahme|'
  r'[Ss]pitze|[Ww]ellenform|[Ee]rwartet|[Bb]estanden|[Ff]ehlt|[Ll]eer|[Ss]tille|[Ss]chlag|[Ss]chläge|[Kk]licks|'
  r'[Uu]nterteilung|[Ss]prung|[Aa]usgabe|[Qq]uelle|[Ww]iedergabe|[Aa]ufnahme|[Dd]auer|[Tt]itel|[Gg]espielt|'
  r'[Ll]ädt|[Ll]äuft|[Ss]tufe|[Pp]egel|[Rr]eferenz|[Rr]eservierungen|[Ee]reignis|[Ll]adefehler|[Ss]ekunde|'
  r'[Aa]bstände|[Dd]urchgänge|[Ww]anduhr|[Pp]lattform|[Mm]usiker|[Ss]pielt|bleibt|genau|letzter|weiter|nachführen|'
  r'angebunden|abgelehnt|[Uu]nverändert|[Ee]rgebnis|[Ww]eg|[Ff]requenz|[Tt]onhöhe|[Bb]ereit)\b',
);

/// Literals that are test data or language data on purpose (file, literal).
const _allowed = <(String, String)>{
  // Collation table for natural sorting of German titles.
  ('app/lib/library/natural_compare.dart', "'ä'"),
  ('app/lib/library/natural_compare.dart', "'ö'"),
  ('app/lib/library/natural_compare.dart', "'ü'"),
  ('app/lib/library/natural_compare.dart', "'ß'"),
  // Demo library for the store screenshots (test data).
  ('app/tool/screenshots_test.dart', "'Übungsband'"),
  ('app/tool/screenshots_test.dart', "'Etüde in A-Moll'"),
  ('app/tool/screenshots_test.dart', "'Arpeggio-Übung 14'"),
  // Messages of the hook after a commit, which talks to Claude in German (#7/AK7).
  ('app/tool/after_commit_hook_test.dart', "'grün'"),
  (
    'app/tool/after_commit_hook_test.dart',
    "'ändert Logik ohne Tests (app/lib/main.dart)'",
  ),
  (
    'app/tool/after_commit_hook_test.dart',
    "'«flutter test» ist fehlgeschlagen'",
  ),
  (
    'app/tool/after_commit_hook_test.dart',
    "'«C++-Kern bauen» ist fehlgeschlagen'",
  ),
  ('app/tool/after_commit_hook_test.dart', "'nicht das Format «Titel (#22)»'"),
  // Patterns of the German check comments in the issues (CLAUDE.md «Prüfe #22»), read by the
  // overview page (#12/AK3). The texts of the page itself live in tool/report/texts_de.json.
  (
    'app/tool/report/report.dart',
    r"'^\W*(?:(?:Erneute )?Prüfung\b|Nacharbeit AK\d+|AK\d+ (?:erfüllt|ok) in [0-9a-f]{7})'",
  ),
  ('app/tool/report/report.dart', "'durch den Anwender'"),
  (
    'app/tool/report/report.dart',
    r"'^\s*(?:[-*]\s+)?\**\s*((?:AK\d+(?:\s*,\s*|\s+und\s+)?)+)(.*)$'",
  ),
  (
    'app/tool/report/report.dart',
    r"'✅|❌|\bnicht\b|\boffen\b|\bteilweise\b|überholt|erfüllt|\bok\b|ist belegt'",
  ),
  (
    'app/tool/report/report.dart',
    r"'\balle (?:\d+ |\w+ )?Kriterien (?:sind )?(?:erfüllt|ok)|Ergebnis: \d+ von \d+ Kriterien ok'",
  ),
  ('app/tool/report/report.dart', r"'^(?:❌|nicht|offen|teilweise|überholt)$'"),
  // German words that the English error texts must not contain (#46).
  ('core/tests/player_tests.cpp', '"datei"'),
  ('core/tests/player_tests.cpp', '"fehler"'),
  ('core/tests/player_tests.cpp', '"nicht"'),
  ('core/tests/player_tests.cpp', '"kein"'),
  ('core/tests/player_tests.cpp', '"laden"'),
  ('core/tests/player_tests.cpp', '"gefunden"'),
  ('core/tests/player_tests.cpp', '"bitte"'),
};

const _roots = [
  'lib',
  'packages',
  'tool',
  'web/index.html',
  'web/manifest.json',
  'pubspec.yaml',
  '../core',
];
const _extensions = [
  '.dart',
  '.cpp',
  '.hpp',
  '.h',
  '.c',
  '.mm',
  '.mjs',
  '.js',
  '.sh',
  '.html',
  '.yaml',
  '.txt',
  '.cmake',
  '.podspec',
  '.swift',
];

bool _skipped(String path) =>
    path.contains('/third_party/') ||
    path.contains('/build') ||
    path.contains('/.dart_tool/') ||
    path.contains('/l10n/') ||
    path.contains('/w0_') ||
    path.contains('build_w0') ||
    path.contains('/web/wp_core/') ||
    path.contains('/generated') ||
    path.contains('/ephemeral/');

/// A string literal with its 1-based line number.
typedef Literal = ({int line, int offset, String text});

/// Extracts string literals; skips comments. Good enough for Dart, C/C++, JS, shell, YAML and HTML.
List<Literal> literals(String source, String path) {
  final hashComments =
      path.endsWith('.sh') ||
      path.endsWith('.yaml') ||
      path.endsWith('.txt') ||
      path.endsWith('.cmake') ||
      path.endsWith('.podspec');
  final out = <Literal>[];
  var line = 1;
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '\n') {
      line++;
      i++;
    } else if (!hashComments && source.startsWith('//', i)) {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
    } else if (!hashComments && source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      final stop = end < 0 ? source.length : end + 2;
      line += '\n'.allMatches(source.substring(i, stop)).length;
      i = stop;
    } else if (source.startsWith('<!--', i)) {
      final end = source.indexOf('-->', i + 4);
      final stop = end < 0 ? source.length : end + 3;
      line += '\n'.allMatches(source.substring(i, stop)).length;
      i = stop;
    } else if (hashComments &&
        c == '#' &&
        (i == 0 || RegExp(r'\s').hasMatch(source[i - 1]))) {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
    } else if (c == '"' || c == "'" || c == '`') {
      final triple = c != '`' && source.startsWith(c * 3, i);
      final quote = triple ? c * 3 : c;
      final multiline = triple || c == '`';
      final start = i;
      final startLine = line;
      i += quote.length;
      while (i < source.length && !source.startsWith(quote, i)) {
        if (source[i] == '\\' && !hashComments) i++;
        if (i < source.length && source[i] == '\n') {
          if (!multiline) {
            break; // unterminated: apostrophe in prose, not a literal
          }
          line++;
        }
        i++;
      }
      if (i < source.length && source.startsWith(quote, i)) {
        i += quote.length;
        out.add((
          line: startLine,
          offset: start,
          text: source.substring(start, i),
        ));
      }
    } else {
      i++;
    }
  }
  return out;
}

bool isGerman(String text) =>
    _umlauts.hasMatch(text) || _germanWords.hasMatch(text);

Iterable<File> _files(String root) {
  if (File(root).existsSync()) return [File(root)];
  return Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => _extensions.any(f.path.endsWith) && !_skipped(f.path));
}

String _repoPath(String path) =>
    path.startsWith('../') ? path.substring(3) : 'app/$path';

void main() {
  // slow: scans every source file of app/lib, app/packages, app/tool and core/
  test('#45/AK5: no German string literals in app/lib, app/packages, app/tool and core/', () {
    final hits = <String>[];
    for (final root in _roots) {
      for (final file in _files(root)) {
        final path = _repoPath(file.path);
        for (final l in literals(file.readAsStringSync(), path)) {
          if (isGerman(l.text) && !_allowed.contains((path, l.text))) {
            hits.add('$path:${l.line}: ${l.text}');
          }
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('#45/AK3: reason texts in the Dart tests are English', () {
    final hits = <String>[];
    for (final file in _files('test')) {
      final source = file.readAsStringSync();
      for (final l in literals(source, file.path)) {
        final before = source.substring(0, l.offset).trimRight();
        if (!before.endsWith('reason:')) continue;
        if (isGerman(l.text)) hits.add('app/${file.path}:${l.line}: ${l.text}');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('#45/AK5: the scanner finds German texts and skips comments', () {
    expect(isGerman("'Datei nicht lesbar'"), isTrue);
    expect(isGerman('"%d Prüfungen, %d Fehler"'), isTrue);
    expect(isGerman("'File not readable'"), isFalse);
    expect(isGerman("'MIT'"), isFalse);
    final found = literals(
      "// 'kein Audio'\nfinal a = 'no audio'; /* \"Fehler\" */\nb = `x\ny`;",
      'x.dart',
    );
    expect(found.map((l) => l.text), ["'no audio'", '`x\ny`']);
    expect(found.map((l) => l.line), [2, 3]);
  });
}
