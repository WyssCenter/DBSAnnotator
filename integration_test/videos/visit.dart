import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/electrode/geometry.dart';
import 'package:dbs_annotator/core/electrode/stimulation_rule.dart';
import 'package:dbs_annotator/core/prefs/user_prefs.dart';
import 'package:dbs_annotator/ui/electrode_view.dart';
import 'package:dbs_annotator/ui/scale_slider.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/percept_fixture.dart';
import 'video_harness.dart';

/// The visit the video shows: obsessive-compulsive disorder, VC/VS, a
/// SenSight lead on each side, 130 Hz and 90 µs, 5 mA on arrival.
const leadModel = 'Medtronic SenSight B33005';
const ipgModel = 'Medtronic Percept PC';

/// Opens the session screen on a fresh BIDS folder named 'DBS study'.
Future<Directory> openApp(WidgetTester tester) async {
  final study = videoFolder('DBS study');
  await startVideo(
    tester,
    FutureBuilder<void>(
      future: Future(
        () => saveUserPrefs(
          UserPrefs(bidsFolders: [(name: 'DBS study', path: study.path)]),
        ),
      ),
      builder: (context, saved) => saved.connectionState == ConnectionState.done
          ? const SessionScreen()
          : const SizedBox.shrink(),
    ),
  );
  return study;
}

Future<ElectrodeModel> lead() async =>
    (await loadElectrodeCatalog()).models[leadModel]!;

Future<void> pick(WidgetTester tester, String field, String option) async {
  await tapText(tester, field);
  await tap(tester, find.text(option).last);
}

/// Moves to the next step once the line being said is finished.
Future<void> next(WidgetTester tester) async {
  await quiet(tester);
  await tapText(tester, 'Next');
  await pause(tester, 1000);
}

Future<void> startPatient(WidgetTester tester) async {
  await typeInto(tester, 'Patient ID', '01');
  await point(tester, find.text('DBS study'));
  await quiet(tester);
  await tapText(tester, 'New session');
  await pause(tester, 1000);
}

Future<void> chooseIndication(WidgetTester tester) async {
  await pick(tester, 'DBS indication', 'Obsessive-compulsive disorder');
  await pick(tester, 'Anatomical target', 'VC/VS');
}

Future<void> chooseDevices(WidgetTester tester) async {
  await pick(tester, 'Lead model', leadModel);
  await pick(tester, 'IPG model', ipgModel);
  await pick(tester, 'Position', 'Left chest');
}

Future<void> clinicalScores(WidgetTester tester) async {
  for (final (i, score) in ['28', '14', '14', '18'].indexed) {
    await typeInto(tester, 'Score', score, at: i);
  }
}

Future<void> arrivalNotes(WidgetTester tester) async {
  await typeInto(tester, 'Medications', 'Fluoxetine 60 mg daily');
  await typeInto(
    tester,
    'Notes',
    'Past two weeks: more checking at home, poor sleep, low mood most days. '
        'Today anxious, checked the door twice on arrival.',
  );
}

/// Taps contact [level], [segment] of lead [side] (0 left, 1 right), or the
/// case when [level] is null.
Future<void> tapContact(
  WidgetTester tester,
  ElectrodeModel model,
  int side, {
  int? level,
  int segment = 0,
  int taps = 1,
}) async {
  final view = find.byType(ElectrodeView).at(side);
  await center(tester, view);
  final origin = tester.getTopLeft(view);
  final l = computeLayout(model, tester.getSize(view));
  final at = level == null
      ? l.caseRect.center
      : l.levels
            .firstWhere((e) => e.levelIdx == level)
            .contactRects[ContactKey(level, segment)]!
            .center;
  for (var i = 0; i < taps; i++) {
    await tapAt(tester, origin + at, fast: true);
  }
}

/// A cathode on the ventral contact of each lead, the case as the anode.
Future<void> arrivalContacts(WidgetTester tester, ElectrodeModel model) async {
  for (final side in [0, 1]) {
    await tapContact(tester, model, side, level: 0, taps: 2);
    await tapContact(tester, model, side);
  }
}

/// Sets the amplitude of both sides to [mA].
Future<void> amplitude(WidgetTester tester, String mA) async {
  await typeInto(tester, 'Amplitude', mA);
  await typeInto(tester, 'Amplitude', mA, at: 1);
}

/// Rates every session scale at [fractions] of its bar: the widest drawing in
/// each row, not the arrow buttons beside it.
Future<void> rate(WidgetTester tester, List<double> fractions) async {
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
      fast: true,
    );
  }
}

/// The configurations of Programming, rated as Obsessions, Compulsions,
/// Anxiety, Mood and Energy. Only the first is typed in; the others are set
/// on the programmer and filled from its export at Finish.
const configurations = [
  (
    mA: '6',
    ratings: [0.6, 0.55, 0.5, 0.45, 0.5],
    note: 'Calmer; warmth in the left arm.',
  ),
  (
    mA: null,
    ratings: [0.4, 0.4, 0.35, 0.6, 0.6],
    note: '7 mA: mood lighter, less urge to check; warmth stronger.',
  ),
  (
    mA: null,
    ratings: [0.3, 0.3, 0.3, 0.7, 0.7],
    note: 'Right lead steered to E1a and E1b: warmth gone, calm.',
  ),
];

Future<void> configuration(
  WidgetTester tester,
  int i, {
  bool finalSettings = false,
}) async {
  final c = configurations[i];
  if (c.mA case final mA?) await amplitude(tester, mA);
  await rate(tester, c.ratings);
  await typeInto(tester, 'Notes', c.note);
  if (finalSettings) {
    await tapText(tester, 'Star this configuration');
    await tapText(tester, 'Final settings (patient goes home on this)');
  }
  await tapText(tester, 'Save configuration');
}

/// Files a synthetic Percept export of the visit in its `ieeg/` folder: 5 mA
/// on E0 of both leads, then 6 and 7 mA, then the right lead steered onto E1a
/// and E1b at 7 mA, each held around one of [saved], the times the initial
/// assessment and the three configurations were saved.
void filePerceptExport(Directory study, List<DateTime> saved) {
  final changes = [
    for (var i = 1; i < saved.length; i++)
      saved[i - 1].add(saved[i].difference(saved[i - 1]) ~/ 2),
  ];
  final start = saved.first.subtract(const Duration(seconds: 30));
  final end = saved.last.add(const Duration(seconds: 20));
  int at(DateTime t) => t.difference(start).inSeconds;
  final e0 = snapshotSide(
    rate: 130,
    electrodes: monopolar([('SenSight_00', null)]),
  );
  final steered = snapshotSide(
    rate: 130,
    electrodes: monopolar([('SenSight_1a', 32), ('SenSight_1b', 32)]),
  );
  final export = perceptJson(
    start: start,
    end: end,
    segments: [
      segment(
        start,
        [(0, 5, 5), (at(changes[0]), 6, 6), (at(changes[1]), 7, 7)],
        endSeconds: at(changes[2]),
        left: e0,
        right: e0,
      ),
      segment(
        changes[2],
        [(0, 7, 7)],
        endSeconds: end.difference(changes[2]).inSeconds,
        left: e0,
        right: steered,
      ),
    ],
  );
  final session = Directory('${study.path}/sub-01')
      .listSync()
      .whereType<Directory>()
      .single;
  final ieeg = Directory('${session.path}/ieeg')..createSync();
  File('${ieeg.path}/Report_Json_Session_Report.json')
      .writeAsStringSync(jsonEncode(export));
}
