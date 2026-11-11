/// The file lifecycle of the session screen: finding unfinished work, opening
/// a file, recording into a BIDS folder, the guard the desktop window asks
/// before closing, and a failing working folder. Each test pins the texts and
/// files a user gets.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/core/prefs/user_prefs.dart';
import 'package:dbs_annotator/ui/close_guard.dart';
import 'package:dbs_annotator/ui/wizard_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_test_helpers.dart';

const _recoveredName = 'sub-07_ses-20260203_task-tuning_run-03_beh.tsv';
const _openedName = 'sub-08_ses-20260204_task-tuning_run-02_beh.tsv';
const _guardTitle = 'Keep a recovery copy of this session?';
const _recoveryTitle = 'Unfinished session found';
const _newSnack = 'New session in Cohort.';

String _planted(String text) => sessionTsv(notes: text);
String _blank() => sessionTsv().split('\n').first;
String _opened(String file) => 'Opened $file (0 configurations tested so far).';

Future<void> _show(WidgetTester tester) async {
  await pumpScreen(tester, sessionScreen());
  await awaitRecoveryCheck(tester);
}

Finder _entryStep() => find.text('Save configuration').hitTestable();
Finder _setupStep() => find.text('Open saved session').hitTestable();

String _field(WidgetTester tester, String label) => tester
    .widget<TextField>(
      find.widgetWithText(TextField, label, skipOffstage: false),
    )
    .controller!
    .text;

String _toSlashes(String path) => path.replaceAll('\\', '/');

List<File> _behTsvs(Directory root) => root
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => _toSlashes(f.path).contains('/beh/'))
    .where((f) => f.path.endsWith('_beh.tsv'))
    .toList();

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

Directory _dataset() {
  final dataset = Directory.systemTemp.createTempSync('dbs_dataset');
  addTearDown(() => removeQuietly(dataset));
  _useFolder(dataset);
  return dataset;
}

Future<void> _toSetup(WidgetTester tester) async {
  final strip = find.byType(SessionStrip);
  if (strip.evaluate().isEmpty) return;
  await tester.tap(strip);
  await tester.pumpAndSettle();
}

Future<void> _newVisit(
  WidgetTester tester,
  Directory dataset, {
  String? session,
}) async {
  await pumpUntilFound(tester, find.text(dataset.path));
  await tester.enterText(find.widgetWithText(TextField, 'Patient ID'), '01');
  if (session != null) {
    await tester.enterText(find.widgetWithText(TextField, 'Visit'), session);
  }
  await tapNew(tester);
  await pumpUntilFound(tester, find.textContaining(_newSnack));
  await tester.pumpAndSettle();
}

Future<void> _add(WidgetTester tester, Directory working, String text) async {
  if (_entryStep().evaluate().isEmpty) {
    await tester.tap(find.text('Programming'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.widgetWithText(TextField, 'Notes'), text);
  final save = find.text('Save configuration');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await settleUntil(
    tester,
    working,
    () => workingText(working).contains(text),
    cap: const Duration(seconds: 40),
  );
}

void _expectSidecar(File tsv) {
  final sidecar = jsonAt(tsv.path.replaceFirst(RegExp(r'\.tsv$'), '.json'));
  expect(
    sidecar['TaskDescription'],
    startsWith('Deep brain stimulation programming.'),
  );
  expect(sidecar.containsKey('left_stim_freq'), isTrue);
  expect(sidecar.containsKey('notes'), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('unfinished work', () {
    Future<void> found(WidgetTester tester) async {
      await _show(tester);
      await pumpUntilFound(tester, find.text(_recoveryTitle));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '$_recoveredName was left open, 0 configurations tested. It was '
          'saved as you went, and can be reopened here.',
        ),
        findsOneWidget,
      );
    }

    testWidgets('Reopen restores it, its labels and the right step', (
      tester,
    ) async {
      final dirs = useTempDirs();
      plantWork(dirs.working, _recoveredName, _planted('recovered entry'));
      await found(tester);

      await tester.tap(find.text('Reopen'));
      await pumpUntilFound(
        tester,
        find.text(
          'Reopened $_recoveredName. Export it to save it outside the app.',
        ),
      );
      await tester.pumpAndSettle();

      expect(_entryStep(), findsOneWidget);
      expect(_setupStep(), findsNothing);
      expect(find.textContaining('recovered entry'), findsWidgets);

      await _toSetup(tester);
      expect(_field(tester, 'Patient ID'), '07');
      expect(_field(tester, 'Task'), 'tuning');
      expect(_field(tester, 'Run'), '03');
    });

    testWidgets('a reopened copy keeps recording into itself only', (
      tester,
    ) async {
      final dirs = useTempDirs();
      final planted = plantWork(
        dirs.working,
        _recoveredName,
        _planted('recovered entry'),
      );
      await found(tester);
      await tester.tap(find.text('Reopen'));
      await pumpUntilFound(tester, find.textContaining('Reopened'));
      await tester.pumpAndSettle();

      await _add(tester, dirs.working, 'after reopening');

      final text = planted.readAsStringSync();
      expect(text, contains('recovered entry'));
      expect(
        text.indexOf('recovered entry'),
        lessThan(text.indexOf('after reopening')),
      );
      expect(
        Directory('${dirs.working.path}/work').listSync().whereType<File>(),
        hasLength(1),
      );
      expect(dirs.saved.listSync(), isEmpty);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(_guardTitle), findsOneWidget);
      expect(find.text('Delete the only copy'), findsOneWidget);
    });

    testWidgets('Discard deletes the copy and starts empty', (tester) async {
      final dirs = useTempDirs();
      final planted = plantWork(
        dirs.working,
        _recoveredName,
        _planted('recovered entry'),
      );
      await found(tester);

      await tester.tap(find.text('Discard'));
      for (var i = 0; i < 40 && planted.existsSync(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(planted.existsSync(), isFalse);
      expect(find.text(_recoveryTitle), findsNothing);
      expect(find.textContaining('Reopened'), findsNothing);
      expect(_setupStep(), findsOneWidget);
    });

    testWidgets('dismissing the question keeps the copy untouched', (
      tester,
    ) async {
      final dirs = useTempDirs();
      final planted = plantWork(
        dirs.working,
        _recoveredName,
        _planted('recovered entry'),
      );
      await found(tester);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      await awaitRecoveryCheck(tester);

      expect(find.text(_recoveryTitle), findsNothing);
      expect(find.textContaining('Reopened'), findsNothing);
      expect(planted.readAsStringSync(), _planted('recovered entry'));
    });

    testWidgets('copies of the other kind or without entries are not '
        'offered', (tester) async {
      final dirs = useTempDirs();
      plantWork(dirs.working, 'sub-01_task-other_beh.tsv', notesTsv());
      plantWork(dirs.working, 'sub-02_task-empty_beh.tsv', _blank());
      await _show(tester);
      await awaitRecoveryCheck(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(_recoveryTitle), findsNothing);
    });

    testWidgets('skips such copies to offer the older usable one', (
      tester,
    ) async {
      final dirs = useTempDirs();
      final now = DateTime.now();
      plantWork(
        dirs.working,
        _recoveredName,
        _planted('recovered entry'),
        modified: now.subtract(const Duration(hours: 3)),
      );
      plantWork(
        dirs.working,
        'sub-01_task-other_beh.tsv',
        notesTsv(),
        modified: now.subtract(const Duration(hours: 2)),
      );
      plantWork(
        dirs.working,
        'sub-02_task-empty_beh.tsv',
        _blank(),
        modified: now.subtract(const Duration(hours: 1)),
      );
      await _show(tester);
      await pumpUntilFound(tester, find.text(_recoveryTitle));
      await tester.pumpAndSettle();

      expect(find.textContaining(_recoveredName), findsOneWidget);
    });
  });

  group('Open', () {
    Future<(Directory, Directory, File, FakePicker)> prepare(
      WidgetTester tester,
    ) async {
      final dirs = useTempDirs();
      final file = File('${dirs.saved.path}/$_openedName')
        ..writeAsStringSync(_planted('opened entry'));
      final picker = useFakePicker()..file = pickedFile(file);
      await _show(tester);
      return (dirs.working, dirs.saved, file, picker);
    }

    testWidgets('a file of the right kind loads and is written back to', (
      tester,
    ) async {
      final (working, _, file, _) = await prepare(tester);

      await tester.tap(find.text('Open saved session'));
      await pumpUntilFound(tester, find.text(_opened(_openedName)));
      await tester.pumpAndSettle();

      expect(find.text(_opened(_openedName)), findsOneWidget);
      expect(_setupStep(), findsOneWidget);
      expect(_field(tester, 'Patient ID'), '08');
      expect(_field(tester, 'Task'), 'tuning');
      expect(_field(tester, 'Run'), '02');

      await _add(tester, working, 'after opening');
      await settleUntil(
        tester,
        working,
        () => file.readAsStringSync().contains('after opening'),
      );
      final written = file.readAsStringSync();
      expect(written, contains('opened entry'));
      expect(
        written.indexOf('opened entry'),
        lessThan(written.indexOf('after opening')),
      );
      expect(workingText(working), contains('opened entry'));
      expect(workingText(working), contains('after opening'));
    });

    testWidgets('a file of the other kind is refused and changes nothing', (
      tester,
    ) async {
      final (working, saved, _, picker) = await prepare(tester);
      final other = File('${saved.path}/$_openedName')
        ..writeAsStringSync(notesTsv());
      picker.file = pickedFile(other);

      await tester.tap(find.text('Open saved session'));
      const refused =
          '$_openedName is an annotations (notes) file; this view needs a '
          'programming session.';
      await pumpUntilFound(tester, find.text(refused));
      await tester.pumpAndSettle();

      expect(find.text(refused), findsOneWidget);
      expect(find.textContaining('Opened '), findsNothing);
      expect(_setupStep(), findsOneWidget);
      expect(
        Directory('${working.path}/work').listSync().whereType<File>(),
        isEmpty,
      );
      expect(other.readAsStringSync(), notesTsv());
    });

    testWidgets('a picker that fails says so and changes nothing', (
      tester,
    ) async {
      final (working, _, _, picker) = await prepare(tester);
      picker.failure = Exception('no dialog');

      await tester.tap(find.text('Open saved session'));
      await pumpUntilFound(
        tester,
        find.text('Could not open the file picker. (Exception: no dialog)'),
      );

      expect(find.textContaining('Opened '), findsNothing);
      expect(
        Directory('${working.path}/work').listSync().whereType<File>(),
        isEmpty,
      );
    });

    testWidgets('a file that is not text cannot be read', (tester) async {
      final (_, saved, _, picker) = await prepare(tester);
      final binary = File('${saved.path}/$_openedName')
        ..writeAsBytesSync([0xff, 0xfe, 0xfd]);
      picker.file = pickedFile(binary);

      await tester.tap(find.text('Open saved session'));
      await pumpUntilFound(tester, find.text('Could not read $_openedName.'));

      expect(find.textContaining('Opened '), findsNothing);
    });

    testWidgets('with entries recorded, the leave question comes first', (
      tester,
    ) async {
      final dataset = _dataset();
      final (working, _, file, _) = await prepare(tester);
      await _newVisit(tester, dataset);
      await _add(tester, working, 'first entry');
      final oldCopy = Directory('${working.path}/work')
          .listSync()
          .whereType<File>()
          .single;
      await _toSetup(tester);

      await tester.tap(find.text('Open saved session'));
      await pumpUntilFound(tester, find.text(_guardTitle));
      await tester.pumpAndSettle();
      expect(find.text('Discard copy'), findsOneWidget);
      expect(find.textContaining('Opened '), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await awaitRecoveryCheck(tester);
      expect(find.textContaining('Opened '), findsNothing);
      expect(oldCopy.readAsStringSync(), contains('first entry'));

      await tester.tap(find.text('Open saved session'));
      await pumpUntilFound(tester, find.text(_guardTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard copy'));
      await pumpUntilFound(tester, find.text(_opened(_openedName)));
      await tester.pumpAndSettle();

      expect(oldCopy.existsSync(), isFalse);
      expect(file.readAsStringSync(), _planted('opened entry'));
    });
  });

  group('recording into a BIDS folder', () {
    testWidgets('is filed at its BIDS path on the first entry', (tester) async {
      final dirs = useTempDirs();
      final dataset = _dataset();
      await _show(tester);

      await _newVisit(tester, dataset);

      expect(
        find.text('$_newSnack Run 01 is saved there from the first save.'),
        findsOneWidget,
      );
      expect(_behTsvs(dataset), isEmpty);

      await _add(tester, dirs.working, 'dataset entry');
      await pumpUntilFound(tester, find.textContaining('Saved as '));

      final filed = _behTsvs(dataset).single;
      final rel = _toSlashes(filed.path)
          .substring(_toSlashes(dataset.path).length + 1);
      expect(
        rel,
        matches(
          RegExp(
            r'^sub-01/ses-\d{8}/beh/sub-01_ses-\d{8}_task-\w+_run-01_beh'
            r'\.tsv$',
          ),
        ),
      );
      expect(find.text('Saved as $rel.'), findsOneWidget);
      expect(filed.readAsStringSync(), contains('dataset entry'));
      _expectSidecar(filed);

      await _add(tester, dirs.working, 'second dataset entry');
      await settleUntil(
        tester,
        dirs.working,
        () => filed.readAsStringSync().contains('second dataset entry'),
      );
      expect(filed.readAsStringSync(), contains('dataset entry'));
      expect(_behTsvs(dataset), hasLength(1));
    });

    testWidgets('a name the folder already holds is refused and kept in the '
        'app', (tester) async {
      final dirs = useTempDirs();
      final dataset = _dataset();
      await _show(tester);
      await _newVisit(tester, dataset);
      final today = BidsName.sessionStamp(DateTime.now());
      final file = 'sub-01_ses-${today}_task-programming_run-01_beh.tsv';
      final taken = File('${dataset.path}/sub-01/ses-$today/beh/$file')
        ..createSync(recursive: true)
        ..writeAsStringSync(_planted('someone else'));

      await _add(tester, dirs.working, 'dataset entry');
      await pumpUntilFound(
        tester,
        find.textContaining('That BIDS folder already holds'),
      );

      expect(
        find.text(
          'That BIDS folder already holds $file. This visit stays in the app. '
          'Export it under a different run.',
        ),
        findsOneWidget,
      );
      expect(taken.readAsStringSync(), _planted('someone else'));
      expect(workingText(dirs.working), contains('dataset entry'));
    });

    testWidgets('Open afterwards records into the opened file only', (
      tester,
    ) async {
      final dirs = useTempDirs();
      final dataset = _dataset();
      final picker = useFakePicker();
      final loose = File('${dirs.saved.path}/$_openedName')
        ..writeAsStringSync(_planted('opened entry'));
      await _show(tester);
      await _newVisit(tester, dataset, session: 'visitA');
      await _add(tester, dirs.working, 'dataset entry');
      await pumpUntilFound(tester, find.textContaining('Saved as '));
      final filed = _behTsvs(dataset).single;
      final filedText = filed.readAsStringSync();

      picker.file = pickedFile(loose);
      await _toSetup(tester);
      await tester.tap(find.text('Open saved session'));
      await pumpUntilFound(tester, find.text(_guardTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep copy'));
      await pumpUntilFound(tester, find.text(_opened(_openedName)));
      await tester.pumpAndSettle();
      await _add(tester, dirs.working, 'after opening');
      await settleUntil(
        tester,
        dirs.working,
        () => loose.readAsStringSync().contains('after opening'),
      );

      expect(filed.readAsStringSync(), filedText);
      expect(_behTsvs(dataset), hasLength(1));
      expect(filed.path, contains('ses-visitA'));
      await _toSetup(tester);
      expect(_field(tester, 'Visit'), '20260204');
    });
  });

  group('the close guard', () {
    testWidgets('is set while the screen is open and cleared after', (
      tester,
    ) async {
      useTempDirs();
      await _show(tester);
      expect(activeSessionGuard, isNotNull);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
      expect(activeSessionGuard, isNull);
    });

    testWidgets('lets the window close when nothing was recorded', (
      tester,
    ) async {
      useTempDirs();
      await _show(tester);

      final answer = activeSessionGuard!();
      await tester.pumpAndSettle();

      expect(await answer, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('asks after an entry, and Cancel keeps the window open', (
      tester,
    ) async {
      final dirs = useTempDirs();
      final dataset = _dataset();
      await _show(tester);
      await _newVisit(tester, dataset);
      await _add(tester, dirs.working, 'an entry');

      final answer = activeSessionGuard!();
      await pumpUntilFound(tester, find.text(_guardTitle));
      await tester.pumpAndSettle();
      expect(find.text('Discard copy'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await answer, isFalse);
      expect(find.text(_guardTitle), findsNothing);
      expect(workingText(dirs.working), contains('an entry'));
    });
  });

  group('a working folder and BIDS folder that cannot be written', () {
    testWidgets('says the entry was not saved and warns on leaving', (
      tester,
    ) async {
      final dirs = useTempDirs();
      final dataset = _dataset();
      await _show(tester);
      await _newVisit(tester, dataset);
      Directory('${dirs.working.path}/work').deleteSync(recursive: true);
      File('${dirs.working.path}/work').writeAsStringSync('in the way');
      dataset.deleteSync(recursive: true);
      File(dataset.path).writeAsStringSync('in the way');
      addTearDown(() => File(dataset.path).deleteSync());

      await tester.tap(find.text('Programming'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Notes'),
        'doomed entry',
      );
      final save = find.text('Save configuration');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await pumpUntilFound(
        tester,
        find.textContaining('This change is not saved anywhere yet.'),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not file into the BIDS folder: '),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await pumpUntilFound(tester, find.text('Changes could not be saved'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'The changes in this session could not be saved to disk and '
          'will be lost if you leave',
        ),
        findsOneWidget,
      );
      expect(find.text('Leave and lose them'), findsOneWidget);
      expect(find.text('Stay'), findsOneWidget);
    });
  });
}
