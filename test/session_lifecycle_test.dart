/// The session screen's file lifecycle: leaving, New, Open and Export against
/// real files, pinning the texts and files a clinician gets.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/prefs/user_prefs.dart';
import 'package:dbs_annotator/core/safe_file.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/bids_session.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:dbs_annotator/ui/wizard_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_test_helpers.dart';

const _guardTitle = 'Keep a recovery copy of this session?';
const _newSnack = 'New session in Cohort.';

/// Saves user prefs naming a new empty folder as the only BIDS folder,
/// `Cohort`, and returns that folder.
Directory _useFolder() {
  final prefs = Directory.systemTemp.createTempSync('dbs_prefs');
  final bids = Directory.systemTemp.createTempSync('dbs_bids');
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
  return bids;
}

List<File> _behIn(Directory bids) => bids
    .listSync(recursive: true)
    .whereType<File>()
    .where(
      (f) => f.path.endsWith('_beh.tsv') && !f.path.contains('derivatives'),
    )
    .toList();

/// The screen with a session already open and no file behind it, so the
/// recovery copy is the only copy.
Future<(Directory, Directory, Directory)> _show(WidgetTester tester) async {
  final dirs = useTempDirs();
  final bids = _useFolder();
  await pumpScreen(
    tester,
    SessionScreen(
      catalog: sessionScreen().catalog,
      limits: sessionScreen().limits,
      scalePresets: sessionScreen().scalePresets,
      authoring: SessionAuthoring(),
    ),
  );
  await awaitRecoveryCheck(tester);
  await pumpUntilFound(tester, find.text(bids.path));
  return (dirs.working, dirs.saved, bids);
}

/// The screen with nothing open, a visit of patient 01 started into the BIDS
/// folder with New.
Future<(Directory, Directory)> _showNew(WidgetTester tester) async {
  final dirs = useTempDirs();
  final bids = _useFolder();
  await pumpScreen(tester, sessionScreen());
  await awaitRecoveryCheck(tester);
  await pumpUntilFound(tester, find.text(bids.path));
  await tester.enterText(find.widgetWithText(TextField, 'Patient ID'), '01');
  await tapNew(tester);
  await pumpUntilFound(tester, find.textContaining(_newSnack));
  await tester.pumpAndSettle();
  return (dirs.working, bids);
}

Future<void> _toSetup(WidgetTester tester) async {
  final strip = find.byType(SessionStrip);
  if (strip.evaluate().isEmpty) return;
  await tester.tap(strip);
  await tester.pumpAndSettle();
}

/// Presses New session on Setup with patient 01, confirming an earlier run of
/// the same visit.
Future<void> _pressNew(WidgetTester tester) async {
  await _toSetup(tester);
  await tester.enterText(find.widgetWithText(TextField, 'Patient ID'), '01');
  await tapNew(tester);
  await pumpUntilFound(
    tester,
    find.byWidgetPredicate(
      (w) => w is Text && (w.data == 'Continue' || w.data == _guardTitle),
    ),
  );
  if (find.text('Continue').evaluate().isNotEmpty) {
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }
}

/// Types [text] as the notes of a Programming configuration and saves it.
Future<void> _save(WidgetTester tester, String text) async {
  if (find.text('Save configuration').evaluate().isEmpty) {
    await tester.tap(find.text('Programming'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.widgetWithText(TextField, 'Notes'), text);
  final save = find.text('Save configuration');
  await tester.ensureVisible(save);
  await tester.tap(save);
}

/// [_save], then waits until the working copy holds [text].
Future<void> _add(WidgetTester tester, Directory working, String text) async {
  await _save(tester, text);
  await settleUntil(
    tester,
    working,
    () => workingText(working).contains(text),
    cap: const Duration(seconds: 40),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final guard = find.text(_guardTitle);

  group('leaving', () {
    testWidgets('with only the working copy says it is the only copy', (
      tester,
    ) async {
      final (working, _, _) = await _show(tester);
      await _add(tester, working, 'first visit');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(guard, findsOneWidget);
      expect(
        find.textContaining(
          'Changes in this session are not saved anywhere else unless you '
          'exported or shared them. Discarding deletes this copy.',
        ),
        findsOneWidget,
      );
      expect(find.text('Delete the only copy'), findsOneWidget);
      expect(find.text('Keep copy'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Delete the only copy leaves and removes the working copy', (
      tester,
    ) async {
      final (working, _, _) = await _show(tester);
      await _add(tester, working, 'first visit');
      final copy = Directory('${working.path}/work')
          .listSync()
          .whereType<File>()
          .single;

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete the only copy'));
      await pumpUntilGone(tester, find.byType(SessionScreen));

      expect(find.byType(SessionScreen), findsNothing);
      expect(copy.existsSync(), isFalse);
    });

    testWidgets('Keep copy leaves and keeps the working copy', (tester) async {
      final (working, _, _) = await _show(tester);
      await _add(tester, working, 'first visit');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep copy'));
      await tester.pumpAndSettle();

      expect(find.byType(SessionScreen), findsNothing);
      expect(workingText(working), contains('first visit'));
    });
  });

  group('New', () {
    testWidgets('Next with a patient ID starts the visit, as New does', (
      tester,
    ) async {
      useTempDirs();
      final bids = _useFolder();
      await pumpScreen(tester, sessionScreen());
      await awaitRecoveryCheck(tester);
      await pumpUntilFound(tester, find.text(bids.path));
      await tester.enterText(
        find.widgetWithText(TextField, 'Patient ID'),
        '01',
      );
      await tester.tap(find.text('Next'));
      await pumpUntilFound(tester, find.textContaining(_newSnack));
      await tester.pumpAndSettle();

      expect(find.text('Same lead on both sides'), findsOneWidget);
      expect(find.text('Patient ID'), findsNothing);
      expect(Directory('${bids.path}/derivatives/sub-01').existsSync(), isTrue);
    });

    testWidgets('after an entry asks, and Delete the only copy replaces it', (
      tester,
    ) async {
      final (working, _, bids) = await _show(tester);
      await _add(tester, working, 'first visit');
      final oldCopy = Directory('${working.path}/work')
          .listSync()
          .whereType<File>()
          .single;

      await _pressNew(tester);
      await tester.pumpAndSettle();
      expect(find.text('Delete the only copy'), findsOneWidget);
      await tester.tap(find.text('Delete the only copy'));
      await pumpUntilFound(tester, find.textContaining(_newSnack));
      await settleUntil(tester, working, () => !oldCopy.existsSync());

      expect(oldCopy.existsSync(), isFalse);
      expect(workingText(working), isNot(contains('first visit')));
      expect(_behIn(bids), isEmpty);

      await _add(tester, working, 'second visit');
      await settleUntil(tester, working, () => _behIn(bids).isNotEmpty);
      final created = _behIn(bids).single;
      await settleUntil(
        tester,
        working,
        () => created.readAsStringSync().contains('second visit'),
      );
      final text = created.readAsStringSync();
      expect(text, isNot(contains('first visit')));
      expect({
        for (final r in parseAnySessionTsv(text)) r.blockId,
      }, hasLength(1));
    });

    testWidgets('Cancel keeps the entries and creates nothing', (tester) async {
      final (working, _, bids) = await _show(tester);
      await _add(tester, working, 'first visit');

      await _pressNew(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await awaitRecoveryCheck(tester);

      expect(find.textContaining(_newSnack), findsNothing);
      expect(bids.listSync(recursive: true), isEmpty);
      expect(workingText(working), contains('first visit'));
    });

    testWidgets('for the same visit takes the next run and leaves the first', (
      tester,
    ) async {
      final (working, bids) = await _showNew(tester);
      await _add(tester, working, 'first visit');
      await settleUntil(tester, working, () => _behIn(bids).isNotEmpty);
      final first = _behIn(bids).single;
      expect(first.path, endsWith('_run-01_beh.tsv'));
      await settleUntil(
        tester,
        working,
        () => first.readAsStringSync().contains('first visit'),
      );
      await awaitRecoveryCheck(tester);

      await _pressNew(tester);
      await pumpUntilFound(tester, guard);
      await tester.pumpAndSettle();
      expect(find.text('Discard copy'), findsOneWidget);
      await tester.tap(find.text('Keep copy'));
      await pumpUntilFound(tester, find.textContaining('run 02'));
      await tester.pumpAndSettle();

      await _add(tester, working, 'second visit');
      await settleUntil(tester, working, () => _behIn(bids).length == 2);
      final second = _behIn(bids).singleWhere((f) => f.path != first.path);
      expect(second.path, endsWith('_run-02_beh.tsv'));
      await settleUntil(
        tester,
        working,
        () => second.readAsStringSync().contains('second visit'),
      );
      expect(first.readAsStringSync(), contains('first visit'));
      expect(first.readAsStringSync(), isNot(contains('second visit')));
    });

    testWidgets('is refused while a save is running, and nothing is lost', (
      tester,
    ) async {
      final (working, bids) = await _showNew(tester);
      await _add(tester, working, 'first entry');
      await settleUntil(tester, working, () => _behIn(bids).isNotEmpty);
      final file = _behIn(bids).single;
      await settleUntil(
        tester,
        working,
        () => file.readAsStringSync().contains('first entry'),
      );
      await awaitRecoveryCheck(tester);

      final gate = Completer<void>();
      debugWriteGate = gate.future;
      addTearDown(() => debugWriteGate = null);
      await _save(tester, 'held');
      await tester.pump();

      await _pressNew(tester);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'A save is still running, so the latest changes may not be on disk '
          'yet.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Keep copy'));
      await tester.pumpAndSettle();
      final refused = find.text(
        'A save is still running. Try again in a moment.',
      );
      for (var i = 0; i < 6 && refused.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      }

      expect(refused, findsOneWidget);
      expect(_behIn(bids), hasLength(1));

      gate.complete();
      await settleUntil(
        tester,
        working,
        () => file.readAsStringSync().contains('held'),
        step: const Duration(milliseconds: 100),
      );
      final text = file.readAsStringSync();
      expect(text, contains('first entry'));
      expect(text.indexOf('first entry'), lessThan(text.indexOf('held')));
    });
  });

  group('Open', () {
    testWidgets('a file naming an unknown electrode model says so after '
        'Opened', (tester) async {
      final dirs = useTempDirs();
      final file = File('${dirs.saved.path}/sub-08_ses-20260204_task-x_beh.tsv')
        ..writeAsStringSync(sessionTsv(model: 'Unknown Lead 9'));
      useFakePicker().file = pickedFile(file);
      await pumpScreen(tester, sessionScreen());
      await awaitRecoveryCheck(tester);

      await tester.tap(find.text('Open saved session'));
      await pumpUntilFound(tester, find.textContaining('Opened '));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text(
          'Opened sub-08_ses-20260204_task-x_beh.tsv (0 configurations tested '
          'so far).',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('not in the catalogue'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This file names an electrode model, "Unknown Lead 9", that is not '
          'in the catalogue. The diagrams show Medtronic SenSight B33005 '
          'instead.',
        ),
        findsOneWidget,
      );
    });
  });

  group('recovery', () {
    testWidgets('a copy naming an unknown electrode model says so after '
        'Reopened', (tester) async {
      final dirs = useTempDirs();
      plantWork(
        dirs.working,
        'sub-07_ses-20260203_task-tuning_run-03_beh.tsv',
        sessionTsv(model: 'Unknown Lead 9'),
      );
      await pumpScreen(tester, sessionScreen());
      await pumpUntilFound(tester, find.text('Unfinished session found'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reopen'));
      await pumpUntilFound(tester, find.textContaining('Reopened '));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('not in the catalogue'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This file names an electrode model, "Unknown Lead 9", that is not '
          'in the catalogue. The diagrams show Medtronic SenSight B33005 '
          'instead.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Export', () {
    testWidgets('lifts the warning until the next entry', (tester) async {
      final cache = useExportCache(tester);
      final (working, saved, _) = await _show(tester);
      await _add(tester, working, 'first visit');

      await tester.tap(find.text('Session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BIDS folder (zip)').first);
      await settleUntil(
        tester,
        working,
        () =>
            saved.listSync().whereType<File>().isNotEmpty &&
            !cache
                .listSync(recursive: true)
                .any((e) => e is Directory && e.path.contains('export-')),
      );
      expect(saved.listSync().whereType<File>().single.path, endsWith('.zip'));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('not saved anywhere else'), findsNothing);
      expect(guard, findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await _add(tester, working, 'second visit');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('not saved anywhere else'), findsOneWidget);
      expect(find.text('Delete the only copy'), findsOneWidget);
    });
  });
}
