/// The combined table of a BIDS folder is refreshed once, when a visit
/// recorded into it ends, and a problem doing so is shown without stopping the
/// user leaving.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/core/bids_dataset.dart';
import 'package:dbs_annotator/core/bids_merge.dart';
import 'package:dbs_annotator/core/bids_sidecar.dart';
import 'package:dbs_annotator/core/prefs/user_prefs.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/ui/bids_export.dart';
import 'package:dbs_annotator/ui/bids_merge_ui.dart';
import 'package:dbs_annotator/ui/close_guard.dart';
import 'package:dbs_annotator/ui/recording_file.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:dbs_annotator/ui/wizard_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_test_helpers.dart';

const _tablePath = '$aggregateDerivativeDir/$aggregateStem.tsv';
const _progress = 'Updating the combined table';
const _failure = 'Could not update the combined table under';
const _later =
    'The next merge from Reports or the next visit recorded into this '
    'dataset will refresh it.';
const _newSnack = 'New session in Cohort.';

const _visit = BidsName(
  subject: '01',
  session: '20260203',
  task: 'programming',
  run: '01',
);

late Map<String, dynamic> _contract;

Future<Object?> _fileVisit(Directory root, BidsName name, String notes) =>
    fileIntoDataset(
      root: root.path,
      entry: sessionEntry(
        name: name,
        rows:
            (SessionAuthoring()..addInsert(
                  isInitial: false,
                  stim: const {'left_stim_freq': '130'},
                  notes: notes,
                  at: DateTime.utc(2026, 2, 3, 9),
                ))
                .rows,
        contract: _contract,
      ),
    );

Map<String, String> _snapshot(Directory root) => {
  for (final f in root.listSync(recursive: true).whereType<File>())
    f.path: String.fromCharCodes(f.readAsBytesSync()),
};

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => screen),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _untilAcknowledge(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (find.text('Combined table').evaluate().isEmpty) {
    if (!DateTime.now().isBefore(end)) fail('no acknowledge dialog appeared');
    final keep = find.text('Keep copy');
    if (keep.evaluate().isNotEmpty) await tester.tap(keep);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void _useFolder(Directory dataset) {
  final dir = Directory.systemTemp.createTempSync('dbs_prefs');
  File('${dir.path}/dbs_user_prefs.json').writeAsStringSync(
    jsonEncode({
      'bids_folders': [
        {'name': 'Cohort', 'path': dataset.path},
      ],
    }),
  );
  debugPrefsDir = dir;
  addTearDown(() {
    debugPrefsDir = null;
    removeQuietly(dir);
  });
}

Future<void> _toSetup(WidgetTester tester) async {
  final strip = find.byType(SessionStrip);
  if (strip.evaluate().isEmpty) return;
  await tester.tap(strip);
  await tester.pumpAndSettle();
}

Future<void> _add(WidgetTester tester, Directory working, String text) async {
  await _toProgramming(tester);
  await _type(tester, text);
  await settleUntil(
    tester,
    working,
    () => workingText(working).contains(text),
    cap: const Duration(seconds: 40),
  );
}

Future<void> _toProgramming(WidgetTester tester) async {
  if (find.text('Save configuration').evaluate().isNotEmpty) return;
  await tester.tap(find.text('Programming'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.widgetWithText(TextField, 'Notes'), text);
  final save = find.text('Save configuration');
  await tester.ensureVisible(save);
  await tester.tap(save);
}

Future<void> _pressNew(WidgetTester tester) async {
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .clearSnackBars();
  await _toSetup(tester);
  await tester.tap(find.text('New session'));
  await pumpUntilFound(
    tester,
    find.byWidgetPredicate(
      (w) => w is Text && (w.data == 'Continue' || w.data == 'Keep copy'),
    ),
  );
  if (find.text('Continue').evaluate().isNotEmpty) {
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }
}

Future<void> _pressOpen(
  WidgetTester tester,
  FakePicker picker,
  File file,
) async {
  picker.file = pickedFile(file);
  await _toSetup(tester);
  await tester.tap(find.text('Open saved session'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => _contract = await loadTsvContract());

  group('refreshDatasetAggregate', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('dbs_refresh_unit');
    });
    tearDown(() => removeQuietly(root));

    test('builds the table once and a second call changes nothing', () async {
      await _fileVisit(root, _visit, 'first visit');

      final first = await refreshDatasetAggregate(root.path);
      expect(first.notice, isNull);
      final table = File('${root.path}/$_tablePath');
      expect(table.readAsStringSync(), contains('first visit'));
      final after = _snapshot(root);

      final second = await refreshDatasetAggregate(root.path);

      expect(second.notice, isNull);
      expect(_snapshot(root), after);
      expect(after.keys.where((p) => p.contains('.bak-')), isEmpty);
    });

    test('replaces a stale table, keeping the old one and hiding it', () async {
      await _fileVisit(root, _visit, 'first visit');
      File('${root.path}/$_tablePath')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('stale');

      await refreshDatasetAggregate(root.path);

      final dir = Directory('${root.path}/$aggregateDerivativeDir');
      final backups = dir.listSync().whereType<File>().where(
        (f) => f.path.contains('.bak-'),
      );
      expect(backups.single.readAsStringSync(), 'stale');
      expect(
        File('${root.path}/$_tablePath').readAsStringSync(),
        contains('first visit'),
      );
      expect(
        File('${root.path}/.bidsignore').readAsStringSync(),
        contains(kBackupIgnoreLine),
      );
    });

    test('never writes raw data and reads only what the table needs', () async {
      await _fileVisit(root, _visit, 'first visit');
      File('${root.path}/sourcedata/notes.tsv')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([0xff, 0xfe, 0x00]);
      File('${root.path}/sub-01/ses-20260203/anat/sub-01_T1w.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{}');
      final raw = {
        for (final e in _snapshot(root).entries)
          if (!e.key.contains('derivatives')) e.key: e.value,
      };

      final read = await readDatasetDirectory(
        root.path,
        only: (path) => path.contains('_beh.'),
      );
      expect(read.map((f) => f.path), everyElement(contains('_beh.')));
      expect(read, isNotEmpty);

      await refreshDatasetAggregate(root.path);

      final now = _snapshot(root);
      expect({
        for (final e in now.entries)
          if (!e.key.contains('derivatives')) e.key: e.value,
      }, raw);
    });

    test('decodes only the recorded files, sidecars and the table', () async {
      await _fileVisit(root, _visit, 'first visit');
      File('${root.path}/sourcedata/notes.tsv')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(List.filled(2 * 1024 * 1024, 0xff));
      File('${root.path}/sub-01/ses-20260203/anat/sub-01_T1w.json')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{}');
      File('${root.path}/README.md').writeAsStringSync('about');
      final read = <String>[];
      debugDatasetRead = read.add;
      addTearDown(() => debugDatasetRead = null);

      await refreshDatasetAggregate(root.path);

      expect(read, contains(contains('_beh.tsv')));
      expect(read, contains(contains('_beh.json')));
      expect(read.where((p) => p.contains('sourcedata')), isEmpty);
      expect(read.where((p) => p.contains('anat')), isEmpty);
      expect(read, isNot(contains('README.md')));
    });

    test('writers into one dataset run one after the other', () async {
      final gate = Completer<void>();
      final events = <String>[];
      final first = inDatasetQueue(() async {
        events.add('first start');
        await gate.future;
        events.add('first end');
      });
      final second = inDatasetQueue(() async => events.add('second start'));
      final refresh = _fileVisit(root, _visit, 'queued');
      final refreshed = refresh.then((_) => events.add('filed'));

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(events, ['first start']);
      expect(
        Directory(root.path).listSync(recursive: true).whereType<File>(),
        isEmpty,
      );

      gate.complete();
      await Future.wait([first, second, refreshed]);

      expect(events, ['first start', 'first end', 'second start', 'filed']);
      await expectDatasetQueueIdle();
    });

    test('every public writer waits for a held queue job', () async {
      await _fileVisit(root, _visit, 'first visit');
      final existing = await readDatasetDirectory(root.path);
      const other = BidsName(
        subject: '02',
        session: '20260203',
        task: 'programming',
        run: '01',
      );
      final writers = <String, Future<Object?> Function()>{
        'refreshDatasetAggregate': () => refreshDatasetAggregate(root.path),
        'applyMergeToDirectory': () =>
            applyMergeToDirectory(root.path, planBidsMerge(existing, const [])),
        'writeAggregateInto': () =>
            writeAggregateInto(root.path, tsv: 'table', sidecar: '{}'),
        'fileIntoDataset': () => _fileVisit(root, other, 'planted visit'),
      };
      final gate = Completer<void>();
      final held = inDatasetQueue(() => gate.future);
      final finished = <String>[];
      final runs = [
        for (final w in writers.entries)
          w.value().then((_) => finished.add(w.key)),
      ];

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(finished, isEmpty);
      expect(datasetQueueIdle, isFalse);

      gate.complete();
      await held;
      await Future.wait(runs);

      expect(finished, unorderedEquals(writers.keys));
      await expectDatasetQueueIdle();
    });

    test('a failed writer does not stop the next one', () async {
      final failing = inDatasetQueue<void>(() async => throw StateError('x'));
      await expectLater(failing, throwsStateError);

      expect(await inDatasetQueue(() async => 7), 7);
      await expectDatasetQueueIdle();
    });

    test('names a recorded file it cannot include and says why', () async {
      await _fileVisit(root, _visit, 'first visit');
      const broken =
          'sub-02/ses-20260203/beh/sub-02_ses-20260203_task-programming_'
          'run-01_beh.tsv';
      File('${root.path}/$broken')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('not a table');
      File(
          '${root.path}/sub-03/ses-1/beh/sub-03_ses-1_task-stroop_run-01_beh.tsv',
        )
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('another lab');

      final result = await refreshDatasetAggregate(root.path);

      expect(result.leftOut.map((f) => f.path), [broken]);
      expect(result.notice, contains(broken));
      expect(result.notice, isNot(contains('stroop')));
      expect(
        File('${root.path}/$_tablePath').readAsStringSync(),
        contains('first visit'),
      );
    });
  });

  group('the session screen', () {
    late Directory working;
    late Directory saved;
    late Directory dataset;
    late FakePicker picker;

    File table() => File('${dataset.path}/$_tablePath');
    String tableText() =>
        table().existsSync() ? table().readAsStringSync() : '';

    void plant(String text) => table()
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);

    File looseFile() =>
        File('${saved.path}/sub-09_ses-20260204_task-tuning_run-01_beh.tsv')
          ..writeAsStringSync(sessionTsv(notes: 'opened entry'));

    Future<void> startVisit(WidgetTester tester) async {
      final dirs = useTempDirs();
      working = dirs.working;
      saved = dirs.saved;
      dataset = Directory.systemTemp.createTempSync('dbs_refresh_ds');
      addTearDown(() {
        debugRefreshHold = null;
        refreshTimeLimit = const Duration(seconds: 60);
        removeQuietly(dataset);
      });
      _useFolder(dataset);
      picker = useFakePicker();
      await _pumpScreen(tester, sessionScreen());
      await awaitRecoveryCheck(tester);
      await pumpUntilFound(tester, find.text(dataset.path));
      await tester.enterText(
        find.widgetWithText(TextField, 'Patient ID'),
        '01',
      );
      await tester.tap(find.text('New session'));
      await pumpUntilFound(tester, find.textContaining(_newSnack));
      await tester.pumpAndSettle();
    }

    Future<void> startFiledVisit(WidgetTester tester) async {
      await startVisit(tester);
      await _add(tester, working, 'first entry');
      await _add(tester, working, 'last entry');
      await settleUntil(
        tester,
        working,
        () => dataset
            .listSync(recursive: true)
            .whereType<File>()
            .any((f) => f.readAsStringSync().contains('last entry')),
      );
    }

    Future<void> keepCopy(WidgetTester tester) async {
      await pumpUntilFound(tester, find.text('Keep copy'));
      await tester.tap(find.text('Keep copy'));
    }

    Future<void> leave(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await keepCopy(tester);
    }

    void breakDerivatives() {
      final derivatives = Directory('${dataset.path}/derivatives');
      if (derivatives.existsSync()) derivatives.deleteSync(recursive: true);
      File(derivatives.path).writeAsStringSync('in the way');
    }

    Finder screen() => find.byType(SessionScreen);

    testWidgets('leaving refreshes the table to include the last entry', (
      tester,
    ) async {
      await startFiledVisit(tester);
      plant('stale');

      await leave(tester);
      await pumpUntilGone(tester, screen());

      expect(tableText(), contains('first entry'));
      expect(tableText(), contains('last entry'));
      expect(
        Directory('${dataset.path}/$aggregateDerivativeDir')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('.bak-')),
        hasLength(1),
      );
      expect(find.text(_progress), findsNothing);
    });

    testWidgets('New refreshes the table before the visit is replaced', (
      tester,
    ) async {
      await startFiledVisit(tester);
      plant('stale');

      await _pressNew(tester);
      await keepCopy(tester);
      await pumpUntilFound(tester, find.textContaining(_newSnack));

      expect(tableText(), contains('last entry'));
    });

    testWidgets('Open refreshes the table before the visit is replaced', (
      tester,
    ) async {
      await startFiledVisit(tester);
      plant('stale');

      await _pressOpen(tester, picker, looseFile());
      await keepCopy(tester);
      await pumpUntilFound(tester, find.textContaining('Opened '));

      expect(tableText(), contains('last entry'));
      expect(tableText(), isNot(contains('opened entry')));
    });

    testWidgets('a file opened outside any BIDS folder refreshes nothing', (
      tester,
    ) async {
      await startFiledVisit(tester);
      await _pressOpen(tester, picker, looseFile());
      await keepCopy(tester);
      await pumpUntilFound(tester, find.textContaining('Opened '));
      await tester.pumpAndSettle();
      plant('sentinel');

      var started = 0;
      debugRefreshHold = () async => started++;

      await _add(tester, working, 'loose entry');
      await leave(tester);
      await pumpUntilGone(tester, screen());

      expect(started, 0);
      expect(tableText(), 'sentinel');
      expect(find.textContaining('combined table'), findsNothing);
    });

    testWidgets('a visit with nothing filed refreshes nothing', (tester) async {
      await startVisit(tester);
      plant('sentinel');
      var started = 0;
      debugRefreshHold = () async => started++;

      await tester.binding.handlePopRoute();
      await pumpUntilGone(tester, screen());

      expect(started, 0);
      expect(tableText(), 'sentinel');
      expect(find.textContaining('combined table'), findsNothing);
    });

    testWidgets('first entry still being filed on leave says so', (
      tester,
    ) async {
      await startVisit(tester);
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      unawaited(inDatasetQueue(() => gate.future));
      var started = 0;
      debugRefreshHold = () async => started++;
      await _add(tester, working, 'first entry');

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 11));
      await tester.pump();
      await tester.tap(find.text('Keep copy'));
      await tester.pump();
      await tester.pump();

      await pumpUntilFound(
        tester,
        find.text(
          'A save was still running, so the combined table under '
          '$aggregateDerivativeDir/ was not updated. $_later',
        ),
      );
      await pumpUntilGone(tester, screen());
      expect(started, 0);

      gate.complete();
      await tester.pump();
      await drainDatasetQueue(tester);
    });

    testWidgets('a save still running skips the refresh and says so', (
      tester,
    ) async {
      await startVisit(tester);
      await _add(tester, working, 'first entry');
      await pumpUntilFound(tester, find.textContaining('Saved as '));
      plant('sentinel');
      await _type(tester, 'unsettled entry');

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 11));
      await tester.pump();
      await tester.tap(find.text('Keep copy'));
      await tester.pump();
      await tester.pump();

      await pumpUntilFound(
        tester,
        find.text(
          'A save was still running, so the combined table under '
          '$aggregateDerivativeDir/ was not updated. $_later',
        ),
      );
      await pumpUntilGone(tester, screen());
      expect(tableText(), 'sentinel');
    });

    testWidgets('a failed refresh is shown and leaving still works', (
      tester,
    ) async {
      await startFiledVisit(tester);
      breakDerivatives();

      await leave(tester);
      await pumpUntilFound(tester, find.textContaining(_failure));
      await pumpUntilGone(tester, screen());

      expect(find.text(_progress), findsNothing);
    });

    testWidgets('closing the window shows a dialog to acknowledge first', (
      tester,
    ) async {
      await startFiledVisit(tester);
      breakDerivatives();

      var closed = false;
      final answer = activeSessionGuard!(closingWindow: true).then((may) {
        closed = may;
        return may;
      });
      await keepCopy(tester);
      await pumpUntilFound(tester, find.text('Combined table'));
      await tester.pumpAndSettle();

      expect(find.textContaining(_failure), findsOneWidget);
      expect(closed, isFalse);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(await answer, isTrue);
      expect(find.text('Combined table'), findsNothing);
    });

    testWidgets('closing the window after a clean refresh asks nothing more', (
      tester,
    ) async {
      await startFiledVisit(tester);
      plant('stale');

      final answer = activeSessionGuard!(closingWindow: true);
      await keepCopy(tester);
      await settleUntil(
        tester,
        working,
        () => tableText().contains('last entry'),
      );
      await tester.pumpAndSettle();

      expect(await answer, isTrue);
      expect(find.text('Combined table'), findsNothing);
    });

    testWidgets('the time limit closes the dialog and says so', (tester) async {
      await startFiledVisit(tester);
      final gate = Completer<void>();
      debugRefreshHold = () => gate.future;
      refreshTimeLimit = const Duration(milliseconds: 300);

      await leave(tester);
      await pumpUntilFound(tester, find.text(_progress));
      await pumpUntilGone(tester, find.text(_progress));
      await pumpUntilFound(
        tester,
        find.textContaining(
          'did not finish in time, so it may not include this visit. '
          '$_later',
        ),
      );
      await pumpUntilGone(tester, screen());

      gate.complete();
      await drainDatasetQueue(tester);
      await settleUntil(
        tester,
        working,
        () => tableText().contains('last entry'),
      );
    });

    testWidgets('a second request waits and stacks no second dialog', (
      tester,
    ) async {
      await startFiledVisit(tester);
      final gate = Completer<void>();
      var started = 0;
      debugRefreshHold = () {
        started++;
        return gate.future;
      };

      await leave(tester);
      await pumpUntilFound(tester, find.text(_progress));
      final second = activeSessionGuard!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(started, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Keep copy'), findsNothing);

      gate.complete();
      await pumpUntilGone(tester, screen());
      expect(await second, isTrue);
      expect(started, 1);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a second request after Discard asks nothing and the screen '
        'is popped', (tester) async {
      await startFiledVisit(tester);
      final gate = Completer<void>();
      debugRefreshHold = () => gate.future;

      await tester.binding.handlePopRoute();
      await pumpUntilFound(tester, find.text('Discard copy'));
      await tester.tap(find.text('Discard copy'));
      await pumpUntilFound(tester, find.text(_progress));
      final second = activeSessionGuard!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Discard copy'), findsNothing);
      expect(find.text('Keep copy'), findsNothing);

      gate.complete();
      await pumpUntilGone(tester, screen());
      expect(await second, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a window close that waited shows the earlier snack in a '
        'dialog', (tester) async {
      await startFiledVisit(tester);
      final gate = Completer<void>();
      debugRefreshHold = () => gate.future;

      await leave(tester);
      await pumpUntilFound(tester, find.text(_progress));
      breakDerivatives();
      var closed = false;
      final second = activeSessionGuard!(closingWindow: true).then((may) {
        closed = may;
        return may;
      });
      await tester.pump();

      gate.complete();
      await pumpUntilFound(tester, find.text('Combined table'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(_failure),
        ),
        findsOneWidget,
      );
      expect(closed, isFalse);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('OK'));
      await pumpUntilGone(tester, screen());

      expect(await second, isTrue);
      await drainDatasetQueue(tester);
    });

    testWidgets('two window closes that waited both wait for the message', (
      tester,
    ) async {
      await startFiledVisit(tester);
      final gate = Completer<void>();
      debugRefreshHold = () => gate.future;

      await leave(tester);
      await pumpUntilFound(tester, find.text(_progress));
      breakDerivatives();
      final guard = activeSessionGuard!;
      var closed = 0;
      final first = guard(closingWindow: true).then((may) {
        if (may) closed++;
        return may;
      });
      final second = guard(closingWindow: true).then((may) {
        if (may) closed++;
        return may;
      });
      await tester.pump();

      gate.complete();
      await pumpUntilFound(tester, find.text('Combined table'));
      await tester.pumpAndSettle();

      expect(closed, 0);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('OK'));
      await pumpUntilGone(tester, screen());

      expect(await first, isTrue);
      expect(await second, isTrue);
      await drainDatasetQueue(tester);
    });

    testWidgets('Discard then a window close: the dialog stays until OK and '
        'the screen is popped, not the dialog', (tester) async {
      await startFiledVisit(tester);
      final gate = Completer<void>();
      debugRefreshHold = () => gate.future;
      final copy = working
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhere((f) => f.readAsStringSync().contains('last entry'));

      await tester.binding.handlePopRoute();
      await pumpUntilFound(tester, find.text('Discard copy'));
      await tester.tap(find.text('Discard copy'));
      await pumpUntilFound(tester, find.text(_progress));
      breakDerivatives();
      var closed = false;
      final second = activeSessionGuard!(closingWindow: true).then((may) {
        closed = may;
        return may;
      });
      await tester.pump();

      gate.complete();
      await pumpUntilFound(tester, find.text('Combined table'));
      await pumpUntilGone(tester, screen());
      await tester.pumpAndSettle();

      expect(copy.existsSync(), isFalse);
      expect(find.text('Combined table'), findsOneWidget);
      expect(find.textContaining(_failure), findsOneWidget);
      expect(find.text('open'), findsOneWidget);
      expect(closed, isFalse);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(await second, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('open'), findsOneWidget);
      await drainDatasetQueue(tester);
    });

    testWidgets('a second Back during Discard pops the screen once and '
        'never the home route', (tester) async {
      await startFiledVisit(tester);
      final gate = Completer<void>();
      debugRefreshHold = () => gate.future;

      await tester.binding.handlePopRoute();
      await pumpUntilFound(tester, find.text('Discard copy'));
      await tester.tap(find.text('Discard copy'));
      await pumpUntilFound(tester, find.text(_progress));
      final screenPop = tester.widget<PopScope<Object?>>(
        find.descendant(
          of: screen(),
          matching: find.byWidgetPredicate((w) => w is PopScope),
        ),
      );
      screenPop.onPopInvokedWithResult!(false, null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      gate.complete();
      await pumpUntilGone(tester, screen());
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await drainDatasetQueue(tester);
    });

    testWidgets('a window close during a New refresh shows its message in a '
        'dialog', (tester) async {
      await startFiledVisit(tester);
      final gate = Completer<void>();
      debugRefreshHold = () => gate.future;

      await _pressNew(tester);
      await keepCopy(tester);
      await pumpUntilFound(tester, find.text(_progress));
      breakDerivatives();
      var closed = false;
      final second = activeSessionGuard!(closingWindow: true).then((may) {
        closed = may;
        return may;
      });
      await tester.pump();

      gate.complete();
      await _untilAcknowledge(tester);

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(_failure),
        ),
        findsOneWidget,
      );
      expect(closed, isFalse);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(await second, isTrue);
      await drainDatasetQueue(tester);
    });

    testWidgets('a later window close does not show an earlier refresh '
        'message again', (tester) async {
      await startFiledVisit(tester);
      breakDerivatives();
      await _pressOpen(tester, picker, looseFile());
      await keepCopy(tester);
      await pumpUntilFound(tester, find.textContaining('Opened '));
      await tester.pumpAndSettle(const Duration(seconds: 10));
      await _add(tester, working, 'loose entry');
      await tester.pumpAndSettle(const Duration(seconds: 10));

      await tester.binding.handlePopRoute();
      await pumpUntilFound(tester, find.text('Keep copy'));
      final second = activeSessionGuard!(closingWindow: true);
      await tester.pump();
      await tester.tap(find.text('Keep copy'));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Combined table'), findsNothing);
      expect(await second, isTrue);
      await drainDatasetQueue(tester);
    });

    testWidgets('a window close during an Open refresh shows its message in '
        'a dialog', (tester) async {
      await startFiledVisit(tester);
      final gate = Completer<void>();
      debugRefreshHold = () => gate.future;

      await _pressOpen(tester, picker, looseFile());
      await keepCopy(tester);
      await pumpUntilFound(tester, find.text(_progress));
      breakDerivatives();
      var closed = false;
      final second = activeSessionGuard!(closingWindow: true).then((may) {
        closed = may;
        return may;
      });
      await tester.pump();

      gate.complete();
      await _untilAcknowledge(tester);

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining(_failure),
        ),
        findsOneWidget,
      );
      expect(closed, isFalse);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(await second, isTrue);
      await drainDatasetQueue(tester);
    });
  });
}
