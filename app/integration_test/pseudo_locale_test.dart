// #13/AK7: the app in the pseudo language (pseudo.dart: every text marked and 40 % longer) in every
// size, with a loaded track: no layout overflows (Flutter reports it as an error, which fails the
// test) and no text of the app is cut off (ellipsis, too few lines, a word wider than its box).
// All other UI tests fix the language to English.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:woodshed_player/app/app_controller.dart';

import 'pseudo.dart';
import 'pseudo_localizations.dart';
import 'ui_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('#13/AK7 pseudo language: nothing cut off or overflowing', (
    tester,
  ) async {
    final t = testFolder(seconds: 3);
    final c = await startApp(
      tester,
      t.dir,
      l10n: const PseudoLocalizationsDelegate(),
    );
    expect(find.textContaining(pseudoStart), findsWidgets);
    // #115: the start shows the area Player with the empty library, fewer texts than the practice screen
    expect(pseudoTexts(tester), greaterThan(5));
    await dropFiles(tester, c, [t.wav]);
    c.player.setLoopStart(0.5);
    c.player.setLoopEnd(2.0);

    for (final (name, size) in [
      ('desktop', desktopSize),
      ('tablet', tabletSize),
      ('phone', phoneSize),
    ]) {
      setSize(tester, size);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$name: overflow');
      expect(cutTexts(tester), isEmpty, reason: '$name: library');
      if (name == 'phone') {
        await tester.tap(find.byKey(const Key('openPlayer')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'phone player');
        expect(cutTexts(tester), isEmpty, reason: 'phone player');
      }
      // #115: the areas Practice and Metronome (with the track in the mini bar), then back to Player
      for (final a in [AppArea.practice, AppArea.metronome, AppArea.player]) {
        await showArea(tester, a);
        expect(tester.takeException(), isNull, reason: '$name ${a.name}');
        expect(cutTexts(tester), isEmpty, reason: '$name ${a.name}');
      }
      if (name == 'phone') {
        await tester.tap(find.byKey(const Key('backToLibrary')));
        await tester.pumpAndSettle();
      }
    }
  });
}
