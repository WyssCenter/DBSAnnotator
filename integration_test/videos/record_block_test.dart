import 'package:flutter_test/flutter_test.dart';

import 'video_harness.dart';
import 'visit.dart';

/// What the video says, in order: its captions and its voice. Each line
/// starts as the actions it describes begin.
enum _Line {
  patient(
    'A whole visit, start to end. In Session, type the patient ID and press '
    'New session: the visit is saved in the chosen BIDS folder.',
  ),
  indication(
    'Choose the DBS indication, here obsessive-compulsive disorder, the '
    'anatomical target, the lead, and the IPG with its position.',
  ),
  clinical(
    'The initial assessment documents how the patient arrives: the clinical '
    'scales, the medications, and how the past weeks went.',
  ),
  stimulation(
    'The stimulation on arrival comes from the defaults of the indication: '
    '130 hertz, 5 milliamps, 90 microseconds. Tap a contact twice for a '
    'cathode, and the case once for the anode.',
  ),
  first(
    'In Programming, each configuration is rated and saved. At 6 milliamps '
    'the patient is calmer, with warmth in the left arm.',
  ),
  fold(
    'The next changes are made on the Percept programmer, so the stimulation '
    'settings are folded away: its export fills them in at the end.',
  ),
  second('At 7 milliamps mood is lighter, but the warmth is stronger.'),
  steered(
    'Steering the right lead onto two segments takes the warmth away. This '
    'configuration is starred and kept as the final settings.',
  ),
  fill(
    'Finish asks which configuration the patient leaves on. With the '
    "programmer's export filed in the visit's folder, Fill from Percept "
    'export previews what the device delivered, and Fill writes it in.',
  ),
  report(
    'The session report, for the patient record: the visit, every '
    'configuration with its ratings, and the settings read from the device, '
    'marked as such.',
  ),
  research('For research, the visit is also exported as a BIDS folder.'),
  charts(
    'Back in Programming, the charts and the table show every configuration '
    'with the settings from the device.',
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
    final saved = [DateTime.now()];

    await _say(tester, _Line.first);
    await configuration(tester, 0);
    saved.add(DateTime.now());
    await _say(tester, _Line.fold);
    await tapText(tester, 'Stimulation settings');
    await _say(tester, _Line.second);
    await configuration(tester, 1);
    saved.add(DateTime.now());
    await _say(tester, _Line.steered);
    await configuration(tester, 2, finalSettings: true);
    saved.add(DateTime.now());
    filePerceptExport(study, saved);

    await _say(tester, _Line.fill);
    await next(tester);
    await tapText(tester, 'Confirm');
    await tapText(tester, 'Fill from Percept export');
    await pause(tester, 3000);
    await tapText(tester, 'Fill');
    await center(tester, find.text('Session summary'));
    await pause(tester, 1500);

    await _say(tester, _Line.report);
    await tapText(tester, 'Report (PDF)');
    await tapText(tester, 'Next');
    await tapText(tester, 'Export');
    await showSavedPdf(tester);
    await _say(tester, _Line.research);
    await point(tester, find.text('BIDS folder (zip)'));

    await _say(tester, _Line.charts);
    await tapText(tester, 'Back');
    await tapText(tester, 'Comparison charts');
    await pause(tester, 2000);
    await center(tester, find.text('All configurations'));
    await pause(tester, 2000);
    await endVideo(tester);
    study.deleteSync(recursive: true);
  });
}
