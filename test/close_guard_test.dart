/// Leaving a session asks about its recovery copy, and never deletes it
/// unasked.
library;

import 'dart:async';
import 'dart:io';

import 'package:dbs_annotator/ui/close_guard.dart';
import 'package:dbs_annotator/ui/save_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('dbs_guard'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Future<bool>> leave(
    WidgetTester tester,
    String? path, {
    bool onlyCopy = false,
    bool copyMayBeStale = false,
    bool entriesUnsaved = false,
    bool stillSaving = false,
  }) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = () async {
              final choice = await askLeaveSession(
                context,
                path,
                onlyCopy: onlyCopy,
                copyMayBeStale: copyMayBeStale,
                entriesUnsaved: entriesUnsaved,
                stillSaving: stillSaving,
              );
              if (choice == null) return false;
              if (choice == LeaveChoice.discard) await discardWork(path);
              return true;
            }(),
            child: const Text('leave'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('nothing recorded: leaving asks nothing', (tester) async {
    final result = await leave(tester, '${dir.path}/absent.tsv');
    expect(find.byType(AlertDialog), findsNothing);
    expect(await result, isTrue);
  });

  testWidgets('keep leaves the copy in place', (tester) async {
    final copy = File('${dir.path}/visit.tsv')..writeAsStringSync('rows');
    final result = await leave(tester, copy.path);
    expect(find.text('Keep a recovery copy of this session?'), findsOneWidget);
    await tester.tap(find.text('Keep copy'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    expect(copy.existsSync(), isTrue);
  });

  testWidgets('onlyCopy is forwarded to the dialog wording', (tester) async {
    final copy = File('${dir.path}/visit.tsv')..writeAsStringSync('rows');
    final result = await leave(tester, copy.path, onlyCopy: true);
    expect(find.text('Delete the only copy'), findsOneWidget);
    expect(find.text('Discard copy'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('cancel stays in the session and keeps the copy', (tester) async {
    final copy = File('${dir.path}/visit.tsv')..writeAsStringSync('rows');
    final result = await leave(tester, copy.path);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
    expect(copy.existsSync(), isTrue);
  });

  testWidgets('only copy: warns plainly and names the deletion', (
    tester,
  ) async {
    late Future<bool?> answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                answer = askKeepRecoveryCopy(context, onlyCopy: true),
            child: const Text('leave'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not saved anywhere else'), findsOneWidget);
    expect(find.textContaining('saved file is not changed'), findsNothing);
    await tester.tap(find.text('Delete the only copy'));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });

  testWidgets('a save still running is named, not reported as failed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => askKeepRecoveryCopy(
              context,
              onlyCopy: false,
              stillSaving: true,
            ),
            child: const Text('leave'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('A save is still running, so the latest changes'),
      findsOneWidget,
    );
    expect(find.textContaining('last save failed'), findsNothing);
  });

  testWidgets('discard is an explicit answer, distinct from cancel', (
    tester,
  ) async {
    // The deletion itself is discardWork, covered in durable_autosave_test.
    late Future<bool?> answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                answer = askKeepRecoveryCopy(context, onlyCopy: false),
            child: const Text('leave'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard copy'));
    await tester.pumpAndSettle();
    expect(await answer, isFalse);
  });

  testWidgets('entries that could not be saved: leaving warns they are lost', (
    tester,
  ) async {
    final result = await leave(
      tester,
      '${dir.path}/absent.tsv',
      entriesUnsaved: true,
    );
    expect(find.textContaining('will be lost if you leave'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(await result, isFalse);
  });

  testWidgets('unsaved entries can still be left behind on request', (
    tester,
  ) async {
    final result = await leave(tester, null, entriesUnsaved: true);
    await tester.tap(find.text('Leave and lose them'));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('a copy exists but the last save failed: it may be stale', (
    tester,
  ) async {
    final copy = File('${dir.path}/visit.tsv')..writeAsStringSync('rows');
    await leave(tester, copy.path, copyMayBeStale: true);
    expect(find.textContaining('may be missing the latest'), findsOneWidget);
  });

  testWidgets('entries unsaved with a copy: says the copy lacks them', (
    tester,
  ) async {
    final copy = File('${dir.path}/visit.tsv')..writeAsStringSync('rows');
    await leave(
      tester,
      copy.path,
      onlyCopy: true,
      copyMayBeStale: true,
      entriesUnsaved: true,
    );
    expect(
      find.textContaining('This copy is missing the latest changes'),
      findsOneWidget,
    );
  });

  group('leaveGuardState', () {
    ({bool onlyCopy, bool copyMayBeStale, bool entriesUnsaved}) state({
      bool workingFailed = false,
      bool fileFailed = false,
      bool hasSavePath = true,
      bool savePathIsSandboxCopy = false,
      bool exportedSinceChange = false,
      bool hasEntries = true,
      bool stillSaving = false,
    }) => leaveGuardState(
      workingFailed: workingFailed,
      fileFailed: fileFailed,
      hasSavePath: hasSavePath,
      savePathIsSandboxCopy: savePathIsSandboxCopy,
      exportedSinceChange: exportedSinceChange,
      hasEntries: hasEntries,
      stillSaving: stillSaving,
    );

    test('everything saved: nothing to warn about', () {
      final g = state();
      expect(g.onlyCopy, isFalse);
      expect(g.copyMayBeStale, isFalse);
      expect(g.entriesUnsaved, isFalse);
    });

    test('recovery copy fine, file failed: only copy, not stale', () {
      final g = state(fileFailed: true);
      expect(g.onlyCopy, isTrue);
      expect(g.copyMayBeStale, isFalse);
      expect(g.entriesUnsaved, isFalse);
    });

    test('recovery copy failed, file fine: stale, not the only copy', () {
      final g = state(workingFailed: true);
      expect(g.onlyCopy, isFalse);
      expect(g.copyMayBeStale, isTrue);
      expect(g.entriesUnsaved, isFalse);
    });

    test('both failed: entries are unsaved', () {
      final g = state(workingFailed: true, fileFailed: true);
      expect(g.onlyCopy, isTrue);
      expect(g.entriesUnsaved, isTrue);
    });

    test('no file and the recovery copy failed: entries are unsaved', () {
      expect(
        state(workingFailed: true, hasSavePath: false).entriesUnsaved,
        isTrue,
      );
    });

    test('a sandbox copy is not the user file', () {
      final g = state(workingFailed: true, savePathIsSandboxCopy: true);
      expect(g.onlyCopy, isTrue);
      expect(g.entriesUnsaved, isTrue);
    });

    test('exported: no only-copy or unsaved warning', () {
      final g = state(
        workingFailed: true,
        fileFailed: true,
        exportedSinceChange: true,
      );
      expect(g.onlyCopy, isFalse);
      expect(g.entriesUnsaved, isFalse);
    });

    test('a save still running counts as a failed file write', () {
      final g = state(stillSaving: true);
      expect(g.onlyCopy, isTrue);
      expect(g.copyMayBeStale, isFalse);
      expect(g.entriesUnsaved, isFalse);
    });

    test('still saving and the recovery copy failed: entries unsaved', () {
      final g = state(stillSaving: true, workingFailed: true);
      expect(g.onlyCopy, isTrue);
      expect(g.entriesUnsaved, isTrue);
    });

    test('no save path, recovery copy written: only copy, nothing unsaved', () {
      final g = state(hasSavePath: false);
      expect(g.onlyCopy, isTrue);
      expect(g.copyMayBeStale, isFalse);
      expect(g.entriesUnsaved, isFalse);
    });

    test('no save path but exported: not the only copy', () {
      final g = state(hasSavePath: false, exportedSinceChange: true);
      expect(g.onlyCopy, isFalse);
      expect(g.entriesUnsaved, isFalse);
    });

    test('no entries: nothing is stale or unsaved', () {
      final g = state(workingFailed: true, fileFailed: true, hasEntries: false);
      expect(g.copyMayBeStale, isFalse);
      expect(g.entriesUnsaved, isFalse);
    });
  });

  group('mixed save outcomes through the dialogs', () {
    Future<Future<bool>> leaveWith(
      WidgetTester tester, {
      required String? path,
      required bool workingFailed,
      required bool fileFailed,
      bool exported = false,
      bool stillSaving = false,
    }) {
      final g = leaveGuardState(
        workingFailed: workingFailed,
        fileFailed: fileFailed,
        hasSavePath: true,
        savePathIsSandboxCopy: false,
        exportedSinceChange: exported,
        hasEntries: true,
        stillSaving: stillSaving,
      );
      return leave(
        tester,
        path,
        onlyCopy: g.onlyCopy,
        copyMayBeStale: g.copyMayBeStale,
        entriesUnsaved: g.entriesUnsaved,
        stillSaving: stillSaving,
      );
    }

    testWidgets('copy ok, file failed: only-copy wording, no stale note', (
      tester,
    ) async {
      final copy = File('${dir.path}/visit.tsv')..writeAsStringSync('rows');
      await leaveWith(
        tester,
        path: copy.path,
        workingFailed: false,
        fileFailed: true,
      );
      expect(find.text('Delete the only copy'), findsOneWidget);
      expect(find.textContaining('may be missing the latest'), findsNothing);
    });

    testWidgets('copy failed, file ok, copy exists: stale, not only copy', (
      tester,
    ) async {
      final copy = File('${dir.path}/visit.tsv')..writeAsStringSync('rows');
      await leaveWith(
        tester,
        path: copy.path,
        workingFailed: true,
        fileFailed: false,
      );
      expect(find.text('Discard copy'), findsOneWidget);
      expect(find.text('Delete the only copy'), findsNothing);
      expect(find.textContaining('may be missing the latest'), findsOneWidget);
    });

    testWidgets('copy failed, file ok, no copy: leaves without asking', (
      tester,
    ) async {
      final result = await leaveWith(
        tester,
        path: '${dir.path}/absent.tsv',
        workingFailed: true,
        fileFailed: false,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(await result, isTrue);
    });

    testWidgets('both failed, no copy: warns the entries will be lost', (
      tester,
    ) async {
      await leaveWith(
        tester,
        path: '${dir.path}/absent.tsv',
        workingFailed: true,
        fileFailed: true,
      );
      expect(find.text('Changes could not be saved'), findsOneWidget);
      expect(
        find.textContaining('unless you exported or shared them'),
        findsOneWidget,
      );
    });

    testWidgets('still saving, no copy: asks instead of leaving silently', (
      tester,
    ) async {
      final result = await leaveWith(
        tester,
        path: '${dir.path}/absent.tsv',
        workingFailed: false,
        fileFailed: false,
        stillSaving: true,
      );
      expect(find.text('Changes not saved yet'), findsOneWidget);
      expect(find.textContaining('A save is still running'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('still saving, copy exists: only-copy wording', (tester) async {
      final copy = File('${dir.path}/visit.tsv')..writeAsStringSync('rows');
      await leaveWith(
        tester,
        path: copy.path,
        workingFailed: false,
        fileFailed: false,
        stillSaving: true,
      );
      expect(find.text('Delete the only copy'), findsOneWidget);
      expect(
        find.textContaining('latest changes may not be on disk yet'),
        findsOneWidget,
      );
    });

    testWidgets('both failed but exported: leaves without asking', (
      tester,
    ) async {
      final result = await leaveWith(
        tester,
        path: '${dir.path}/absent.tsv',
        workingFailed: true,
        fileFailed: true,
        exported: true,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(await result, isTrue);
    });
  });
  testWidgets('askLeaveSession reports discard without deleting', (
    tester,
  ) async {
    final copy = File('${dir.path}/visit.tsv')..writeAsStringSync('rows');
    late Future<LeaveChoice?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = askLeaveSession(
              context,
              copy.path,
              onlyCopy: false,
              copyMayBeStale: false,
              entriesUnsaved: false,
            ),
            child: const Text('leave'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard copy'));
    await tester.pumpAndSettle();
    expect(await result, LeaveChoice.discard);
    expect(copy.existsSync(), isTrue);
    await tester.runAsync(() => discardWork(copy.path));
    expect(copy.existsSync(), isFalse);
  });

  testWidgets('waitForSaves follows saves queued while waiting', (
    tester,
  ) async {
    await tester.runAsync(() async {
      var saving = Future<void>.delayed(const Duration(milliseconds: 20));
      final second = Completer<void>();
      unawaited(saving.then((_) => saving = second.future));
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 60))
            .then((_) => second.complete()),
      );
      final stopwatch = Stopwatch()..start();
      expect(await waitForSaves(() => saving), isTrue);
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(55));
    });
  });
}
