/// The session screen's file lifecycle: leaving, New, Open and Export against
/// real files, pinning the texts and files a clinician gets.
library;

import 'dart:async';
import 'dart:io';

import 'package:dbs_annotator/core/safe_file.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_test_helpers.dart';

const _guardTitle = 'Keep a recovery copy of this session?';

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

Future<void> _startNew(WidgetTester tester) async {
  if (find.text('New').hitTestable().evaluate().isEmpty) {
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('New'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Loose TSV'));
}

List<File> _tsvIn(Directory dir) => dir
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.tsv'))
    .toList();

Future<(Directory, Directory)> _show(WidgetTester tester) async {
  final dirs = useTempDirs();
  await pumpScreen(tester, sessionScreen());
  await awaitRecoveryCheck(tester);
  return (dirs.working, dirs.saved);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final guard = find.text(_guardTitle);

  group('leaving', () {
    testWidgets('with only the working copy says it is the only copy', (
      tester,
    ) async {
      final (working, _) = await _show(tester);
      await addSessionEntry(tester, working, 'first visit');

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
      final (working, _) = await _show(tester);
      await addSessionEntry(tester, working, 'first visit');
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
      final (working, _) = await _show(tester);
      await addSessionEntry(tester, working, 'first visit');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep copy'));
      await tester.pumpAndSettle();

      expect(find.byType(SessionScreen), findsNothing);
      expect(workingText(working), contains('first visit'));
    });
  });

  group('New', () {
    testWidgets('after an entry asks, and Delete the only copy replaces it', (
      tester,
    ) async {
      final (working, saved) = await _show(tester);
      await addSessionEntry(tester, working, 'first visit');
      final oldCopy = Directory('${working.path}/work')
          .listSync()
          .whereType<File>()
          .single;

      await _startNew(tester);
      await pumpUntilFound(tester, guard);
      await tester.pumpAndSettle();
      expect(find.text('Delete the only copy'), findsOneWidget);
      await tester.tap(find.text('Delete the only copy'));
      await pumpUntilFound(tester, find.textContaining('New session: '));
      await settleUntil(tester, working, () => !oldCopy.existsSync());

      final created = _tsvIn(saved).single;
      expect(
        find.text('New session: ${saved.path}/${_basename(created.path)}'),
        findsOneWidget,
      );
      expect(created.readAsStringSync(), SessionAuthoring().serialize());
      expect(oldCopy.existsSync(), isFalse);
      expect(workingText(working), isNot(contains('first visit')));

      await addSessionEntry(tester, working, 'second visit');
      await settleUntil(
        tester,
        working,
        () => created.readAsStringSync().contains('second visit'),
      );
      final text = created.readAsStringSync();
      expect(text, isNot(contains('first visit')));
      final authoring = SessionAuthoring()..loadExisting(text);
      expect(authoring.rows.map((r) => r.blockId).toSet(), {'0'});
      expect(authoring.blockId, 1);
    });

    testWidgets('Cancel keeps the entries and creates nothing', (tester) async {
      final (working, saved) = await _show(tester);
      await addSessionEntry(tester, working, 'first visit');

      await _startNew(tester);
      await pumpUntilFound(tester, guard);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await awaitRecoveryCheck(tester);

      expect(find.textContaining('New session: '), findsNothing);
      expect(saved.listSync(), isEmpty);
      expect(workingText(working), contains('first visit'));
    });

    testWidgets('onto the file already in use is refused and rewrites it', (
      tester,
    ) async {
      final (working, saved) = await _show(tester);
      await _startNew(tester);
      await pumpUntilFound(tester, find.textContaining('New session: '));
      await tester.pumpAndSettle();
      await addSessionEntry(tester, working, 'first visit');
      final file = _tsvIn(saved).single;
      await settleUntil(
        tester,
        working,
        () => file.readAsStringSync().contains('first visit'),
      );

      await _startNew(tester);
      await pumpUntilFound(tester, guard);
      await tester.pumpAndSettle();
      expect(find.text('Discard copy'), findsOneWidget);
      await tester.tap(find.text('Keep copy'));
      await pumpUntilFound(tester, find.textContaining('already saved in'));

      expect(
        find.text(
          'Could not start a new file: that is the file this session is '
          'already saved in. Choose another name.',
        ),
        findsOneWidget,
      );
      await settleUntil(
        tester,
        working,
        () => file.readAsStringSync().contains('first visit'),
      );
      final authoring = SessionAuthoring()
        ..loadExisting(file.readAsStringSync());
      expect(authoring.rows, isNotEmpty);
      expect(_tsvIn(saved), hasLength(1));
    });

    testWidgets('Discard copy of a refused New keeps the working copy', (
      tester,
    ) async {
      final (working, saved) = await _show(tester);
      await _startNew(tester);
      await pumpUntilFound(tester, find.textContaining('New session: '));
      await tester.pumpAndSettle();
      await addSessionEntry(tester, working, 'first visit');
      final file = _tsvIn(saved).single;
      await settleUntil(
        tester,
        working,
        () => file.readAsStringSync().contains('first visit'),
      );

      await _startNew(tester);
      await pumpUntilFound(tester, guard);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard copy'));
      await pumpUntilFound(tester, find.textContaining('already saved in'));

      expect(workingText(working), contains('first visit'));
      await settleUntil(
        tester,
        working,
        () => file.readAsStringSync().contains('first visit'),
      );
    });

    testWidgets('is refused while a save is running, and nothing is lost', (
      tester,
    ) async {
      final (working, saved) = await _show(tester);
      await _startNew(tester);
      await pumpUntilFound(tester, find.textContaining('New session: '));
      await tester.pumpAndSettle();
      await addSessionEntry(tester, working, 'first entry');
      final file = _tsvIn(saved).single;
      await settleUntil(
        tester,
        working,
        () => file.readAsStringSync().contains('first entry'),
      );

      final gate = Completer<void>();
      debugWriteGate = gate.future;
      addTearDown(() => debugWriteGate = null);
      await tester.enterText(find.widgetWithText(TextField, 'Notes'), 'held');
      final insert = find.text('Insert baseline');
      await tester.ensureVisible(insert);
      await tester.tap(insert);
      await tester.pump();

      await _startNew(tester);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'A save is still running, so the latest entries may not be on disk '
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
      expect(_tsvIn(saved), hasLength(1));

      final sizeBefore = file.statSync().size;
      gate.complete();
      await settleUntil(
        tester,
        working,
        () => file.statSync().size > sizeBefore,
        step: const Duration(milliseconds: 100),
      );
      final text = file.readAsStringSync();
      expect(text, contains('first entry'));
      expect(text, contains('held'));
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

      await tester.tap(find.text('Open existing TSV'));
      await pumpUntilFound(tester, find.textContaining('Opened '));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text(
          'Opened sub-08_ses-20260204_task-x_beh.tsv (1 rows, next block 1, '
          'append 2).',
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
      final dirs = useTempDirs();
      final cache = Directory.systemTemp.createTempSync('dbs_cache');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => cache.path,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        removeQuietly(cache);
      });
      await pumpScreen(tester, sessionScreen());
      await awaitRecoveryCheck(tester);
      await addSessionEntry(tester, dirs.working, 'first visit');

      await tester.tap(find.text('Recording'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export TSV'));
      await settleUntil(
        tester,
        dirs.working,
        () =>
            dirs.saved.listSync().whereType<File>().isNotEmpty &&
            !cache
                .listSync(recursive: true)
                .any((e) => e is Directory && e.path.contains('export-')),
      );
      final exported = dirs.saved.listSync().whereType<File>().single;
      expect(exported.readAsStringSync(), contains('first visit'));

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('not saved anywhere else'), findsNothing);
      expect(guard, findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await addSessionEntry(tester, dirs.working, 'second visit');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('not saved anywhere else'), findsOneWidget);
      expect(find.text('Delete the only copy'), findsOneWidget);
    });
  });
}
