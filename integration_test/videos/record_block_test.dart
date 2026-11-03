import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/electrode/geometry.dart';
import 'package:dbs_annotator/core/electrode/stimulation_rule.dart';
import 'package:dbs_annotator/ui/electrode_view.dart';
import 'package:dbs_annotator/ui/home_screen.dart';
import 'package:dbs_annotator/ui/scale_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_harness.dart';

const _model = 'Medtronic SenSight B33005';

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

/// A stimulation preset chip on the [side]th parameters card.
Future<void> _preset(WidgetTester tester, String value, {int side = 0}) =>
    tap(tester, find.widgetWithText(ActionChip, value).at(side));

/// Rates every session scale at [fractions] of its bar.
Future<void> _rate(WidgetTester tester, List<double> fractions) async {
  final sliders = find.byType(ScaleSlider);
  for (var i = 0; i < sliders.evaluate().length; i++) {
    final bar = find
        .descendant(of: sliders.at(i), matching: find.byType(CustomPaint))
        .first;
    await center(tester, bar);
    final r = tester.getRect(bar);
    await tapAt(
      tester,
      Offset(r.left + r.width * fractions[i % fractions.length], r.center.dy),
    );
  }
}

void main() {
  initVideoBinding();

  testWidgets('recording a session', (tester) async {
    final model = (await loadElectrodeCatalog()).models[_model]!;
    await startVideo(tester, const HomeScreen());
    await tapText(tester, 'Complete workflow');
    await typeInto(tester, 'Patient ID', '01');
    await tapText(tester, 'Pathology');
    await tap(tester, find.text('OCD').last);
    await tapText(tester, 'New session');
    await tapText(tester, 'Loose TSV');

    // Stimulation first: presets on the left, typed on the right.
    await _preset(tester, '125');
    await _preset(tester, '3');
    await _preset(tester, '60');
    await typeInto(tester, 'Frequency', '130', at: 1);
    await typeInto(tester, 'Amplitude', '3.5', at: 1);
    await typeInto(tester, 'Pulse width', '60', at: 1);
    await _tapLead(tester, model, 0, (l) => _contact(l, 2, 1), taps: 2);
    await _tapLead(tester, model, 0, (l) => _contact(l, 2, 2), taps: 2);
    await _tapLead(tester, model, 0, (l) => l.caseRect.center);
    await _tapLead(tester, model, 1, (l) => _contact(l, 3, 0), taps: 2);
    await _tapLead(tester, model, 1, (l) => l.caseRect.center);

    // Then the clinical scores the pathology loaded.
    await typeInto(tester, 'Score', '28');
    await typeInto(tester, 'Score', '15', at: 1);
    await typeInto(tester, 'Notes', 'Baseline on admission settings.');
    await tapText(tester, 'Next');
    await pause(tester, 1500);

    // Three configurations, each changing one thing.
    await _preset(tester, '5');
    await _rate(tester, [0.6, 0.55, 0.5, 0.45, 0.4]);
    await typeInto(tester, 'Notes', 'Left raised to 5 mA.');
    await tapText(tester, 'Save configuration');
    await _preset(tester, '7');
    await _rate(tester, [0.35, 0.4, 0.3, 0.55, 0.5]);
    await typeInto(tester, 'Notes', 'Left raised to 7 mA, less checking.');
    await tapText(tester, 'Save configuration');
    await _preset(tester, '100');
    await _rate(tester, [0.2, 0.25, 0.25, 0.65, 0.6]);
    await typeInto(tester, 'Notes', 'Left frequency down to 100 Hz.');
    await tapText(tester, 'Save configuration');

    await center(tester, find.textContaining('Inserted entries'));
    await pause(tester, 2500);
    await center(tester, find.textContaining('Table of all entries'));
    await pause(tester, 2500);
    await endVideo(tester);
  });
}
