import 'package:flutter_test/flutter_test.dart';

import 'video_harness.dart';
import 'visit.dart';

/// What the video says, in order: its captions and its voice. Each line is
/// said before the actions it describes.
enum _Line {
  patient(
    'A whole visit, start to end. In Session, type the patient ID and press '
    'Next: the session starts in the chosen BIDS folder.',
  ),
  indication(
    'Choose the DBS indication, here OCD, the anatomical target, the lead '
    'model and the IPG.',
  ),
  clinical(
    'The initial assessment documents how the patient arrives: the clinical '
    'scales, the medications and a note.',
  ),
  stimulation(
    'Then the stimulation on arrival: 130 hertz, 5 milliamps, 90 '
    'microseconds on each side. Tap a contact twice for a cathode, and the '
    'case once for the anode.',
  ),
  programming(
    'In Programming, raise the amplitude to 6 milliamps, rate the symptoms '
    'and side effects, note how the patient responds, and save.',
  ),
  better(
    'At 7 milliamps the patient is better: the configuration is starred and '
    'marked as the final settings.',
  ),
  more('At 8 milliamps, side effects appear.'),
  charts(
    'The charts follow every rating across the configurations, and the '
    'table lists them all.',
  ),
  finish(
    'Next confirms the configuration the patient leaves on. Finish makes the '
    'reports and the BIDS export.',
  );

  const _Line(this.text);
  final String text;
}

Future<void> _say(WidgetTester tester, _Line line) => say(tester, line.text);

void main() {
  initVideoBinding();

  testWidgets('annotating a session', (tester) async {
    final model = await lead();
    await prepareScript(_Line.values.map((l) => l.text));
    final study = await openApp(tester);
    await rolling(tester);

    await _say(tester, _Line.patient);
    await startPatient(tester);

    await _say(tester, _Line.indication);
    await chooseIndication(tester);
    await chooseDevices(tester);
    await next(tester);

    await _say(tester, _Line.clinical);
    await clinicalScores(tester);
    await arrivalNotes(tester);
    await _say(tester, _Line.stimulation);
    await point(tester, find.text('Amplitude').first);
    await arrivalContacts(tester, model);
    await next(tester);

    await _say(tester, _Line.programming);
    await configuration(tester, 0);
    await _say(tester, _Line.better);
    await configuration(tester, 1, finalSettings: true);
    await _say(tester, _Line.more);
    await configuration(tester, 2);

    await center(tester, find.textContaining('Configurations tested'));
    await _say(tester, _Line.charts);
    await center(tester, find.text('All configurations'));
    await pause(tester, 2000);

    await _say(tester, _Line.finish);
    await next(tester);
    await tapText(tester, 'Confirm');
    await pause(tester, 3000);
    await endVideo(tester);
    study.deleteSync(recursive: true);
  });
}
