import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_harness.dart';
import 'visit.dart';

enum _Line {
  change(
    'Programming starts from the settings on arrival. Change one thing at a '
    'time: here the amplitude, to 6 milliamps on each side.',
  ),
  scales(
    'The plus button adds or removes session scales, from any indication. '
    'Here Energy is removed, and Rumination added from the depression list.',
  ),
  rate(
    'Rate each symptom and side effect on its bar. It turns greener as the '
    'rating nears its best value; the cross leaves a rating out.',
  ),
  save('Note how the patient responds, and press Save configuration.'),
  star(
    'At 7 milliamps the patient is better. This configuration is starred, '
    'and marked as the final settings.',
  ),
  more('At 8 milliamps, side effects appear.'),
  edit(
    'In the table, Edit opens a saved configuration again, and Save changes '
    'writes it back.',
  ),
  delete(
    'The menu beside it deletes a configuration. The later ones move up a '
    'number, as in the saved file.',
  );

  const _Line(this.text);
  final String text;
}

Future<void> _say(WidgetTester tester, _Line line) => say(tester, line.text);

void main() {
  initVideoBinding();

  testWidgets('the Programming step', (tester) async {
    final model = await lead();
    await prepareScript(_Line.values.map((l) => l.text));
    final study = await openApp(tester);
    await startPatient(tester);
    await chooseIndication(tester);
    await chooseDevices(tester);
    await next(tester);
    await clinicalScores(tester);
    await arrivalContacts(tester, model);
    await next(tester);
    await rolling(tester);

    final c = configurations.first;
    await _say(tester, _Line.change);
    await amplitude(tester, c.mA);
    await _say(tester, _Line.scales);
    await tap(tester, find.byTooltip('Add ratings'));
    await tapText(tester, 'Scales for OCD');
    await tap(tester, find.text('Energy').last);
    await tapText(tester, 'Scales for MDD');
    await tap(tester, find.text('Rumination').last);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pause(tester, 300);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pause(tester, 1000);

    await _say(tester, _Line.rate);
    await rate(tester, c.ratings);
    await _say(tester, _Line.save);
    await typeInto(tester, 'Notes', c.note);
    await tapText(tester, 'Save configuration');

    await _say(tester, _Line.star);
    await configuration(tester, 1, finalSettings: true);
    await _say(tester, _Line.more);
    await configuration(tester, 2);

    await center(tester, find.text('All configurations'));
    await _say(tester, _Line.edit);
    await tap(tester, find.text('Edit').last);
    await typeInto(tester, 'Notes', 'Restless and talkative, laughs easily.');
    await tapText(tester, 'Save changes');

    await center(tester, find.text('All configurations'));
    await _say(tester, _Line.delete);
    await tap(tester, find.byTooltip('More for configuration #1'));
    await tap(tester, find.text('Delete configuration #1…'));
    await tapText(tester, 'Delete');
    await center(tester, find.text('All configurations'));
    await pause(tester, 3000);
    await endVideo(tester);
    study.deleteSync(recursive: true);
  });
}
