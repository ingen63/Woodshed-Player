// #139: release workflow, release notes (tools/changelog.py) and packages (tools/package.sh).
// Runs from app/ like the other tool tests. The changelog tests need python3 (#125: WP_PYTHON_REQUIRED),
// the macOS package tests run on macOS only (clang, codesign, hdiutil).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../test/required_resource.dart';

final changelogTool = File('../tools/changelog.py').absolute.path;
final packageTool = File('../tools/package.sh').absolute.path;

String read(String path) => File(path).readAsStringSync();

/// The job [name] of [workflow] up to the next job.
String job(String workflow, String name) {
  final start = workflow.indexOf('\n  $name:\n');
  expect(start, isNot(-1), reason: 'job $name missing');
  final rest = workflow.substring(start + 1);
  final next = RegExp(r'\n  [a-z-]+:\n').firstMatch(rest.substring(1));
  return next == null ? rest : rest.substring(0, next.start + 1);
}

bool python() => needs(
  pythonRequired,
  available: hasPython,
  reason: 'python3 not installed',
);

/// German fixture in a file: no German literals in app/tool (#45/AK5).
final de = read('tool/testdata/changelog/CHANGELOG.md');

/// German section headings of the fixture, in their order: «new, changed, fixed», «tests».
final deSections = RegExp(
  r'^### (.*)$',
  multiLine: true,
).allMatches(de).map((m) => m[1]!).take(2).toList();

/// The German entry 0.9.0 of the fixture without its heading.
final deEntry = de.substring(
  de.indexOf('## Version 0.9.0\n\n') + '## Version 0.9.0\n\n'.length,
  de.indexOf('\n\n## Version 0.8.2'),
);

const en = '''# Changelog

Introduction.

## Version 0.9.0

Up front.

### New, changed, fixed

- **Something (#5, #7):** Text.

### Tests and development

- Tests (#9).

## Version 0.8.2

### New, changed, fixed

- Window (#130).
''';

/// A repository root with both changelogs and app/pubspec.yaml.
Directory fixture({
  String? german,
  String? english = en,
  String version = '0.9.0',
}) {
  final dir = Directory.systemTemp.createTempSync('wp_changelog_');
  addTearDown(() => dir.deleteSync(recursive: true));
  File('${dir.path}/CHANGELOG.md').writeAsStringSync(german ?? de);
  if (english != null) {
    File('${dir.path}/CHANGELOG.en.md').writeAsStringSync(english);
  }
  File('${dir.path}/app/pubspec.yaml')
    ..createSync(recursive: true)
    ..writeAsStringSync('name: woodshed_player\nversion: $version+3\n');
  return dir;
}

ProcessResult changelog(List<String> args, {Directory? root}) =>
    Process.runSync('python3', [
      changelogTool,
      if (root != null) ...['--root', root.path],
      ...args,
    ]);

ProcessResult package(List<String> args, {Map<String, String>? environment}) =>
    Process.runSync('bash', [packageTool, ...args], environment: environment);

void main() {
  final workflow = read('../.github/workflows/release.yml');
  final pages = read('../.github/workflows/pages.yml');

  group('#139/AK1 a tag push creates a release draft with the packages', () {
    test('runs on tags v* and creates a draft with the tag', () {
      expect(workflow, contains("tags: ['v*']"));
      final release = job(workflow, 'release');
      expect(release, contains('gh release create "\$TAG"'));
      expect(release, contains('--draft'));
      expect(release, contains('--verify-tag'));
      expect(release, contains('contents: write'));
      // no automatic publishing: the draft is published by hand
      expect(workflow, isNot(contains('--draft=false')));
    });

    test('builds the macOS .dmg and the web .zip and attaches both', () {
      expect(job(workflow, 'macos'), contains('runs-on: macos-latest'));
      expect(job(workflow, 'macos'), contains('flutter build macos --release'));
      expect(
        job(workflow, 'macos'),
        contains('tools/package.sh macos "\$TAG" dist'),
      );
      expect(
        job(workflow, 'web'),
        contains('tools/package.sh web "\$TAG" dist'),
      );
      final release = job(workflow, 'release');
      expect(
        release,
        contains("-name '*.dmg' -o -name '*.zip' -o -name '*.tar.gz'"),
      );
      expect(release, contains('test "\$(find dist -type f | wc -l)" -eq 4'));
    });

    test('#60: builds the Windows .zip and the Linux .tar.gz (x64)', () {
      final windows = job(workflow, 'windows');
      expect(windows, contains('runs-on: windows-latest'));
      expect(windows, contains('flutter build windows --release'));
      expect(windows, contains('tools/package.sh windows "\$TAG" dist'));
      final linux = job(workflow, 'linux');
      expect(linux, contains('runs-on: ubuntu-latest'));
      expect(linux, contains('libgtk-3-dev'));
      expect(linux, contains('flutter build linux --release'));
      expect(linux, contains('tools/package.sh linux "\$TAG" dist'));
      for (final j in [windows, linux]) {
        expect(j, contains('fetch-depth: 0'));
      }
    });

    test('the web app is built like the one on GitHub Pages', () {
      final web = job(workflow, 'web');
      // same steps as pages.yml: WASM core, its test under Node.js, flutter test, build, offline stamp
      for (final step in [
        'build_web_core.sh',
        'wp_core_web_test.mjs',
        'flutter test --reporter failures-only',
        'dart run tool/stamp_sw.dart build/web',
      ]) {
        expect(pages, contains(step));
        expect(web, contains(step));
      }
      // same build flags, only the base href differs (root of a web server instead of /<repo>/app/)
      String flags(String text) =>
          RegExp(r'flutter build web (.*?)--base-href \S+ \\\n\s*(.*)\n')
              .firstMatch(text)!
              .groups([1, 2])
              .join(' ');
      expect(flags(web), flags(pages));
      expect(web, contains('--base-href /'));
      final version = RegExp(r'(FLUTTER_VERSION|EMSDK_VERSION): (\S+)');
      String versions(String text) =>
          version.allMatches(text).map((m) => m[0]).toSet().join(',');
      expect(versions(workflow), versions(pages));
    });
  });

  group('#139/AK2 file names with app name, version and platform', () {
    test('name of each package', () {
      expect(
        package(['name', 'macos', 'v0.9.0']).stdout,
        'WoodshedPlayer-0.9.0-macos.dmg\n',
      );
      expect(
        package(['name', 'web', 'v0.9.0']).stdout,
        'WoodshedPlayer-0.9.0-web.zip\n',
      );
      expect(
        package(['name', 'web', 'v1.0.0-beta.2']).stdout,
        'WoodshedPlayer-1.0.0-beta.2-web.zip\n',
      );
      // #60
      expect(
        package(['name', 'windows', 'v1.0.0']).stdout,
        'WoodshedPlayer-1.0.0-windows.zip\n',
      );
      expect(
        package(['name', 'linux', 'v1.0.0']).stdout,
        'WoodshedPlayer-1.0.0-linux.tar.gz\n',
      );
    });

    test('no name without a version tag or for an unknown platform', () {
      final noTag = package(['name', 'macos', '0.9.0']);
      expect(noTag.exitCode, 1);
      expect(noTag.stderr, contains("tag '0.9.0' is not vX.Y.Z"));
      final platform = package(['name', 'android', 'v0.9.0']);
      expect(platform.exitCode, 1);
      expect(platform.stderr, contains("unknown platform 'android'"));
    });
  });

  group('#139/AK3 #139/AK4 web package', () {
    Directory webBuild(String js) {
      final dir = Directory.systemTemp.createTempSync('wp_web_build_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/index.html').writeAsStringSync('<html></html>');
      File('${dir.path}/main.dart.js').writeAsStringSync(js);
      return dir;
    }

    test('#139/AK3 the zip carries the app, LICENSE and the licence texts, without LAME', () {
      final build = webBuild('var a="v0.9.0",b="0.9.0";');
      final out = Directory.systemTemp.createTempSync('wp_release_');
      addTearDown(() => out.deleteSync(recursive: true));
      final result = package(['web', 'v0.9.0', out.path, build.path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final zip = '${out.path}/WoodshedPlayer-0.9.0-web.zip';
      expect(result.stdout, '$zip\n');
      final list = Process.runSync('unzip', ['-Z1', zip]).stdout as String;
      final files = list
          .split('\n')
          .where((f) => f.isNotEmpty && !f.endsWith('/'))
          .toSet();
      const p = 'WoodshedPlayer-0.9.0-web';
      expect(
        files,
        containsAll([
          '$p/index.html',
          '$p/main.dart.js',
          '$p/licenses/LICENSE',
          '$p/licenses/fonts/README.md',
          '$p/licenses/fonts/inter/OFL.txt',
          '$p/licenses/fonts/jetbrains-mono/OFL.txt',
          '$p/licenses/core/README.md',
          '$p/licenses/core/miniaudio/LICENSE',
          '$p/licenses/core/signalsmith-stretch/LICENSE.txt',
          '$p/licenses/core/signalsmith-linear/LICENSE.txt',
          '$p/licenses/core/flac/COPYING.Xiph',
        ]),
      );
      expect(files.where((f) => f.contains('lame')), isEmpty);
    });

    test(
      '#139/AK4 refuses a build without the tag or the version of the release',
      () {
        final out = Directory.systemTemp.createTempSync('wp_release_');
        addTearDown(() => out.deleteSync(recursive: true));
        final noTag = package([
          'web',
          'v0.9.0',
          out.path,
          webBuild('var b="0.9.0";').path,
        ]);
        expect(noTag.exitCode, 1);
        expect(noTag.stderr, contains('tag v0.9.0 not in main.dart.js'));
        final oldVersion = package([
          'web',
          'v0.9.0',
          out.path,
          webBuild('var a="v0.9.0",b="0.8.2";').path,
        ]);
        expect(oldVersion.exitCode, 1);
        expect(
          oldVersion.stderr,
          contains('version 0.9.0 not in main.dart.js'),
        );
        expect(out.listSync(), isEmpty);
      },
    );

    test('#139/AK4 the workflow stamps the tag into the web build', () {
      expect(
        job(workflow, 'web'),
        contains('--dart-define=WP_GIT_TAG="\$TAG"'),
      );
    });
  });

  group('#60 #139/AK4 Windows and Linux packages refuse a wrong build', () {
    Directory build(Map<String, String> files) {
      final dir = Directory.systemTemp.createTempSync('wp_desktop_build_');
      addTearDown(() => dir.deleteSync(recursive: true));
      files.forEach((name, text) {
        File('${dir.path}/$name')
          ..createSync(recursive: true)
          ..writeAsStringSync(text);
      });
      return dir;
    }

    test('without the tag in the program or the version in the Dart code', () {
      final out = Directory.systemTemp.createTempSync('wp_release_');
      addTearDown(() => out.deleteSync(recursive: true));
      final noTag = package([
        'linux',
        'v0.9.0',
        out.path,
        build({'woodshed-player': 'x', 'lib/libapp.so': '0.9.0'}).path,
      ]);
      expect(noTag.exitCode, 1);
      expect(
        noTag.stderr,
        contains('linux: tag v0.9.0 not in woodshed-player'),
      );
      final oldVersion = package([
        'windows',
        'v0.9.0',
        out.path,
        build({'WoodshedPlayer.exe': 'v0.9.0', 'data/app.so': '0.8.2'}).path,
      ]);
      expect(oldVersion.exitCode, 1);
      expect(
        oldVersion.stderr,
        contains('windows: version 0.9.0 not in app.so'),
      );
      expect(out.listSync(), isEmpty);
    });

    test('a program that is not x64', () {
      final out = Directory.systemTemp.createTempSync('wp_release_');
      addTearDown(() => out.deleteSync(recursive: true));
      final result = package([
        'linux',
        'v0.9.0',
        out.path,
        build({
          'woodshed-player': 'v0.9.0',
          'lib/libapp.so': '0.9.0',
          'lib/libwp_core.so': 'x',
          'lib/libflutter_linux_gtk.so': 'x',
        }).path,
      ]);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('linux: woodshed-player is not x86-64'));
    });

    test('Linux names the system libraries (LGPL, not in the package)', () {
      expect(read('../tools/package.sh'), contains('SYSTEM-LIBRARIES.txt'));
      final text = read('linux/SYSTEM-LIBRARIES.txt');
      expect(text, contains('GTK 3'));
      expect(text, contains('Lesser General Public License'));
      expect(text, contains('not part of this package'));
    });
  });

  group('#139/AK2 #139/AK3 #139/AK4 macOS package', () {
    late Directory work;
    late String universal;
    late String intelOnly;

    setUpAll(() {
      if (!Platform.isMacOS) return;
      work = Directory.systemTemp.createTempSync('wp_macos_package_');
      File('${work.path}/main.c')
          .writeAsStringSync('int main(void) { return 0; }\n');
      universal = '${work.path}/bin-universal';
      intelOnly = '${work.path}/bin-intel';
      for (final (out, archs) in [
        (universal, ['-arch', 'arm64', '-arch', 'x86_64']),
        (intelOnly, ['-arch', 'x86_64']),
      ]) {
        final cc = Process.runSync('clang', [
          ...archs,
          '${work.path}/main.c',
          '-o',
          out,
        ]);
        expect(cc.exitCode, 0, reason: '${cc.stderr}');
      }
    });
    tearDownAll(() {
      if (Platform.isMacOS) work.deleteSync(recursive: true);
    });

    /// A minimal ad hoc signed app: one binary, Info.plist with version and Git tag, maybe LAME.
    String app(
      String name, {
      String version = '0.9.0',
      String tag = 'v0.9.0',
      String? binary,
      bool lame = false,
    }) {
      final contents = Directory(
        '${work.path}/$name/Woodshed Player.app/Contents',
      )..createSync(recursive: true);
      Directory('${contents.path}/MacOS').createSync();
      File(binary ?? universal)
          .copySync('${contents.path}/MacOS/Woodshed Player');
      if (lame) {
        Directory('${contents.path}/Frameworks').createSync();
        File(universal)
            .copySync('${contents.path}/Frameworks/libmp3lame.dylib');
      }
      File('${contents.path}/Info.plist')
          .writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Woodshed Player</string>
<key>CFBundleIdentifier</key><string>test.woodshed.release</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>WPGitTag</key><string>$tag</string>
</dict></plist>
''');
      final bundle = contents.parent.path;
      final sign = Process.runSync('codesign', [
        '--force',
        '--deep',
        '--sign',
        '-',
        bundle,
      ]);
      expect(sign.exitCode, 0, reason: '${sign.stderr}');
      return bundle;
    }

    ProcessResult pack(
      String bundle, {
      Map<String, String>? environment,
      String tag = 'v0.9.0',
    }) => package([
      'macos',
      tag,
      '${work.path}/out',
      bundle,
    ], environment: environment);

    test('the dmg carries the universal app, Applications, LICENSE and the licence texts with LAME', () {
      if (!Platform.isMacOS) {
        return markTestSkipped('macOS only (clang, codesign, hdiutil)');
      }
      final result = pack(app('ok', lame: true));
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final dmg = '${work.path}/out/WoodshedPlayer-0.9.0-macos.dmg';
      expect(result.stdout, '$dmg\n');
      final mount = Directory('${work.path}/mount')..createSync();
      final attach = Process.runSync('hdiutil', [
        'attach',
        '-quiet',
        '-nobrowse',
        '-readonly',
        '-mountpoint',
        mount.path,
        dmg,
      ]);
      expect(attach.exitCode, 0, reason: '${attach.stderr}');
      addTearDown(
        () => Process.runSync('hdiutil', ['detach', '-quiet', mount.path]),
      );
      final files =
          Process.runSync('find', ['.'], workingDirectory: mount.path).stdout
              as String;
      expect(
        files.split('\n'),
        containsAll([
          './Woodshed Player.app/Contents/MacOS/Woodshed Player',
          './Applications',
          './Licenses/LICENSE',
          './Licenses/fonts/inter/OFL.txt',
          './Licenses/fonts/jetbrains-mono/OFL.txt',
          './Licenses/core/miniaudio/LICENSE',
          './Licenses/core/flac/COPYING.Xiph',
          './Licenses/core/lame/LICENSE.txt',
        ]),
      );
      expect(Link('${mount.path}/Applications').targetSync(), '/Applications');
      expect(read('${mount.path}/Licenses/LICENSE'), read('../LICENSE'));
    });

    test('refuses an app that is not universal', () {
      if (!Platform.isMacOS) return markTestSkipped('macOS only');
      final result = pack(app('intel', binary: intelOnly));
      expect(result.exitCode, 1);
      expect(
        result.stderr,
        contains('not universal (x86_64): Contents/MacOS/Woodshed Player'),
      );
    });

    test('#139/AK4 refuses an app with another version or tag', () {
      if (!Platform.isMacOS) return markTestSkipped('macOS only');
      final version = pack(app('version', version: '0.8.2'));
      expect(version.exitCode, 1);
      expect(version.stderr, contains('app version 0.8.2, tag v0.9.0'));
      final tag = pack(app('tag', tag: 'v0.8.2'));
      expect(tag.exitCode, 1);
      expect(tag.stderr, contains("tag in the app 'v0.8.2', expected v0.9.0"));
    });

    test(
      '#139/AK4 a pre-release: the app carries the version with digits only',
      () {
        // Flutter turns 1.0.0-beta.1 into 1.0.0.1 in CFBundleShortVersionString
        if (!Platform.isMacOS) return markTestSkipped('macOS only');
        final tag = 'v1.0.0-beta.1';
        final ok = pack(
          app('beta', version: '1.0.0.1', tag: tag),
          tag: tag,
        );
        expect(ok.exitCode, 0, reason: '${ok.stderr}');
        expect(ok.stdout, endsWith('WoodshedPlayer-1.0.0-beta.1-macos.dmg\n'));
        final other = pack(
          app('beta2', version: '1.0.0.2', tag: tag),
          tag: tag,
        );
        expect(other.exitCode, 1);
        expect(other.stderr, contains('app version 1.0.0.2, tag $tag'));
      },
    );

    test('refuses a broken signature', () {
      if (!Platform.isMacOS) return markTestSkipped('macOS only');
      final bundle = app('unsigned');
      File('$bundle/Contents/Info.plist').writeAsStringSync(
        read('$bundle/Contents/Info.plist')
            .replaceFirst('</dict>', '<key>X</key><string>y</string></dict>'),
      );
      final result = pack(bundle);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('signature of the app is not valid'));
    });

    test('WP_LAME_REQUIRED=1 refuses an app without LAME (#141)', () {
      if (!Platform.isMacOS) return markTestSkipped('macOS only');
      final result = pack(
        app('nolame'),
        environment: {'WP_LAME_REQUIRED': '1'},
      );
      expect(result.exitCode, 1);
      expect(result.stderr, contains('no LAME in the app'));
      expect(job(workflow, 'macos'), contains("WP_LAME_REQUIRED: '1'"));
    });

    test('#139/AK4 the workflow builds with all tags for the stamp', () {
      // app/tool/stamp_build_info.sh writes `git describe --tags` into the app's Info.plist
      expect(job(workflow, 'macos'), contains('fetch-depth: 0'));
      expect(
        read('tool/stamp_build_info.sh'),
        contains('git -C "\${SRCROOT}" describe --tags --abbrev=0'),
      );
    });
  });

  group('#139/AK4 tag and app version', () {
    test('the tag gives the version when it equals app/pubspec.yaml', () {
      if (!python()) return;
      final ok = changelog(['tag', 'v0.9.0'], root: fixture());
      expect(ok.exitCode, 0, reason: '${ok.stderr}');
      expect(ok.stdout, '0.9.0\n');
    });

    test('a tag that differs from the app version or is no version fails', () {
      if (!python()) return;
      final other = changelog(['tag', 'v0.9.1'], root: fixture());
      expect(other.exitCode, 1);
      expect(
        other.stderr,
        contains('tag v0.9.1 differs from version 0.9.0 in app/pubspec.yaml'),
      );
      final bad = changelog(['tag', 'release-1'], root: fixture());
      expect(bad.exitCode, 1);
      expect(bad.stderr, contains("tag 'release-1' is not vX.Y.Z"));
    });

    test('the workflow checks it before any package', () {
      expect(
        job(workflow, 'notes'),
        contains('python3 tools/changelog.py tag "\$TAG"'),
      );
    });
  });

  group('#139/AK5 release notes in fixed sections', () {
    test('the real changelogs pass the check', () {
      if (!python()) return;
      final result = changelog(['check']);
      expect(result.exitCode, 0, reason: '${result.stdout}');
      expect(result.stdout, 'changelog: 0 findings\n');
    });

    test('a fitting pair has no findings', () {
      if (!python()) return;
      final result = changelog(['check'], root: fixture());
      expect(result.stdout, 'changelog: 0 findings\n');
      expect(result.exitCode, 0);
    });

    test('unknown, misordered or missing sections are findings', () {
      if (!python()) return;
      final unknown = changelog(
        ['check'],
        root: fixture(
          german: de.replaceFirst('### ${deSections[1]}', '### Misc'),
        ),
      );
      expect(unknown.exitCode, 1);
      expect(
        unknown.stdout,
        contains('CHANGELOG.md 0.9.0 [sections]: unknown section «Misc»'),
      );
      final order = changelog(
        ['check'],
        root: fixture(
          german: () {
            final newBlock = de.substring(
              de.indexOf('### ${deSections[0]}'),
              de.indexOf('### ${deSections[1]}'),
            );
            const tests = '- Tests (#9).\n';
            final testsBlock = '### ${deSections[1]}\n\n$tests';
            return de
                .replaceFirst(newBlock + testsBlock, '$testsBlock\n$newBlock')
                .trimRight();
          }(),
        ),
      );
      expect(
        order.stdout,
        contains('CHANGELOG.md 0.9.0 [sections]: sections not in the order'),
      );
      final none = changelog(
        ['check'],
        root: fixture(
          english: en.replaceFirst(
            '### New, changed, fixed\n\n- Window (#130).',
            'Nothing.',
          ),
        ),
      );
      expect(
        none.stdout,
        contains('CHANGELOG.en.md 0.8.2 [sections]: no section'),
      );
    });

    test('every bullet names an issue', () {
      if (!python()) return;
      final result = changelog(
        ['check'],
        root: fixture(
          german: de.replaceFirst(
            '- Tests (#9).',
            '- Tests (#9).\n- No number.',
          ),
        ),
      );
      expect(result.exitCode, 1);
      expect(
        result.stdout,
        contains(
          'CHANGELOG.md 0.9.0 [issues]: «${deSections[1]}»: '
          'bullet without an issue number: «No number.»',
        ),
      );
    });

    test('a heading that is not «## Version X.Y.Z» or a repeated version is a finding', () {
      if (!python()) return;
      final heading = changelog(
        ['check'],
        root: fixture(german: de.replaceFirst('## Version 0.8.2', '## 0.8.2')),
      );
      expect(
        heading.stdout,
        contains(
          'CHANGELOG.md file [versions]: heading is not «## Version X.Y.Z»: «## 0.8.2»',
        ),
      );
      final twice = changelog(
        ['check'],
        root: fixture(
          english: en.replaceFirst('## Version 0.8.2', '## Version 0.9.0'),
        ),
      );
      expect(
        twice.stdout,
        contains(
          'CHANGELOG.en.md 0.9.0 [versions]: version appears more than once',
        ),
      );
    });
  });

  group('#139/AK6 the tool compares both languages, in make test and CI', () {
    test('different versions are a finding of the translation', () {
      if (!python()) return;
      final result = changelog(
        ['check'],
        root: fixture(english: en.substring(0, en.indexOf('## Version 0.8.2'))),
      );
      expect(result.exitCode, 1);
      expect(
        result.stdout,
        contains(
          "CHANGELOG.en.md file [versions]: versions ['0.9.0'], German ['0.9.0', '0.8.2']; missing ['0.8.2']",
        ),
      );
    });

    test('different sections are a finding', () {
      if (!python()) return;
      final result = changelog(
        ['check'],
        root: fixture(
          english: en.replaceFirst(
            '### Tests and development\n\n- Tests (#9).\n',
            '',
          ),
        ),
      );
      expect(result.exitCode, 1);
      expect(
        result.stdout,
        contains(
          "CHANGELOG.en.md 0.9.0 [sections]: sections ['New, changed, fixed'], German",
        ),
      );
    });

    test('different issue numbers are a finding per section', () {
      if (!python()) return;
      final result = changelog([
        'check',
      ], root: fixture(english: en.replaceFirst('(#5, #7)', '(#5, #8)')));
      expect(result.exitCode, 1);
      expect(
        result.stdout,
        contains(
          'CHANGELOG.en.md 0.9.0 [issues]: «New, changed, fixed»: missing #7; not in German #8',
        ),
      );
    });

    test('a missing file stops the check (exit 2)', () {
      if (!python()) return;
      final result = changelog(['check'], root: fixture(english: null));
      expect(result.exitCode, 2);
      expect(result.stdout, contains('CHANGELOG.en.md (English) missing'));
    });

    test('make test and the CI checks run it', () {
      final makefile = read('../Makefile');
      expect(makefile, contains('test: clean-tmp test-changelog '));
      expect(
        makefile,
        contains('test-changelog:\n\tpython3 tools/changelog.py check\n'),
      );
      final ci = read('../.github/workflows/test-quality.yml');
      expect(job(ci, 'checks'), contains('run: make test-changelog\n'));
      expect(job(ci, 'changes'), contains(r'CHANGELOG(\.en)?\.md$'));
      expect(
        job(workflow, 'notes'),
        contains('python3 tools/changelog.py check'),
      );
    });
  });

  group(
    '#139/AK7 a missing language stops the workflow before the packages',
    () {
      test('notes name the file and the language that lack the version', () {
        if (!python()) return;
        final result = changelog(
          ['notes', 'v0.9.0'],
          root: fixture(
            english: en.replaceFirst('## Version 0.9.0', '## Version 0.8.9'),
          ),
        );
        expect(result.exitCode, 1);
        expect(
          result.stderr,
          contains('CHANGELOG.en.md (English): version 0.9.0 missing'),
        );
        final german = changelog(['notes', 'v1.0.0'], root: fixture());
        expect(
          german.stderr,
          contains(
            'CHANGELOG.en.md (English): version 1.0.0 missing; '
            'CHANGELOG.md (German): version 1.0.0 missing',
          ),
        );
      });

      test('the package jobs need the notes job', () {
        expect(
          job(workflow, 'notes'),
          contains('python3 tools/changelog.py notes "\$TAG"'),
        );
        for (final name in ['macos', 'web', 'windows', 'linux']) {
          expect(job(workflow, name), contains('needs: notes'), reason: name);
        }
      });
    },
  );

  group('#139/AK8 text and title of the draft', () {
    test('English open, German folded', () {
      if (!python()) return;
      final result = changelog(['notes', 'v0.9.0'], root: fixture());
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        result.stdout,
        'Up front.\n\n### New, changed, fixed\n\n- **Something (#5, #7):** Text.\n\n### Tests and development\n\n'
        '- Tests (#9).\n\n<details>\n<summary>Deutsch</summary>\n\n$deEntry\n\n</details>\n',
      );
    });

    test('-o writes the text into a file', () {
      if (!python()) return;
      final root = fixture();
      final out = '${root.path}/notes.md';
      final result = changelog(['notes', '0.8.2', '-o', out], root: root);
      expect(result.exitCode, 0);
      expect(result.stdout, '');
      expect(
        read(out),
        startsWith('### New, changed, fixed\n\n- Window (#130).\n\n<details>'),
      );
    });

    test('the title is language-neutral', () {
      if (!python()) return;
      expect(changelog(['title', 'v0.9.0']).stdout, 'Woodshed Player 0.9.0\n');
      expect(
        changelog(['title', '1.0.0-beta.2']).stdout,
        'Woodshed Player 1.0.0 Beta 2\n',
      );
      expect(changelog(['title', 'next']).exitCode, 1);
    });

    test('the draft takes title and text from the tool', () {
      expect(
        job(workflow, 'notes'),
        contains('title=\$(python3 tools/changelog.py title "\$TAG")'),
      );
      final release = job(workflow, 'release');
      expect(release, contains('TITLE: \${{ needs.notes.outputs.title }}'));
      expect(release, contains('--title "\$TITLE"'));
      expect(
        release,
        contains('--notes-file artifacts/release-notes/release-notes.md'),
      );
    });
  });

  group('#139/AK9 versions 0.8.0 to 0.8.2', () {
    test('both files have them, newest first', () {
      for (final file in ['../CHANGELOG.md', '../CHANGELOG.en.md']) {
        final versions = RegExp(
          r'^## Version (\S+)$',
          multiLine: true,
        ).allMatches(read(file)).map((m) => m[1]);
        expect(
          versions,
          containsAllInOrder(['0.8.2', '0.8.1', '0.8.0']),
          reason: file,
        );
      }
    });
  });

  group('#139/AK10 a failed platform build gives no draft', () {
    test(
      'the draft needs every package job and runs only after their success',
      () {
        final release = job(workflow, 'release');
        expect(release, contains('needs: [notes, macos, web, windows, linux]'));
        // no `if:` on the job, which would let it run after a failure (always(), failure(), !cancelled())
        expect(release, isNot(contains('    if:')));
      },
    );

    test('a failed job names its platform', () {
      expect(
        job(workflow, 'macos'),
        contains('::error title=macOS package failed::'),
      );
      expect(
        job(workflow, 'web'),
        contains('::error title=Web package failed::'),
      );
      expect(
        job(workflow, 'windows'),
        contains('::error title=Windows package failed::'),
      );
      expect(
        job(workflow, 'linux'),
        contains('::error title=Linux package failed::'),
      );
    });
  });

  group('#139/AK11 README', () {
    String section(String file, String heading) {
      final text = read(file);
      final start = text.indexOf('\n## $heading\n');
      expect(start, isNot(-1), reason: '$file: section «$heading» missing');
      final end = text.indexOf('\n## ', start + 1);
      return text.substring(start, end == -1 ? text.length : end);
    }

    // #145: English README.md and German README.de.md both explain the installation.
    for (final (file, rightClick) in [
      ('../README.md', '**Right-click › '),
      ('../README.de.md', '**Rechtsklick › '),
    ]) {
      test(
        'installation in $file: where the packages are, how to open the unsigned app',
        () {
          final install = section(file, 'Installation');
          expect(install, contains('/releases'));
          expect(install, contains('WoodshedPlayer-<Version>-macos.dmg'));
          expect(install, contains('WoodshedPlayer-<Version>-web.zip'));
          // #60: Windows and Linux, x64
          expect(install, contains('WoodshedPlayer-<Version>-windows.zip'));
          expect(install, contains('WoodshedPlayer-<Version>-linux.tar.gz'));
          expect(install, contains('SmartScreen'));
          expect(install, contains('libgtk-3-0'));
          expect(install, contains(rightClick));
        },
      );
    }

    test('release flow: write, translate, check, tag', () {
      // #145: the release flow moved to docs/ENTWICKLUNG.md.
      final release = section('../docs/ENTWICKLUNG.md', 'Release');
      for (final step in [
        'CHANGELOG.md',
        'CHANGELOG.en.md',
        'make test-changelog',
        'git tag v',
        'Publish',
      ]) {
        expect(release, contains(step));
      }
    });
  });

  group('#139/AK12 free GitHub runners, no new secrets', () {
    test('only GitHub-hosted runners', () {
      final runners = RegExp(r'runs-on: (\S+)')
          .allMatches(workflow)
          .map((m) => m[1])
          .toSet();
      // #60: Windows on windows-latest
      expect(runners, {'ubuntu-latest', 'macos-latest', 'windows-latest'});
    });

    test(
      'no secret besides the run token and the Google desktop secret (#164)',
      () {
        // #164: AK12 adapted; the Windows and Linux packages need the secret of Google's desktop client.
        expect(
          RegExp(r'secrets\.(\w+)')
              .allMatches(workflow)
              .map((m) => m[1])
              .toSet(),
          {'WP_GOOGLE_DESKTOP_SECRET'},
        );
        for (final name in ['notes', 'macos', 'web', 'release']) {
          expect(
            job(workflow, name),
            isNot(contains('secrets.')),
            reason: name,
          );
        }
        expect(
          RegExp(r'GH_TOKEN: (.*)')
              .allMatches(workflow)
              .map((m) => m[1])
              .toSet(),
          {r'${{ github.token }}'},
        );
      },
    );
  });

  group('#164 Google desktop secret for the Windows and Linux packages', () {
    for (final platform in ['windows', 'linux']) {
      test(
        '#164/AK2: the $platform build gets the secret from the environment',
        () {
          final build = job(workflow, platform);
          expect(
            build,
            contains(
              r'WP_GOOGLE_DESKTOP_SECRET: ${{ secrets.WP_GOOGLE_DESKTOP_SECRET }}',
            ),
          );
          expect(
            build,
            contains(
              'flutter build $platform --release '
              r'--dart-define=WP_GOOGLE_DESKTOP_SECRET="$WP_GOOGLE_DESKTOP_SECRET"',
            ),
          );
          expect(build, isNot(contains(r'echo "$WP_GOOGLE_DESKTOP_SECRET')));
        },
      );
    }

    test('#164/AK2: no Google client secret in the repository', () {
      final files = Process.runSync(
        'git',
        ['ls-files'],
        workingDirectory: '..',
      ).stdout.toString().split('\n').where((f) => f.isNotEmpty);
      final secret = RegExp(r'GOCSPX-[\w-]{10,}');
      for (final f in files) {
        final file = File('../$f');
        if (!file.existsSync() || file.lengthSync() > 2000000) continue;
        final String text;
        try {
          text = file.readAsStringSync();
        } on FileSystemException {
          continue; // binary
        }
        expect(secret.hasMatch(text), isFalse, reason: f);
      }
    });

    test('#164/AK3: docs/ENTWICKLUNG.md names where the build takes the secret from', () {
      final docs = File('../docs/ENTWICKLUNG.md').readAsStringSync();
      expect(docs, contains('WP_GOOGLE_DESKTOP_SECRET'));
      expect(docs, contains('Secrets and variables'));
    });
  });
}
