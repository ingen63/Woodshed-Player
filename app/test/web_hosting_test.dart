// #41: web app on GitHub Pages under /app/ – workflow, service worker for COOP/COEP, site build and the
// documents that describe platforms, cloud and hosting. Runs from app/ like the other tests.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('#41/AK1 workflow', () {
    final workflow = read('../.github/workflows/pages.yml');

    test('runs on every push to main and on tags', () {
      expect(workflow, contains('branches: [main]'));
      expect(workflow, contains("tags: ['v*']"));
      // The whole site goes online with every push, not only when certain files change.
      expect(workflow, isNot(contains('paths:')));
    });

    test('a tag push publishes through a run on main', () {
      // The github-pages environment only lets main deploy.
      expect(workflow, contains("if: github.ref_type == 'tag'"));
      expect(workflow, contains('gh workflow run pages.yml'));
      expect(workflow, contains('--ref main'));
      expect(workflow, contains("if: github.ref_type != 'tag'"));
    });

    test(
      'builds the app from the latest tag and leaves it out without one',
      () {
        expect(workflow, contains('git describe --tags --abbrev=0'));
        expect(workflow, contains('ref: \${{ steps.tag.outputs.tag }}'));
        expect(workflow, contains("if: steps.tag.outputs.tag != ''"));
      },
    );

    test('runs the tests before the build and builds the WASM core', () {
      final core = workflow.indexOf('build_web_core.sh');
      final node = workflow.indexOf('wp_core_web_test.mjs');
      final flutterTest = workflow.indexOf('flutter test');
      final build = workflow.indexOf('flutter build web');
      expect([core, node, flutterTest, build], everyElement(greaterThan(0)));
      expect(core < node && node < build && flutterTest < build, isTrue);
      expect(workflow, contains('--base-href "\$BASE_HREF"'));
      expect(workflow, contains('/app/'));
      // the site gets the built app (--app) only when a tag exists (#64: quoted, without word splitting)
      expect(workflow, contains("&& 'app-src/app/build/web' || ''"));
      expect(workflow, contains(r'${APP_DIR:+--app "$APP_DIR"}'));
    });
  });

  group('#41/AK2 service worker', () {
    test('sw.js sets COOP and COEP on same-origin responses', () {
      final sw = read('web/sw.js');
      expect(sw, contains("'Cross-Origin-Opener-Policy', 'same-origin'"));
      expect(sw, contains("'Cross-Origin-Embedder-Policy', 'require-corp'"));
      expect(sw, contains('self.location.origin'));
    });

    test('index.html registers it before Flutter starts and reloads once', () {
      final index = read('web/index.html');
      final register = index.indexOf("serviceWorker.register('sw.js'");
      final bootstrap = index.indexOf("'flutter_bootstrap.js'");
      expect(register, greaterThan(0));
      expect(bootstrap, greaterThan(register));
      expect(index, contains('crossOriginIsolated'));
      expect(index, contains('location.reload()'));
      // Only one service worker: Flutter's loader must not register its own.
      expect(
        read('web/flutter_bootstrap.js'),
        isNot(contains('serviceWorkerSettings')),
      );
    });
  });

  group('#41/AK1 site build with the app', () {
    final python = Process.runSync('which', ['python3']).exitCode == 0;
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('wp_site_app'));
    tearDown(() => tmp.deleteSync(recursive: true));

    const secrets = {
      'CONTROLLER_NAME': 'Test Person',
      'CONTROLLER_ADDRESS': 'Teststrasse 1, 0000 Testort',
      'CONTACT_EMAIL': 'test@example.org',
    };

    ProcessResult build(List<String> extra) => Process.runSync(
      'python3',
      ['-I', '../site/build_site.py', '${tmp.path}/out', ...extra],
      environment: secrets,
      includeParentEnvironment: false,
    );

    test('puts the app under app/ and links it from the start page', () {
      final app = Directory('${tmp.path}/web')..createSync();
      File('${app.path}/index.html').writeAsStringSync('<!doctype html>');
      File('${app.path}/sw.js').writeAsStringSync('// sw');
      final r = build(['--app', app.path]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(File('${tmp.path}/out/app/index.html').existsSync(), isTrue);
      expect(File('${tmp.path}/out/app/sw.js').existsSync(), isTrue);
      final index = read('${tmp.path}/out/index.html');
      expect(index, contains('href="app/"'));
      expect(index, isNot(contains('<!--app-->')));
      expect(File('${tmp.path}/out/w0/index.html').existsSync(), isTrue);
      expect(
        File('${tmp.path}/out/m0/index.html').existsSync(),
        isTrue,
        reason: '#52',
      );
      expect(File('${tmp.path}/out/datenschutz.html').existsSync(), isTrue);
    }, skip: !python);

    test('without a tag the app and its button are left out', () {
      final r = build([]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(Directory('${tmp.path}/out/app').existsSync(), isFalse);
      expect(
        read('${tmp.path}/out/index.html'),
        isNot(contains('href="app/"')),
      );
    }, skip: !python);

    test('fails when the app folder has no index.html', () {
      final r = build(['--app', '${tmp.path}/missing']);
      expect(r.exitCode, isNot(0));
    }, skip: !python);
  });

  group('#41 documents', () {
    test('#41/AK3 README names platforms, cloud and hosting', () {
      final readme = read('../README.md');
      expect(readme, contains('Plattformen'));
      expect(readme, contains('Google Drive'));
      expect(readme, contains('OneDrive'));
      expect(readme, contains('direkte Verbindung'));
      expect(readme, contains('GitHub Pages'));
      expect(
        readme,
        contains('https://ingen63.github.io/Woodshed-Player/app/'),
      );
      expect(readme, isNot(contains('Dropbox')));
    });

    test('#41/AK4 UMBAUPLAN replaces Android by the web app', () {
      final plan = read('../docs/UMBAUPLAN-FLUTTER.md');
      expect(plan, contains('Web-App'));
      expect(plan, contains('PLAN-WEB-UND-SYNC.md'));
      expect(plan, isNot(contains('Foreground-Service')));
    });

    test(
      '#41/AK5 CLAUDE.md has the network exception with relays and STUN',
      () {
        final rules = read('../CLAUDE.md');
        expect(rules, contains('Google Drive oder OneDrive'));
        expect(rules, contains('Relays'));
        expect(rules, contains('STUN'));
        expect(rules, contains('Laden der Web-App'));
      },
    );
  });
}
