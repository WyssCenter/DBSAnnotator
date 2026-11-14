import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_harness.dart';
import 'visit.dart';

enum _Line {
  folder(
    'Every visit is saved into a BIDS folder, chosen at the top of the '
    'Session step. The button beside it adds another folder.',
  ),
  patient(
    'This patient is already in the folder, so pick them from the list. '
    'Their indication, target and devices come from the last visit.',
  ),
  visit('The visit is dated today, unless you type another label.'),
  naming(
    'Research file naming sets the rest of the file name. Here the task is '
    'renamed, and the file name below follows.',
  ),
  start(
    'Next starts the session. The next step shows what was filled in from '
    'the last visit, to check.',
  );

  const _Line(this.text);
  final String text;
}

Future<void> _say(WidgetTester tester, _Line line) => say(tester, line.text);

/// A BIDS folder that already holds patient 02, with one OCD visit.
void _seed(Directory study) {
  for (final f in ['dataset_description.json', 'README']) {
    File('$videoRoot/test/fixtures/bids/$f').copySync('${study.path}/$f');
  }
  File('${study.path}/participants.tsv')
      .writeAsStringSync('participant_id\tdbs_indication\nsub-02\tOCD\n');
  Directory('${study.path}/sub-02').createSync();
  File('${study.path}/sub-02/sub-02_sessions.tsv').writeAsStringSync(
    'session_id\tacq_time\ttarget\tleft_electrode_model\t'
    'right_electrode_model\tleft_ipg_model\tright_ipg_model\n'
    'ses-20260610\t2026-06-10T09:00:00+00:00\tVC/VS\t$leadModel\t'
    '$leadModel\t$ipgModel\t$ipgModel\n',
  );
}

void main() {
  initVideoBinding();

  testWidgets('the Session step', (tester) async {
    await prepareScript(_Line.values.map((l) => l.text));
    final study = await openApp(tester, seed: _seed);
    await rolling(tester);

    await _say(tester, _Line.folder);
    await point(tester, find.text('BIDS folder'));
    await point(tester, find.byTooltip('Add a BIDS folder'));

    await _say(tester, _Line.patient);
    await pick(tester, 'Patient already in this folder', '02');

    await _say(tester, _Line.visit);
    await point(tester, find.widgetWithText(TextField, 'Visit'));

    await _say(tester, _Line.naming);
    await tapText(tester, 'Research file naming');
    await typeInto(tester, 'Task', 'titration');
    await point(tester, find.textContaining('File name:'));

    await _say(tester, _Line.start);
    await next(tester);
    await pause(tester, 3000);
    await endVideo(tester);
    study.deleteSync(recursive: true);
  });
}
