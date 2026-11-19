// #13/AK7: the pseudo language of the UI tests (integration_test/pseudo.dart) and its generated
// localization (tool/pseudo_l10n.dart): every English text is covered, marked and lengthened.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/l10n/app_localizations_en.dart';

import '../integration_test/pseudo.dart';
import '../integration_test/pseudo_localizations.dart';
import '../tool/pseudo_l10n.dart';

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), '');

void main() {
  test('#13/AK7 pseudo() marks, accents and lengthens by 40 %', () {
    // «Library»: 7 letters, 7 · 0.4 = 2.8 → 3 padding dots
    expect(pseudo('Library'), '⟦Ļîƀŕáŕý···⟧');
    expect(pseudo('OK'), '⟦ÖĶ·⟧'); // 2 · 0.4 = 0.8 → 1
    expect(pseudo('1:05 – 2×'), startsWith('⟦1:05 – 2×'));
    expect(pseudo(''), '⟦⟧');
  });

  test('#13/AK7 the generated pseudo localization is up to date', () {
    final english = File(englishFile).readAsStringSync();
    expect(
      _squash(File(outputFile).readAsStringSync()),
      _squash(generate(english)),
      reason: 'run: cd app && dart run tool/pseudo_l10n.dart',
    );
  });

  test('#13/AK7 every English text appears in the pseudo language', () {
    final members = englishMembers(File(englishFile).readAsStringSync());
    // gen-l10n writes one member per ARB key (app_en.arb, without @ entries).
    final arbKeys = RegExp(r'^  "([a-zA-Z]\w*)":', multiLine: true)
        .allMatches(File('lib/l10n/app_en.arb').readAsStringSync())
        .map((m) => m.group(1))
        .toSet();
    expect(members.map((m) => m.$1).toSet(), arbKeys);
    final en = AppLocalizationsEn(), p = PseudoLocalizations();
    expect(p.library, pseudo(en.library));
    expect(p.deleteNamedTitle('X'), pseudo(en.deleteNamedTitle('X')));
    expect(p.loopPass('2', '5'), pseudo(en.loopPass('2', '5')));
  });

  testWidgets('#13/AK7 cutTexts finds cut texts, not whole ones', (
    tester,
  ) async {
    Widget box(double width, Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    );
    final long = pseudo('Set start here');
    await tester.pumpWidget(box(2000, Text(long)));
    expect(pseudoTexts(tester), 1);
    expect(cutTexts(tester), isEmpty);
    await tester.pumpWidget(box(2000, const Text('no marks')));
    expect(pseudoTexts(tester), 0);
    for (final cut in [
      Text(long, maxLines: 1, overflow: TextOverflow.ellipsis),
      Text(long, softWrap: false, overflow: TextOverflow.clip),
      Text(pseudo('Metronome')), // one word, wider than 40 px
    ]) {
      await tester.pumpWidget(box(40, cut));
      expect(cutTexts(tester), hasLength(1), reason: '$cut');
    }
  });
}
