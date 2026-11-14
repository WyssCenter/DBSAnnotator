import 'package:flutter_test/flutter_test.dart';

import 'video_harness.dart';
import 'visit.dart';

enum _Line {
  leaveOn(
    'Next asks which configuration the patient leaves on. The one marked as '
    'the final settings is chosen already; Not noted is also possible.',
  ),
  summary(
    'Finish summarises the session: how many configurations were tested, '
    'and the final settings as their values.',
  ),
  reports(
    'Reports for the patient record come out as PDF or Word, on A4 or US '
    'Letter.',
  ),
  research('For research, the BIDS folder is exported as a zip.'),
  close('Close ends the session. Everything is already saved.');

  const _Line(this.text);
  final String text;
}

Future<void> _say(WidgetTester tester, _Line line) => say(tester, line.text);

void main() {
  initVideoBinding();

  testWidgets('the Finish step', (tester) async {
    final model = await lead();
    await prepareScript(_Line.values.map((l) => l.text));
    final study = await openApp(tester);
    await startPatient(tester);
    await chooseIndication(tester);
    await chooseDevices(tester);
    await next(tester);
    await arrivalContacts(tester, model);
    await next(tester);
    await configuration(tester, 0);
    await configuration(tester, 1, finalSettings: true);
    await configuration(tester, 2);
    await rolling(tester);

    await _say(tester, _Line.leaveOn);
    await next(tester);
    await point(tester, find.text('Not noted'));
    await tapText(tester, 'Confirm');
    await pause(tester, 1000);

    await _say(tester, _Line.summary);
    await point(tester, find.textContaining('Configurations tested'));
    await point(tester, find.textContaining('Final settings:'));
    await _say(tester, _Line.reports);
    await point(tester, find.text('Report (PDF)').last);
    await point(tester, find.text('Report (Word)').last);
    await point(tester, find.text('Page size').last);
    await _say(tester, _Line.research);
    await point(tester, find.text('BIDS folder (zip)').last);
    await _say(tester, _Line.close);
    await point(tester, find.text('Close').last);
    await endVideo(tester);
    study.deleteSync(recursive: true);
  });
}
