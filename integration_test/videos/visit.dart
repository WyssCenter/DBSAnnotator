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

import 'video_harness.dart';

/// The OCD visit every session video shows: VC/VS, a SenSight lead on each
/// side, 130 Hz and 90 µs, amplitude raised from 5 to 8 mA.
const leadModel = 'Medtronic SenSight B33005';
const ipgModel = 'Medtronic Percept PC';

/// Opens the session screen on a fresh BIDS folder named 'DBS study'.
Future<Directory> openApp(
  WidgetTester tester, {
  void Function(Directory)? seed,
}) async {
  final study = videoFolder('DBS study');
  seed?.call(study);
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

Future<void> next(WidgetTester tester) async {
  await tapText(tester, 'Next');
  await pause(tester, 1000);
}

Future<void> startPatient(WidgetTester tester) async {
  await typeInto(tester, 'Patient ID', '01');
  await next(tester);
}

Future<void> chooseIndication(WidgetTester tester) async {
  await pick(tester, 'DBS indication', 'OCD');
  await pick(tester, 'Anatomical target', 'VC/VS');
}

Future<void> chooseDevices(WidgetTester tester) async {
  await pick(tester, 'Lead model', leadModel);
  await pick(tester, 'IPG model', ipgModel);
}

Future<void> clinicalScores(WidgetTester tester) async {
  for (final (i, score) in ['28', '14', '14', '18'].indexed) {
    await typeInto(tester, 'Score', score, at: i);
  }
}

Future<void> arrivalNotes(WidgetTester tester) async {
  await typeInto(tester, 'Medications', 'Fluoxetine 60 mg daily');
  await typeInto(tester, 'Notes', 'Anxious, checks the door twice.');
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

/// The three configurations after the first: 6, 7 (starred, final) and 8 mA.
const configurations = [
  (
    mA: '6',
    ratings: [0.6, 0.55, 0.5, 0.45, 0.4],
    note: 'Calmer; warmth in the left arm.',
  ),
  (
    mA: '7',
    ratings: [0.35, 0.4, 0.3, 0.3, 0.35],
    note: 'Smiles, mood lighter, no urge to check.',
  ),
  (
    mA: '8',
    ratings: [0.3, 0.3, 0.45, 0.65, 0.6],
    note: 'Restless, talks fast, laughs easily.',
  ),
];

Future<void> configuration(
  WidgetTester tester,
  int i, {
  bool finalSettings = false,
}) async {
  final c = configurations[i];
  await amplitude(tester, c.mA);
  await rate(tester, c.ratings);
  await typeInto(tester, 'Notes', c.note);
  if (finalSettings) {
    await tapText(tester, 'Star this configuration');
    await tapText(tester, 'Final settings (patient goes home on this)');
  }
  await tapText(tester, 'Save configuration');
}
