/// A TSV opened with columns the app does not keep is never written over:
/// detection, the save dialogs that must not end on it, and the screen.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/core/prefs/user_prefs.dart';
import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:dbs_annotator/core/session/tsv_kind.dart';
import 'package:dbs_annotator/core/tsv.dart';
import 'package:dbs_annotator/ui/save_target.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:dbs_annotator/ui/share_util.dart';
import 'package:dbs_annotator/ui/wizard_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_test_helpers.dart';

const _legacyFixture =
    'test/fixtures/legacy_0.4_sub-01_ses-20260203_task-programming_run-01_events.tsv';
const _currentFixture =
    'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv';

String _sessionHeader() => File(_currentFixture).readAsLinesSync().first;

List<String> _unkeptSession(String content) =>
    unkeptColumns(content, TsvKind.programming);

List<String> _unkeptNotes(String content) =>
    unkeptColumns(content, TsvKind.notes);

String _withExtraColumn(String content) {
  final rows = parseTsv(content);
  return writeTsv([
    [...rows.first, 'lab_flag'],
    for (final row in rows.skip(1)) [...row, 'x'],
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('unkeptColumns', () {
    test('names a column the app does not keep', () {
      expect(_unkeptSession('${_sessionHeader()}\tlab_flag\textra\n'), [
        'lab_flag',
        'extra',
      ]);
      expect(_unkeptNotes('acq_time\tnotes\tmood\n'), ['mood']);
    });

    test('a current-format and a 0.4 legacy file have none', () {
      expect(_unkeptSession(File(_currentFixture).readAsStringSync()), isEmpty);
      expect(_unkeptSession(File(_legacyFixture).readAsStringSync()), isEmpty);
      expect(_unkeptNotes('acq_time\tnotes\n'), isEmpty);
      expect(_unkeptNotes('date\ttime\ttimezone\tnotes\n'), isEmpty);
    });

    test('a byte order mark does not make the first column unkept', () {
      expect(
        _unkeptSession('\uFEFF${File(_currentFixture).readAsStringSync()}'),
        isEmpty,
      );
      expect(_unkeptNotes('\uFEFFacq_time\tnotes\n'), isEmpty);
    });

    test('an alias beside the column it stands in for is reported', () {
      expect(_unkeptSession('${_sessionHeader()}\tsession_id\n'), [
        'session_id',
      ]);
      expect(_unkeptSession('${_sessionHeader()}\tblock_ID\n'), ['block_ID']);
      expect(_unkeptSession('${_sessionHeader()}\telectrode_model\n'), [
        'electrode_model',
      ]);
      final legacyModels = _sessionHeader()
          .replaceAll('left_electrode_model\t', '')
          .replaceAll('right_electrode_model', 'electrode_model');
      expect(_unkeptSession('$legacyModels\n'), isEmpty);
    });

    test('the legacy time columns are kept only without acq_time', () {
      expect(_unkeptNotes('acq_time\tnotes\tdate\n'), ['date']);
      expect(_unkeptNotes('acq_time\tnotes\ttimezone\n'), ['timezone']);
      expect(_unkeptNotes('date\ttime\tnotes\n'), isEmpty);
    });

    test('only the alias readColumn reads is kept', () {
      final header = _sessionHeader();
      final first = header.replaceAll('append_id', 'session_id');
      final second = header.replaceAll('append_id', 'session_ID');
      expect(_unkeptSession('$first\tsession_ID\n'), ['session_ID']);
      expect(_unkeptSession('$second\tsession_id\n'), ['session_ID']);
    });

    test('legacy time cells that backfill are kept', () {
      const head = 'date\ttime\ttimezone\tnotes\n';
      expect(
        _unkeptNotes('${head}2026-02-03\t09:00:00\tUTC +00:00\tn\n'),
        isEmpty,
      );
      expect(_unkeptNotes('${head}2026-02-03\t\t\tn\n\t\t\tn\n'), isEmpty);
    });

    test('n/a cells are read as empty, as the reader does', () {
      const head = 'date\ttime\ttimezone\tnotes\n';
      expect(_unkeptNotes('${head}2026-02-03\tn/a\tn/a\tn\n'), isEmpty);
      expect(_unkeptNotes('${head}2026-02-03\t09:00:00\t n/a \tn\n'), isEmpty);
      expect(_unkeptNotes('acq_time\tnotes\t\n2026-02-03\tn\tn/a\n'), isEmpty);
    });

    test('a legacy date that does not backfill is reported', () {
      const head = 'date\ttime\ttimezone\tnotes\n';
      expect(_unkeptNotes('${head}03.02.2026\t09:00:00\t+01:00\tn\n'), [
        'date',
        'time',
        'timezone',
      ]);
      expect(_unkeptNotes('date\tnotes\n03.02.2026\tn\n'), ['date']);
    });

    test('a legacy timezone the conversion drops is reported', () {
      const head = 'date\ttime\ttimezone\tnotes\n';
      expect(_unkeptNotes('${head}2026-02-03\t09:00:00\tEurope/Zurich\tn\n'), [
        'timezone',
      ]);
    });

    test('a later row with a lost value is reported', () {
      const rows =
          'date\ttime\tnotes\n2026-02-03\t09:00:00\tn\nlater\t09:00:00\tn\n';
      expect(_unkeptNotes(rows), ['date', 'time']);
    });

    test('a legacy session alias is not kept in a notes file', () {
      expect(_unkeptNotes('acq_time\tnotes\tblock_ID\n'), ['block_ID']);
    });

    test('a value under an empty header name is reported', () {
      expect(_unkeptNotes('acq_time\tnotes\t\n2026\tn\tsecret\n'), [
        unnamedColumn,
      ]);
      expect(_unkeptNotes('acq_time\tnotes\t\n2026\tn\t\n'), isEmpty);
    });

    test('a repeated header name is reported', () {
      expect(_unkeptNotes('acq_time\tnotes\tnotes\n'), ['notes']);
    });

    test('a row with more cells than the header is reported', () {
      expect(_unkeptNotes('acq_time\tnotes\n2026\tn\textra\n'), [
        unnamedColumn,
      ]);
      expect(_unkeptNotes('acq_time\tnotes\n2026\tn\n\n'), isEmpty);
    });
  });

  group('exportFile with a file to avoid', () {
    late Directory dir;
    late File existing;
    late AvoidFile avoid;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('dbs_avoid_export');
      addTearDown(() {
        debugSaveDir = null;
        removeQuietly(dir);
      });
      existing = File('${dir.path}/a_beh.tsv')..writeAsStringSync('kept');
      existing.setLastModifiedSync(DateTime(2020));
      avoid = (path: existing.path, reason: 'Not over the opened file.');
    });

    Future<ExportOutcome> run(WidgetTester tester, {AvoidFile? avoid}) async {
      useExportCache(tester);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final outcome = await tester.runAsync(
        () => exportFile(
          context,
          filename: 'a_beh.tsv',
          avoid: avoid,
          build: () async => (bytes: 'exported'.codeUnits, warning: null),
        ),
      );
      await tester.pump();
      return outcome!;
    }

    testWidgets('the test seam refuses it and says why', (tester) async {
      debugSaveDir = dir;
      expect(await run(tester, avoid: avoid), ExportOutcome.notDelivered);
      expect(find.text('Not over the opened file.'), findsOneWidget);
      expect(existing.readAsStringSync(), 'kept');
    });

    testWidgets('the test seam saves to another name', (tester) async {
      debugSaveDir = dir;
      final other = (path: '${dir.path}/other.tsv', reason: 'x');
      expect(await run(tester, avoid: other), ExportOutcome.saved);
      expect(existing.readAsStringSync(), 'exported');
    });

    testWidgets('a desktop dialog choosing it leaves it as it was', (
      tester,
    ) async {
      useFakeFileSelector().savePath = existing.path;
      expect(await run(tester, avoid: avoid), ExportOutcome.notDelivered);
      expect(find.text('Not over the opened file.'), findsOneWidget);
      expect(existing.readAsStringSync(), 'kept');
      expect(existing.lastModifiedSync(), DateTime(2020));
    });

    testWidgets('a desktop dialog choosing another file gets the export', (
      tester,
    ) async {
      final other = File('${dir.path}/b_beh.tsv');
      useFakeFileSelector().savePath = other.path;
      expect(await run(tester, avoid: avoid), ExportOutcome.saved);
      expect(other.readAsStringSync(), 'exported');
      expect(existing.readAsStringSync(), 'kept');
      expect(existing.lastModifiedSync(), DateTime(2020));
    });

    testWidgets('a desktop dialog that is cancelled writes nothing', (
      tester,
    ) async {
      useFakeFileSelector();
      expect(await run(tester, avoid: avoid), ExportOutcome.notDelivered);
      expect(find.text('Not saved: a_beh.tsv'), findsOneWidget);
      expect(dir.listSync(), hasLength(1));
    });
  });

  group('the session screen', () {
    late Directory working;
    late Directory saved;
    late File original;
    late Uint8List before;
    late FakePicker picker;

    Future<void> openIt(WidgetTester tester) async {
      final dirs = useTempDirs();
      working = dirs.working;
      saved = dirs.saved;
      final name = BidsName(
        subject: '01',
        session: BidsName.sessionStamp(DateTime.now()),
        task: 'programming',
        run: '01',
      ).filename;
      original = File('${saved.path}/$name')
        ..writeAsStringSync(_withExtraColumn(sessionTsv()));
      original.setLastModifiedSync(DateTime(2020));
      before = original.readAsBytesSync();
      picker = useFakePicker()..file = pickedFile(original);
      await pumpScreen(tester, sessionScreen());
      await awaitRecoveryCheck(tester);
      await tester.tap(find.text('Open saved session'));
      await pumpUntilFound(
        tester,
        find.text(
          'Opened $name ($_summary). The app does not keep these '
          'columns: lab_flag. Your file is left unchanged. Export saves '
          'the session without them.',
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> toSetup(WidgetTester tester) async {
      final strip = find.byType(SessionStrip);
      if (strip.evaluate().isEmpty) return;
      await tester.tap(strip);
      await tester.pumpAndSettle();
    }

    testWidgets('Open never writes the file, however it is left', (
      tester,
    ) async {
      await openIt(tester);
      await _add(tester, working, 'after opening');
      expect(original.readAsBytesSync(), before);
      expect(workingText(working), contains('after opening'));

      await tester.binding.handlePopRoute();
      await pumpUntilFound(tester, find.text('Keep copy'));
      expect(find.text('Delete the only copy'), findsOneWidget);
      await tester.tap(find.text('Keep copy'));
      await pumpUntilGone(tester, find.byType(SessionScreen));
      expect(original.readAsBytesSync(), before);
    });

    testWidgets('New leaves the file and records into the BIDS folder', (
      tester,
    ) async {
      final bids = _useFolder();
      await openIt(tester);
      await toSetup(tester);
      await pumpUntilFound(tester, find.text(bids.path));
      await tester.tap(find.text('New session'));
      await pumpUntilFound(tester, find.textContaining('New session in '));
      await tester.pumpAndSettle();

      await _add(tester, working, 'after new');
      await settleUntil(
        tester,
        working,
        () => bids
            .listSync(recursive: true)
            .whereType<File>()
            .any((f) => f.readAsStringSync().contains('after new')),
      );
      expect(original.readAsBytesSync(), before);
    });

    testWidgets('Open of a normal file ends the mode', (tester) async {
      await openIt(tester);
      final normal = File('${saved.path}/sub-08_ses-20260204_task-t_beh.tsv')
        ..writeAsStringSync(sessionTsv());
      picker.file = pickedFile(normal);
      await toSetup(tester);
      await tester.tap(find.text('Open saved session'));
      await pumpUntilFound(
        tester,
        find.text('Opened ${pickedBasename(normal.path)} ($_summary).'),
      );
      await tester.pumpAndSettle();

      await _add(tester, working, 'into the normal file');
      await settleUntil(
        tester,
        working,
        () => normal.readAsStringSync().contains('into the normal file'),
      );
      expect(original.readAsBytesSync(), before);
    });
  });
}

const _summary = '1 rows, next block 1, append 2';

/// Saves user prefs naming a new empty folder as the only BIDS folder.
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

/// Saves a Programming configuration whose notes are [text] and waits until
/// the working copy holds it.
Future<void> _add(WidgetTester tester, Directory working, String text) async {
  if (find.text('Save configuration').evaluate().isEmpty) {
    await tester.tap(find.text('Programming'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.widgetWithText(TextField, 'Notes'), text);
  final save = find.text('Save configuration');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await settleUntil(tester, working, () => workingText(working).contains(text));
}
