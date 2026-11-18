// Screenshots des Designs «Studio» (#30) für README und Abnahme, mit erfundenen Titeln und erzeugter
// Wellenform (keine privaten Daten). Erzeugen:
//   cd app && flutter test tool/screenshots_test.dart --update-goldens
// Die Bilder landen in docs/screenshots/. Kein Teil der normalen Testläufe (liegt nicht unter test/).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/ui/home_page.dart';
import 'package:woodshed_player/ui/style.dart';

import '../test/fakes.dart';
import '../test/metadata_test.dart' show id3, text;

Future<void> _font(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    loader.addFont(
      p.startsWith('/') || p.startsWith('assets/')
          ? Future.value(ByteData.sublistView(File(p).readAsBytesSync()))
          : rootBundle.load(p),
    );
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _font(textFont, [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold'])
        'assets/fonts/inter/Inter-$w.ttf',
    ]);
    await _font(numberFont, [
      for (final w in ['Regular', 'Medium', 'Bold'])
        'assets/fonts/jetbrains-mono/JetBrainsMono-$w.ttf',
    ]);
    await _font('packages/cupertino_icons/CupertinoIcons', [
      'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    ]);
    await _font('MaterialIcons', ['fonts/MaterialIcons-Regular.otf']);
  });

  for (final (name, size) in [
    ('desktop', const Size(1280, 800)),
    ('tablet', const Size(820, 1180)),
    ('phone', const Size(390, 844)),
  ]) {
    for (final b in Brightness.values) {
      testWidgets('$name ${b.name}', (tester) async {
        debugDefaultTargetPlatformOverride = name == 'desktop'
            ? TargetPlatform.macOS
            : TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final dir = Directory.systemTemp.createTempSync('wp_shots');
        addTearDown(() => dir.deleteSync(recursive: true));
        final app = TestApp(Directory('${dir.path}/lib'), duration: 228);
        app.core.hasWaveform = true;
        await tester.runAsync(() async {
          await app.library.load();
          final src = Directory('${dir.path}/q')..createSync();
          final paths = <String>[];
          for (final (i, (t, a)) in [
            ('Blues in F', 'Übungsband'),
            ('Walzer Nr. 2', 'Übungsband'),
            ('Etüde in A-Moll', null),
            ('Arpeggio-Übung 14', null),
            ('Bossa in D', 'Testtrio'),
          ].indexed) {
            final f = File('${src.path}/$i.mp3')
              ..writeAsBytesSync(
                id3(3, [
                  ('TIT2', text(0, t)),
                  if (a != null) ('TPE1', text(0, a)),
                ]),
              );
            paths.add(f.path);
          }
          await app.library.importFiles(paths);
        });
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: woodshedTheme(b),
            home: HomePage(
              controller: app.controller,
              recordingButton: name == 'desktop'
                  ? Builder(
                      builder: (context) => BorderedButton(
                        label: 'Aufnahme',
                        icon: WsIcons.record,
                        onPressed: () {},
                      ),
                    )
                  : null,
            ),
          ),
        );
        await tester.pump();
        final t = app.library.tracks.firstWhere((t) => t.title == 'Blues in F');
        app.controller.select(t);
        app.finishLoads(228);
        final p = app.player;
        p.setSpeedEnabled(true);
        p.setRamp(enabled: true);
        p.setSpeed(0.75);
        p.setLoopStart(42);
        p.setLoopEnd(58.5);
        app.core.pos = 51.3;
        p.play();
        for (var i = 0; i < 7; i++) {
          app.core.passes++;
          app.tick();
        }
        KeyboardPresence.instance.value = name != 'phone';
        await tester.pumpAndSettle();
        if (name == 'phone') {
          await tester.tap(find.byKey(const Key('openPlayer')));
          await tester.pumpAndSettle();
        }
        await expectLater(
          find.byType(HomePage),
          matchesGoldenFile(
            '../../docs/screenshots/studio-$name-${b.name}.png',
          ),
        );
      });
    }
  }
}
