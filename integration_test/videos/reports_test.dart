import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'video_harness.dart';
import 'visit.dart';

/// What the video says, in order: its captions and its voice.
enum _Line {
  import(
    'Import, under Other sessions, reads the visits saved in the BIDS folder '
    'chosen above: here, two visits of the same patient.',
  ),
  report(
    'A report across visits can be exported as PDF or Word. Choose the '
    'sections it includes,',
  ),
  targets('and the scale targets that decide how configurations are ranked.'),
  export('Export saves the report.');

  const _Line(this.text);
  final String text;
}

Future<void> _say(WidgetTester tester, _Line line) => say(tester, line.text);

/// The example BIDS folder: the same two visits the docs show.
void _seed(Directory study) {
  final source = Directory('$videoRoot/test/fixtures/bids');
  for (final f in source.listSync(recursive: true).whereType<File>()) {
    final to = File(
      '${study.path}/${f.path.substring(source.path.length + 1)}',
    );
    to.parent.createSync(recursive: true);
    f.copySync(to.path);
  }
}

void main() {
  initVideoBinding();

  testWidgets('reports from imported sessions', (tester) async {
    await prepareScript(_Line.values.map((l) => l.text));
    await openApp(tester, seed: _seed);
    await rolling(tester);
    await _say(tester, _Line.import);
    await tapText(tester, 'Import');
    await tap(tester, find.text('Import').last);
    await pause(tester, 2000);
    await _say(tester, _Line.report);
    await tap(tester, find.text('PDF').at(1));
    await tapText(tester, 'Electrode configuration');
    await tapText(tester, 'Programming summary');
    await _say(tester, _Line.targets);
    await tapText(tester, 'Scale targets…');
    await pause(tester, 1500);
    await tap(tester, find.text('Cancel').last);
    await pause(tester, 1000);
    await _say(tester, _Line.export);
    await tap(tester, find.text('Export').last);
    await pause(tester, 2500);
    await endVideo(tester);
  });
}
