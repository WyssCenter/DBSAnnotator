import 'package:dbs_annotator/ui/amplitude_split.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_harness.dart';
import 'visit.dart';

enum _Line {
  scales(
    'The initial assessment documents how the patient arrives, before any '
    'change. The clinical scales for OCD are listed: enter each score.',
  ),
  addRemove('The plus button adds a scale; the minus beside one removes it.'),
  notes('Then the medications, and a note on how the patient presents.'),
  parameters(
    'The stimulation on arrival: 130 hertz, 5 milliamps and 90 microseconds '
    'on each side, the defaults for OCD.',
  ),
  contacts(
    'Tap a contact once for an anode, twice for a cathode. Here the case is '
    'the anode.',
  ),
  split(
    'With two cathodes on one lead, the current can be split between them. '
    'Here 60 percent goes to the first.',
  ),
  next('Next saves the initial assessment.');

  const _Line(this.text);
  final String text;
}

Future<void> _say(WidgetTester tester, _Line line) => say(tester, line.text);

void main() {
  initVideoBinding();

  testWidgets('the Initial assessment step', (tester) async {
    final model = await lead();
    await prepareScript(_Line.values.map((l) => l.text));
    final study = await openApp(tester);
    await startPatient(tester);
    await chooseIndication(tester);
    await chooseDevices(tester);
    await next(tester);
    await rolling(tester);

    await _say(tester, _Line.scales);
    await clinicalScores(tester);
    await _say(tester, _Line.addRemove);
    await point(tester, find.byTooltip('Add clinical scales'));
    await point(tester, find.byTooltip('Remove clinical scale').last);

    await _say(tester, _Line.notes);
    await arrivalNotes(tester);

    await _say(tester, _Line.parameters);
    for (final label in ['Frequency', 'Amplitude', 'Pulse width']) {
      await point(tester, find.widgetWithText(TextField, label));
    }

    await _say(tester, _Line.contacts);
    await tapContact(tester, model, 0, level: 1, taps: 2);
    await tapContact(tester, model, 0);
    await tapContact(tester, model, 1, level: 0, taps: 2);
    await tapContact(tester, model, 1);

    await _say(tester, _Line.split);
    await tapContact(tester, model, 0, level: 1, segment: 1, taps: 2);
    await typeIn(
      tester,
      find
          .descendant(
            of: find.byType(AmplitudeSplit),
            matching: find.byType(TextField),
          )
          .first,
      '60',
    );
    await pause(tester, 1500);

    await _say(tester, _Line.next);
    await next(tester);
    await pause(tester, 1500);
    await endVideo(tester);
    study.deleteSync(recursive: true);
  });
}
