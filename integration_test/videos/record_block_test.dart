import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/electrode/geometry.dart';
import 'package:dbs_annotator/core/electrode/stimulation_rule.dart';
import 'package:dbs_annotator/core/prefs/user_prefs.dart';
import 'package:dbs_annotator/ui/electrode_view.dart';
import 'package:dbs_annotator/ui/scale_slider.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_harness.dart';

const _model = 'Medtronic SenSight B33005';

/// What the video says, in order: its captions and its voice.
enum _Line {
  start(
    'This is the Session step. Type the patient ID and press Next: the '
    'session starts, and is saved into the chosen BIDS folder.',
  ),
  indication(
    'In Indication and devices, choose the DBS indication. The target, '
    'the leads and the IPG are set here too.',
  ),
  stimulation(
    'The initial assessment documents how the patient arrives. Set the '
    'stimulation of each side, and tap the contacts on the lead: once for '
    'an anode, twice for a cathode.',
  ),
  scores(
    'Then the clinical scores, and a note on how the patient presents. Next '
    'saves the initial assessment.',
  ),
  programming(
    'In Programming, change one thing at a time, rate the symptoms and side '
    'effects, note how the patient responds, and press Save configuration.',
  ),
  more(
    'Each saved configuration is added to the charts and to the table '
    'below, where it can be starred, edited or deleted.',
  );

  const _Line(this.text);
  final String text;
}

Future<void> _say(WidgetTester tester, _Line line) => say(tester, line.text);

Future<void> _tapLead(
  WidgetTester tester,
  ElectrodeModel model,
  int lead,
  Offset Function(ElectrodeLayout) target, {
  int taps = 1,
}) async {
  final view = find.byType(ElectrodeView).at(lead);
  await center(tester, view);
  final origin = tester.getTopLeft(view);
  final layout = computeLayout(model, tester.getSize(view));
  for (var i = 0; i < taps; i++) {
    await tapAt(tester, origin + target(layout), fast: true);
  }
}

Offset _contact(ElectrodeLayout l, int level, int segment) => l.levels
    .firstWhere((e) => e.levelIdx == level)
    .contactRects[ContactKey(level, segment)]!
    .center;

/// Rates every session scale at [fractions] of its bar: the widest drawing in
/// each row, not the arrow buttons beside it.
Future<void> _rate(WidgetTester tester, List<double> fractions) async {
  final sliders = find.byType(ScaleSlider);
  for (var i = 0; i < sliders.evaluate().length; i++) {
    final paints = find.descendant(
      of: sliders.at(i),
      matching: find.byType(CustomPaint),
    );
    await center(tester, sliders.at(i));
    final r = [
      for (var j = 0; j < paints.evaluate().length; j++)
        tester.getRect(paints.at(j)),
    ].reduce((a, b) => a.width >= b.width ? a : b);
    await tapAt(
      tester,
      Offset(r.left + r.width * fractions[i % fractions.length], r.center.dy),
    );
  }
}

void main() {
  initVideoBinding();

  testWidgets('annotating a session', (tester) async {
    final model = (await loadElectrodeCatalog()).models[_model]!;
    final study = videoFolder('DBS study');
    await prepareScript(_Line.values.map((l) => l.text));
    await startVideo(
      tester,
      FutureBuilder<void>(
        future: Future(
          () => saveUserPrefs(
            UserPrefs(bidsFolders: [(name: 'DBS study', path: study.path)]),
          ),
        ),
        builder: (context, saved) =>
            saved.connectionState == ConnectionState.done
            ? const SessionScreen()
            : const SizedBox.shrink(),
      ),
    );
    await _say(tester, _Line.start);
    await typeInto(tester, 'Patient ID', '01');
    await tapText(tester, 'Next');

    await _say(tester, _Line.indication);
    await tapText(tester, 'DBS indication');
    await tap(tester, find.text('OCD').last);
    await tapText(tester, 'Next');

    await _say(tester, _Line.stimulation);
    await typeInto(tester, 'Amplitude', '3.5', at: 1);
    await _tapLead(tester, model, 0, (l) => _contact(l, 2, 1), taps: 2);
    await _tapLead(tester, model, 0, (l) => _contact(l, 2, 2), taps: 2);
    await _tapLead(tester, model, 0, (l) => l.caseRect.center);
    await _tapLead(tester, model, 1, (l) => _contact(l, 3, 0), taps: 2);
    await _tapLead(tester, model, 1, (l) => l.caseRect.center);

    await _say(tester, _Line.scores);
    await typeInto(tester, 'Score', '28');
    await typeInto(tester, 'Score', '15', at: 1);
    await typeInto(tester, 'Notes', 'Anxious, checks the door twice.');
    await tapText(tester, 'Next');
    await pause(tester, 1500);

    await _say(tester, _Line.programming);
    await typeInto(tester, 'Amplitude', '6');
    await _rate(tester, [0.6, 0.55, 0.5, 0.45, 0.4]);
    await typeInto(tester, 'Notes', 'Calmer; warmth in the left arm.');
    await tapText(tester, 'Save configuration');

    await _say(tester, _Line.more);
    await typeInto(tester, 'Amplitude', '7');
    await _rate(tester, [0.35, 0.4, 0.3, 0.55, 0.5]);
    await typeInto(tester, 'Notes', 'Smiles, mood lighter, no urge to check.');
    await tapText(tester, 'Save configuration');
    await typeInto(tester, 'Frequency', '100');
    await _rate(tester, [0.2, 0.25, 0.25, 0.65, 0.6]);
    await typeInto(tester, 'Notes', 'Mood flatter again, no side effects.');
    await tapText(tester, 'Save configuration');

    await center(tester, find.textContaining('Configurations tested'));
    await pause(tester, 2500);
    await center(tester, find.text('All configurations'));
    await pause(tester, 2500);
    await endVideo(tester);
    study.deleteSync(recursive: true);
  });
}
