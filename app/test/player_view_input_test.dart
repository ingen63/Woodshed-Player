// Eingaben der Oberfläche (#19): Zeitfeld und Wiedergabeleiste.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/ui/player_view.dart';

void main() {
  testWidgets('#19/AK9 Zeitfeld: ungültige Eingabe wird verworfen', (
    tester,
  ) async {
    final commits = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimeField(
            key: const Key('tf'),
            value: 83,
            onCommit: commits.add,
          ),
        ),
      ),
    );
    expect(find.text('01:23'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tf')), 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(commits, isEmpty);

    await tester.enterText(find.byKey(const Key('tf')), '1:75');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(commits, isEmpty);
  });

  testWidgets('#19/AK6 Wiedergabeleiste: Tippen springt proportional', (
    tester,
  ) async {
    final seeks = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: ProgressScrubber(
                position: 0,
                duration: 100,
                onSeek: seeks.add,
              ),
            ),
          ),
        ),
      ),
    );
    final box = tester.getTopLeft(find.byType(ProgressScrubber));
    await tester.tapAt(box + const Offset(100, 12));
    expect(seeks.single, closeTo(25, 0.5));
  });
}
