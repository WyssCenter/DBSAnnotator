import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/prefs/user_prefs.dart' show debugPrefsDir;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_test_helpers.dart';

/// A BIDS folder with patient 01's two visits from the fixture, and patient
/// 02, who has no visit and no indication.
void _useFolder() {
  final prefs = Directory.systemTemp.createTempSync('dbs_prefs');
  final bids = Directory.systemTemp.createTempSync('dbs_bids');
  final source = Directory('test/fixtures/bids');
  for (final f in source.listSync(recursive: true).whereType<File>()) {
    final to = File('${bids.path}/${f.path.substring(source.path.length + 1)}');
    to.parent.createSync(recursive: true);
    f.copySync(to.path);
  }
  File('${bids.path}/participants.tsv').writeAsStringSync(
    'participant_id\tdbs_indication\n'
    'sub-01\tObsessive-compulsive disorder\n'
    'sub-02\t\n',
  );
  File('${prefs.path}/dbs_user_prefs.json').writeAsStringSync(
    jsonEncode({
      'bids_folders': [
        {'name': 'Cohort', 'path': bids.path},
      ],
    }),
  );
  debugPrefsDir = prefs;
  addTearDown(() {
    debugPrefsDir = null;
    removeQuietly(prefs);
    removeQuietly(bids);
  });
}

Future<void> _open(WidgetTester tester) async {
  useTempDirs();
  _useFolder();
  await pumpScreen(tester, sessionScreen());
  await awaitRecoveryCheck(tester);
  await pumpUntilFound(tester, find.text('Patient'));
}

/// Chooses [entry] in the Patient list and lets the folder be read, which
/// needs the real event loop.
Future<void> _pick(WidgetTester tester, String entry) async {
  final list = find.widgetWithText(DropdownMenu<String>, 'Patient').first;
  await tester.ensureVisible(list);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(list);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(entry).last);
  for (var round = 0; round < 20; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Starts the visit and waits for Indication and devices.
Future<void> _start(WidgetTester tester) async {
  await tapNew(tester);
  await pumpUntilFound(tester, find.text('Same lead on both sides'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a patient with visits shows the last one, and fills the next', (
    tester,
  ) async {
    await _open(tester);
    await _pick(tester, '01');
    await pumpUntilFound(tester, find.text('Open last visit'));
    expect(find.text('Patient 01, 2 visits'), findsOneWidget);
    expect(find.textContaining('Latest visit'), findsOneWidget);

    await _start(tester);
    expect(find.textContaining('Filled from patient 01'), findsOneWidget);
    expect(find.text('Obsessive-compulsive disorder'), findsWidgets);
  });

  testWidgets('a patient without visits keeps nothing of the one before', (
    tester,
  ) async {
    await _open(tester);
    await _pick(tester, '01');
    await _pick(tester, '02');
    await _start(tester);
    expect(find.textContaining('Filled from'), findsNothing);
    expect(find.text('Obsessive-compulsive disorder'), findsNothing);
  });

  testWidgets('a new ID typed after a pick keeps nothing of that patient', (
    tester,
  ) async {
    await _open(tester);
    await _pick(tester, '01');
    await tester.enterText(find.widgetWithText(TextField, 'Patient ID'), '03');
    await tester.pump();
    await _start(tester);
    expect(find.textContaining('Filled from'), findsNothing);
    expect(find.text('Obsessive-compulsive disorder'), findsNothing);
  });

  testWidgets('New patient leaves the patient chosen', (tester) async {
    await _open(tester);
    await _pick(tester, '01');
    await pumpUntilFound(tester, find.text('Open last visit'));
    await _pick(tester, 'New patient');
    expect(find.text('Open last visit'), findsNothing);
    expect(find.text('Choose a patient to see their visits.'), findsOneWidget);
    final id = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Patient ID'),
    );
    expect(id.controller!.text, isEmpty);
  });
}
