/// Leaving a screen whose notes exist only as the recovery copy says so.
library;

import 'dart:async';
import 'dart:io';

import 'package:dbs_annotator/core/safe_file.dart';
import 'package:dbs_annotator/ui/save_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('leaving with only the recovery copy warns it is the only copy', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('dbs_leave');
    debugWorkingDir = root;
    addTearDown(() {
      debugWorkingDir = null;
      removeQuietly(root);
    });
    await openNotesStep(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Note'), 'a note');
    await tester.tap(find.text('Insert timestamped note'));
    bool holdsNote() => workingText(root).contains('a note');
    await settleUntil(tester, root, holdsNote);
    expect(holdsNote(), isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.textContaining('not saved anywhere else'), findsOneWidget);
    expect(find.text('Delete the only copy'), findsOneWidget);
  });

  testWidgets('a disk export lifts the warning until the next note', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('dbs_leave');
    final saved = Directory.systemTemp.createTempSync('dbs_saved');
    final cache = Directory.systemTemp.createTempSync('dbs_cache');
    debugWorkingDir = root;
    debugSaveDir = saved;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => cache.path,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
      debugWorkingDir = null;
      debugSaveDir = null;
      removeQuietly(root);
      removeQuietly(saved);
      removeQuietly(cache);
    });
    await openNotesStep(tester);

    bool workingHolds(String text) => workingText(root).contains(text);

    Future<void> addNote(String text) async {
      await tester.enterText(find.widgetWithText(TextField, 'Note'), text);
      await tester.tap(find.text('Insert timestamped note'));
      await settleUntil(tester, root, () => workingHolds(text));
    }

    await addNote('first');
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Data (TSV)'));
    await settleUntil(
      tester,
      root,
      () =>
          saved.listSync().whereType<File>().isNotEmpty &&
          !cache
              .listSync(recursive: true)
              .any((e) => e is Directory && e.path.contains('export-')),
    );
    expect(saved.listSync().whereType<File>(), isNotEmpty);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.textContaining('not saved anywhere else'), findsNothing);
    expect(find.text('Keep a recovery copy of this session?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await addNote('second');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.textContaining('not saved anywhere else'), findsOneWidget);
  });

  testWidgets('two quick notes are both written, oldest first', (tester) async {
    final root = Directory.systemTemp.createTempSync('dbs_leave');
    debugWorkingDir = root;
    addTearDown(() {
      debugWorkingDir = null;
      removeQuietly(root);
    });
    await openNotesStep(tester);
    final field = find.widgetWithText(TextField, 'Note');
    await tester.enterText(field, 'first note');
    await tester.tap(find.text('Insert timestamped note'));
    await tester.enterText(field, 'second note');
    await tester.tap(find.text('Insert timestamped note'));
    await settleUntil(
      tester,
      root,
      () => workingText(root).contains('second note'),
    );
    final text = workingText(root);
    expect(text.indexOf('first note'), greaterThanOrEqualTo(0));
    expect(text.indexOf('first note'), lessThan(text.indexOf('second note')));
  });

  Future<void> startNew(WidgetTester tester) async {
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Loose TSV'));
  }

  Future<void> addNote(WidgetTester tester, Directory root, String text) async {
    await tester.enterText(find.widgetWithText(TextField, 'Note'), text);
    await tester.tap(find.text('Insert timestamped note'));
    await settleUntil(tester, root, () => workingText(root).contains(text));
  }

  Future<(Directory, Directory)> newScreen(WidgetTester tester) async {
    final root = Directory.systemTemp.createTempSync('dbs_leave');
    final saved = Directory.systemTemp.createTempSync('dbs_saved');
    // A future cached from an earlier test's fake-async zone delivers to
    // that zone, so the listeners of later tests never run.
    rootBundle.evict('schema/tsv_schema.json');
    debugWorkingDir = root;
    debugSaveDir = saved;
    addTearDown(() {
      debugWorkingDir = null;
      debugSaveDir = null;
      removeQuietly(root);
      removeQuietly(saved);
    });
    await openNotesStep(tester);
    return (root, saved);
  }

  final guard = find.text('Keep a recovery copy of this session?');

  testWidgets('New with unsaved notes asks before replacing them', (
    tester,
  ) async {
    final (root, _) = await newScreen(tester);
    await addNote(tester, root, 'a note');

    await startNew(tester);
    await settleUntil(tester, root, () => guard.evaluate().isNotEmpty);
    expect(guard, findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(workingText(root), contains('a note'));
    expect(find.textContaining('a note'), findsWidgets);
  });

  testWidgets('New deletes the old working copy only after the new session', (
    tester,
  ) async {
    final (root, saved) = await newScreen(tester);
    await addNote(tester, root, 'a note');

    await startNew(tester);
    await settleUntil(tester, root, () => guard.evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete the only copy'));
    await settleUntil(
      tester,
      root,
      () => !workingText(root).contains('a note'),
    );

    final created = saved.listSync().whereType<File>().singleWhere(
      (f) => f.path.endsWith('.tsv'),
    );
    final name = created.path.replaceAll('\\', '/').split('/').last;
    expect(find.text('New notes file: ${saved.path}/$name'), findsOneWidget);
    expect(workingText(root), isNot(contains('a note')));
    expect(find.textContaining('a note'), findsNothing);
  });

  testWidgets('New refuses the file the notes are already saved in', (
    tester,
  ) async {
    final (root, saved) = await newScreen(tester);
    await startNew(tester);
    await pumpUntilFound(tester, find.textContaining('New notes file: '));
    await tester.pumpAndSettle();
    await addNote(tester, root, 'a note');
    final file = saved.listSync().whereType<File>().singleWhere(
      (f) => f.path.endsWith('.tsv'),
    );
    await settleUntil(
      tester,
      root,
      () => file.readAsStringSync().contains('a note'),
    );

    await startNew(tester);
    await settleUntil(tester, root, () => guard.evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep copy'));
    await pumpUntilFound(tester, find.textContaining('already saved in'));
    expect(find.textContaining('already saved in'), findsOneWidget);
    await settleUntil(
      tester,
      root,
      () => file.readAsStringSync().contains('a note'),
    );
  });

  testWidgets('Discarding the copy of a refused New keeps the working copy', (
    tester,
  ) async {
    final (root, saved) = await newScreen(tester);
    await startNew(tester);
    await pumpUntilFound(tester, find.textContaining('New notes file: '));
    await tester.pumpAndSettle();
    await addNote(tester, root, 'a note');
    final file = saved.listSync().whereType<File>().singleWhere(
      (f) => f.path.endsWith('.tsv'),
    );
    await settleUntil(
      tester,
      root,
      () => file.readAsStringSync().contains('a note'),
    );

    await startNew(tester);
    await settleUntil(tester, root, () => guard.evaluate().isNotEmpty);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard copy'));
    await pumpUntilFound(tester, find.textContaining('already saved in'));
    expect(workingText(root), contains('a note'));
    await settleUntil(
      tester,
      root,
      () => file.readAsStringSync().contains('a note'),
    );
  });

  testWidgets('New is refused while a save is running, and nothing is lost', (
    tester,
  ) async {
    final (root, saved) = await newScreen(tester);
    await startNew(tester);
    await pumpUntilFound(tester, find.textContaining('New notes file: '));
    await tester.pumpAndSettle();
    await addNote(tester, root, 'first');
    final file = saved.listSync().whereType<File>().singleWhere(
      (f) => f.path.endsWith('.tsv'),
    );
    await settleUntil(
      tester,
      root,
      () => file.readAsStringSync().contains('first'),
    );

    final gate = Completer<void>();
    debugWriteGate = gate.future;
    addTearDown(() => debugWriteGate = null);
    await tester.enterText(find.widgetWithText(TextField, 'Note'), 'held');
    await tester.tap(find.text('Insert timestamped note'));
    await tester.pump();

    await startNew(tester);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.textContaining('A save is still running, so'), findsOneWidget);
    await tester.tap(find.text('Keep copy'));
    await tester.pumpAndSettle();
    expect(
      find.text('A save is still running. Try again in a moment.'),
      findsOneWidget,
    );
    expect(
      saved.listSync().whereType<File>().where((f) => f.path.endsWith('.tsv')),
      hasLength(1),
    );
    expect(find.textContaining('held'), findsWidgets);

    final sizeBefore = file.statSync().size;
    gate.complete();
    await settleUntil(
      tester,
      root,
      () => file.statSync().size > sizeBefore,
      step: const Duration(milliseconds: 100),
    );
    expect(file.readAsStringSync(), contains('held'));
    expect(file.readAsStringSync(), contains('first'));
  });
}
