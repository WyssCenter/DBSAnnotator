import 'package:flutter_test/flutter_test.dart';

import 'video_harness.dart';
import 'visit.dart';

enum _Line {
  indication(
    'Indication and devices. The DBS indication sets which clinical and '
    'session scales are offered later. Here, OCD.',
  ),
  target(
    'Then the anatomical target. The button beside each list edits its '
    'choices.',
  ),
  lead(
    'The lead model is drawn to scale in the next steps. When the two leads '
    'differ, untick Same lead on both sides.',
  ),
  ipg('The implanted pulse generator, or IPG, is chosen the same way.'),
  settings(
    'Devices settings adds manufacturers, leads and IPGs, and the design of '
    'each lead.',
  ),
  next('Next goes on to the initial assessment.');

  const _Line(this.text);
  final String text;
}

Future<void> _say(WidgetTester tester, _Line line) => say(tester, line.text);

void main() {
  initVideoBinding();

  testWidgets('the Indication and devices step', (tester) async {
    await prepareScript(_Line.values.map((l) => l.text));
    final study = await openApp(tester);
    await startPatient(tester);
    await rolling(tester);

    await _say(tester, _Line.indication);
    await pick(tester, 'DBS indication', 'OCD');
    await _say(tester, _Line.target);
    await pick(tester, 'Anatomical target', 'VC/VS');
    await point(tester, find.byTooltip('Edit targets'));

    await _say(tester, _Line.lead);
    await pick(tester, 'Lead model', leadModel);
    await point(tester, find.text('Same lead on both sides'));
    await _say(tester, _Line.ipg);
    await pick(tester, 'IPG model', ipgModel);

    await _say(tester, _Line.settings);
    await tap(tester, find.byTooltip('Devices settings'));
    await pause(tester, 3000);
    await tapText(tester, 'Cancel');

    await _say(tester, _Line.next);
    await next(tester);
    await pause(tester, 2000);
    await endVideo(tester);
    study.deleteSync(recursive: true);
  });
}
