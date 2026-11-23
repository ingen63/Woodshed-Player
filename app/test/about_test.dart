// #50: published privacy policy and terms, About dialog with links. Libraries live in temporary folders.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_info.dart';
import 'package:woodshed_player/app/file_platform.dart';
import 'package:woodshed_player/main.dart';

import 'fakes.dart';
import 'required_resource.dart';

final docs = ['../docs/DATENSCHUTZ.md', '../docs/NUTZUNGSBEDINGUNGEN.md'];
const personPlaceholders = {
  '{{CONTROLLER_NAME}}',
  '{{CONTROLLER_ADDRESS}}',
  '{{CONTACT_EMAIL}}',
};

void main() {
  group('#50 texts', () {
    for (final path in docs) {
      test('#50/AK3 $path has no square-bracket placeholders', () {
        final text = File(path).readAsStringSync();
        // Square brackets are only allowed as Markdown links: [text](url).
        final left = RegExp(r'\[[^\]]*\](?!\()').allMatches(text);
        expect(left.map((m) => m[0]), isEmpty);
      });

      test('#50/AK3 $path keeps only the person placeholders', () {
        final text = File(path).readAsStringSync();
        final found = RegExp(r'\{\{[^}]*\}\}')
            .allMatches(text)
            .map((m) => m[0]!)
            .toSet();
        expect(found.difference(personPlaceholders), isEmpty);
        expect(found, contains('{{CONTACT_EMAIL}}'));
      });

      test('#50/AK3 $path matches the sync concept and house style', () {
        final text = File(path).readAsStringSync();
        expect(text, isNot(contains('Dropbox')));
        expect(text, isNot(contains('ß')));
        expect(text, isNot(contains('Entwurf')));
        expect(text, contains('Google'));
        expect(text, contains('Microsoft'));
      });
    }

    test('#50/AK3 privacy policy names drive.file, app folder and direct connection', () {
      final text = File(docs.first).readAsStringSync();
      expect(text, contains('`drive.file`'));
      expect(text, contains('nur Dateien, die die App selbst anlegt'));
      expect(text, contains('App-Ordner'));
      expect(text, contains('STUN-Server'));
      expect(text, contains('IP-Adresse'));
      expect(text, contains('keine Inhalte'));
    });
  });

  group('#50 site build', () {
    final python = hasPython;
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('wp_site'));
    tearDown(() => tmp.deleteSync(recursive: true));

    ProcessResult build(Map<String, String> secrets) => Process.runSync(
      'python3',
      ['-I', '../site/build_site.py', '${tmp.path}/out'],
      environment: secrets,
      includeParentEnvironment: false,
    );

    const secrets = {
      'CONTROLLER_NAME': 'Test Person',
      'CONTROLLER_ADDRESS': 'Teststrasse 1, 0000 Testort',
      'CONTACT_EMAIL': 'test@example.org',
    };

    test('#50/AK1 builds start page, both texts and the W0 page', () {
      if (!needs(
        pythonRequired,
        available: python,
        reason: 'python3 not installed',
      )) {
        return;
      }
      final r = build(secrets);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final out = '${tmp.path}/out';
      for (final page in [
        'index.html',
        'datenschutz.html',
        'nutzungsbedingungen.html',
        'w0/index.html',
      ]) {
        expect(File('$out/$page').existsSync(), isTrue, reason: page);
      }
      final index = File('$out/index.html').readAsStringSync();
      expect(index, contains('href="datenschutz.html"'));
      expect(index, contains('href="nutzungsbedingungen.html"'));
      expect(index, contains(repositoryUrl));
      final privacy = File('$out/datenschutz.html').readAsStringSync();
      expect(privacy, contains('Test Person'));
      expect(privacy, contains('test@example.org'));
      expect(privacy, isNot(contains('{{')));
    });

    test('#50/AK3 build fails when a secret is missing', () {
      if (!needs(
        pythonRequired,
        available: python,
        reason: 'python3 not installed',
      )) {
        return;
      }
      final r = build({...secrets}..remove('CONTACT_EMAIL'));
      expect(r.exitCode, isNot(0));
      expect('${r.stderr}', contains('CONTACT_EMAIL'));
      expect(File('${tmp.path}/out/datenschutz.html').existsSync(), isFalse);
    });
  });

  group('#50 About dialog', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('wp_about'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<TestApp> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = TestApp(Directory('${tmp.path}/lib'));
      await tester.runAsync(app.library.load);
      await tester.pumpWidget(
        WoodshedApp(controller: app.controller, locale: testLocale),
      );
      await tester.pumpAndSettle();
      return app;
    }

    test('#50/AK6 app version matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version:\s*([^+\s]+)',
        multiLine: true,
      ).firstMatch(pubspec)![1];
      expect(appVersion, version);
    });

    testWidgets('#50/AK6 About shows version, licence and both links', (
      tester,
    ) async {
      final app = await pump(tester);
      await tester.tap(find.byKey(const Key('aboutButton')));
      await tester.pumpAndSettle();
      expect(find.text(de.aboutVersion(appVersion)), findsOneWidget);
      expect(find.text(de.aboutLicense), findsOneWidget);
      expect(find.text(de.privacyPolicy), findsOneWidget);
      expect(find.text(de.termsOfUse), findsOneWidget);

      await tester.tap(find.byKey(const Key('aboutPrivacy')));
      await tester.tap(find.byKey(const Key('aboutTerms')));
      await tester.pump();
      expect(app.files.opened, [privacyUrl, termsUrl]);
    });

    testWidgets('#50/AK6 macOS app menu opens About with a localized title', (
      tester,
    ) async {
      final app = await pump(tester);
      expect(app.files.aboutMenuTitle, de.aboutApp);
      app.files.showAbout!();
      await tester.pumpAndSettle();
      expect(find.byType(AboutDialog), findsOneWidget);
    });

    test('#50/AK6 build info: empty values mean unknown', () {
      final none = BuildInfo.parse('', '');
      expect(none.tag, isNull);
      expect(none.date, isNull);
      final some = BuildInfo.parse('v1.2.0', '2026-11-19');
      expect(some.tag, 'v1.2.0');
      expect(some.date, DateTime(2026, 11, 19));
    });

    testWidgets('#50/AK6 About shows Git tag and build date', (tester) async {
      final app = await pump(tester);
      app.files.build = BuildInfo.parse('v1.2.0', '2026-11-19');
      await tester.tap(find.byKey(const Key('aboutButton')));
      await tester.pumpAndSettle();
      expect(find.text(de.aboutTag('v1.2.0')), findsOneWidget);
      expect(find.text('Gebaut am 19.11.2026'), findsOneWidget);
    });

    testWidgets('#50/AK6 About without tag says so and hides an unknown date', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('aboutButton')));
      await tester.pumpAndSettle();
      expect(find.text(de.aboutNoTag), findsOneWidget);
      expect(find.byKey(const Key('aboutBuildDate')), findsNothing);
    });

    test('#50/AK6 links point to the published pages', () {
      expect(
        privacyUrl,
        'https://ingen63.github.io/Woodshed-Player/datenschutz.html',
      );
      expect(
        termsUrl,
        'https://ingen63.github.io/Woodshed-Player/nutzungsbedingungen.html',
      );
    });
  });
}
