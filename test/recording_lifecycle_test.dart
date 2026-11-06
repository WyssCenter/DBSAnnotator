/// The file lifecycle the session screen and the notes screen share: finding
/// unfinished work, opening a file, recording into a dataset, the guard the
/// desktop window asks before closing, and a failing working folder. Each test
/// runs against both screens and pins the texts and files a user gets.
library;

import 'dart:io';

import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/ui/annotations_screen.dart';
import 'package:dbs_annotator/ui/close_guard.dart';
import 'package:dbs_annotator/ui/save_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_test_helpers.dart';

const _recoveredName = 'sub-07_ses-20260203_task-tuning_run-03_beh.tsv';
const _openedName = 'sub-08_ses-20260204_task-tuning_run-02_beh.tsv';
const _guardTitle = 'Keep a recovery copy of this session?';

class _Screen {
  const _Screen({
    required this.name,
    required this.build,
    required this.planted,
    required this.otherKind,
    required this.blank,
    required this.recoveryTitle,
    required this.recoveredCount,
    required this.entryStep,
    required this.opensOnEntryStep,
    required this.opened,
    required this.rejectsOther,
    required this.entryFailed,
    required this.filedHere,
    required this.add,
    required this.insertLabel,
    required this.stepLabel,
    required this.textLabel,
    required this.pickerFailed,
    required this.askWhat,
    required this.newSnack,
    required this.collision,
    required this.sidecarTask,
    required this.sidecarHasBlocks,
    required this.exportTsv,
  });

  final String name;
  final Widget Function() build;
  final String Function(String text) planted;
  final String Function() otherKind;
  final String Function() blank;
  final String recoveryTitle;
  final String recoveredCount;
  final Finder Function() entryStep;
  final bool opensOnEntryStep;
  final String Function(String file) opened;
  final String Function(String file) rejectsOther;
  final String entryFailed;
  final String filedHere;
  final Future<void> Function(
    WidgetTester tester,
    Directory working,
    String text,
  )
  add;
  final String insertLabel;
  final String stepLabel;
  final String? textLabel;
  final String Function(String error) pickerFailed;
  final String askWhat;
  final String newSnack;
  final String Function(String filename) collision;
  final String sidecarTask;
  final bool sidecarHasBlocks;
  final Future<void> Function(WidgetTester tester) exportTsv;

  Future<void> show(WidgetTester tester) async {
    await pumpScreen(tester, build());
    await awaitRecoveryCheck(tester);
  }

  Future<void> toFileStep(WidgetTester tester) async {
    if (_fileStep().evaluate().isNotEmpty) return;
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
  }
}

Future<void> _addNote(
  WidgetTester tester,
  Directory working,
  String text,
) async {
  final insert = find.text('Insert timestamped note').hitTestable();
  if (insert.evaluate().isEmpty) {
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.widgetWithText(TextField, 'Note'), text);
  await tester.tap(insert);
  await settleUntil(tester, working, () => workingText(working).contains(text));
}

final _session = _Screen(
  name: 'session screen',
  build: sessionScreen,
  planted: (text) => sessionTsv(notes: text),
  otherKind: notesTsv,
  blank: () => sessionTsv().split('\n').first,
  recoveryTitle: 'Unfinished session found',
  recoveredCount: '1 blocks',
  entryStep: () => find.text('Insert recording block').hitTestable(),
  opensOnEntryStep: false,
  opened: (file) => 'Opened $file (1 rows, next block 1, append 2).',
  rejectsOther: (file) =>
      '$file is an annotations (notes) file; this view needs a programming '
      'session.',
  entryFailed: 'Could not save this entry: ',
  filedHere: 'The visit is filed there as soon as the first block is inserted.',
  add: addSessionEntry,
  insertLabel: 'Insert baseline',
  stepLabel: 'Initial configuration',
  textLabel: null,
  pickerFailed: (e) => 'Could not open the file picker. ($e)',
  askWhat: 'this visit',
  newSnack: 'New session: ',
  collision: (file) =>
      'That dataset already holds $file. This visit stays in the app. Export '
      'it under a different run.',
  sidecarTask: 'Deep brain stimulation programming.',
  sidecarHasBlocks: true,
  exportTsv: (tester) async {
    await tester.tap(find.text('Recording'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export TSV'));
  },
);

final _notes = _Screen(
  name: 'notes screen',
  build: () => const AnnotationsScreen(),
  planted: (text) => notesTsv(note: text),
  otherKind: sessionTsv,
  blank: () => notesTsv().split('\n').first,
  recoveryTitle: 'Unfinished notes found',
  recoveredCount: '1 notes',
  entryStep: () => find.text('Insert timestamped note').hitTestable(),
  opensOnEntryStep: true,
  opened: (file) => 'Opened $file (1 notes).',
  rejectsOther: (file) =>
      '$file is a programming session; this view needs an annotations '
      '(notes) file.',
  entryFailed: 'Could not save this note: ',
  filedHere: 'The notes are filed there as soon as the first note is added.',
  add: _addNote,
  insertLabel: 'Insert timestamped note',
  stepLabel: 'Notes',
  textLabel: 'Note',
  pickerFailed: (e) =>
      'Could not open the file picker. On Linux it needs the XDG desktop '
      'portal. ($e)',
  askWhat: 'these notes',
  newSnack: 'New notes file: ',
  collision: (file) =>
      'That dataset already holds $file. These notes stay in the app. Export '
      'them under a different run.',
  sidecarTask: 'Timestamped free-text clinical notes',
  sidecarHasBlocks: false,
  exportTsv: (tester) async {
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Data (TSV)'));
  },
);

Finder _fileStep() => find.text('Open existing TSV').hitTestable();

String _field(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

String _toSlashes(String path) => path.replaceAll('\\', '/');

List<File> _datasetTsvs(Directory root) {
  final base = _toSlashes(root.path);
  return root.listSync(recursive: true).whereType<File>().where((f) {
    final rel = _toSlashes(f.path).substring(base.length + 1);
    return rel.startsWith('sub-') &&
        rel.endsWith('.tsv') &&
        !rel.endsWith('_scans.tsv');
  }).toList();
}

String _basename(String path) => _toSlashes(path).split('/').last;

Future<String> _newIntoDataset(
  WidgetTester tester,
  Directory dataset, {
  String? sessionLabel,
}) async {
  await tester.tap(find.text('New'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Into a dataset'));
  await pumpUntilFound(tester, find.text('Start a dataset'));
  await tester.tap(find.text('Start a dataset'));
  await tester.pumpAndSettle();
  if (sessionLabel != null) {
    await tester.enterText(
      find.widgetWithText(TextField, 'ses-'),
      sessionLabel,
    );
    await tester.pump();
  }
  await tester.tap(find.text('Use'));
  await tester.pumpAndSettle();
  final filedAs = tester.widget<Text>(
    find.byWidgetPredicate(
      (w) => w is Text && (w.data ?? '').startsWith('  sub-'),
    ),
  );
  await tester.tap(find.text('Record here'));
  await pumpUntilFound(tester, find.textContaining('Recording into'));
  await tester.pumpAndSettle();
  return filedAs.data!.trim();
}

Future<File> _exportedTsv(
  WidgetTester tester,
  _Screen s,
  Directory working,
  Directory saved,
  Directory cache, {
  Set<String> known = const {},
}) async {
  await s.exportTsv(tester);
  List<File> fresh() => saved
      .listSync()
      .whereType<File>()
      .where(
        (f) => f.path.endsWith('.tsv') && !known.contains(_basename(f.path)),
      )
      .toList();
  await settleUntil(
    tester,
    working,
    () =>
        fresh().isNotEmpty &&
        !cache
            .listSync(recursive: true)
            .any((e) => e is Directory && e.path.contains('export-')),
  );
  return fresh().single;
}

void _expectSidecar(_Screen s, File tsv) {
  final sidecar = jsonAt(tsv.path.replaceFirst(RegExp(r'\.tsv$'), '.json'));
  expect(sidecar['TaskDescription'], startsWith(s.sidecarTask));
  expect(sidecar.containsKey('block_id'), s.sidecarHasBlocks);
  expect(sidecar.containsKey('notes'), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final s in [_session, _notes]) {
    group('the ${s.name}', () {
      group('unfinished work', () {
        Future<void> found(WidgetTester tester) async {
          await s.show(tester);
          await pumpUntilFound(tester, find.text(s.recoveryTitle));
          await tester.pumpAndSettle();
          expect(
            find.text(
              '$_recoveredName was left open with ${s.recoveredCount} '
              'recorded. They were saved as you went, and can be reopened '
              'here.',
            ),
            findsOneWidget,
          );
        }

        testWidgets('Reopen restores it, its labels and the right step', (
          tester,
        ) async {
          final dirs = useTempDirs();
          plantWork(dirs.working, _recoveredName, s.planted('recovered entry'));
          await found(tester);

          await tester.tap(find.text('Reopen'));
          await pumpUntilFound(
            tester,
            find.text(
              'Reopened $_recoveredName. Export it to save it outside the app.',
            ),
          );
          await tester.pumpAndSettle();

          expect(s.entryStep(), findsOneWidget);
          expect(_fileStep(), findsNothing);
          expect(find.textContaining('recovered entry'), findsWidgets);

          await s.toFileStep(tester);
          expect(_field(tester, 'Patient ID (sub-)'), '07');
          expect(_field(tester, 'Task (task-)'), 'tuning');
          expect(_field(tester, 'Run'), '03');
        });

        testWidgets('a reopened copy keeps recording into itself only', (
          tester,
        ) async {
          final dirs = useTempDirs();
          final planted = plantWork(
            dirs.working,
            _recoveredName,
            s.planted('recovered entry'),
          );
          await found(tester);
          await tester.tap(find.text('Reopen'));
          await pumpUntilFound(tester, find.textContaining('Reopened'));
          await tester.pumpAndSettle();

          await s.add(tester, dirs.working, 'after reopening');

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

        testWidgets('Discard deletes the copy and starts empty', (
          tester,
        ) async {
          final dirs = useTempDirs();
          final planted = plantWork(
            dirs.working,
            _recoveredName,
            s.planted('recovered entry'),
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
          expect(find.text(s.recoveryTitle), findsNothing);
          expect(find.textContaining('Reopened'), findsNothing);
          expect(_fileStep(), findsOneWidget);
        });

        testWidgets('dismissing the question keeps the copy untouched', (
          tester,
        ) async {
          final dirs = useTempDirs();
          final planted = plantWork(
            dirs.working,
            _recoveredName,
            s.planted('recovered entry'),
          );
          await found(tester);

          await tester.tapAt(const Offset(4, 4));
          await tester.pumpAndSettle();
          await awaitRecoveryCheck(tester);

          expect(find.text(s.recoveryTitle), findsNothing);
          expect(find.textContaining('Reopened'), findsNothing);
          expect(planted.readAsStringSync(), s.planted('recovered entry'));
        });

        testWidgets('copies of the other kind or without entries are not '
            'offered', (tester) async {
          final dirs = useTempDirs();
          plantWork(dirs.working, 'sub-01_task-other_beh.tsv', s.otherKind());
          plantWork(dirs.working, 'sub-02_task-empty_beh.tsv', s.blank());
          await s.show(tester);
          await awaitRecoveryCheck(tester);

          expect(find.byType(AlertDialog), findsNothing);
          expect(find.text(s.recoveryTitle), findsNothing);
        });

        testWidgets('skips such copies to offer the older usable one', (
          tester,
        ) async {
          final dirs = useTempDirs();
          final now = DateTime.now();
          plantWork(
            dirs.working,
            _recoveredName,
            s.planted('recovered entry'),
            modified: now.subtract(const Duration(hours: 3)),
          );
          plantWork(
            dirs.working,
            'sub-01_task-other_beh.tsv',
            s.otherKind(),
            modified: now.subtract(const Duration(hours: 2)),
          );
          plantWork(
            dirs.working,
            'sub-02_task-empty_beh.tsv',
            s.blank(),
            modified: now.subtract(const Duration(hours: 1)),
          );
          await s.show(tester);
          await pumpUntilFound(tester, find.text(s.recoveryTitle));
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
            ..writeAsStringSync(s.planted('opened entry'));
          final picker = useFakePicker()..file = pickedFile(file);
          await s.show(tester);
          return (dirs.working, dirs.saved, file, picker);
        }

        testWidgets('a file of the right kind loads and is written back to', (
          tester,
        ) async {
          final (working, _, file, _) = await prepare(tester);

          await tester.tap(find.text('Open existing TSV'));
          await pumpUntilFound(tester, find.text(s.opened(_openedName)));
          await tester.pumpAndSettle();

          expect(find.text(s.opened(_openedName)), findsOneWidget);
          expect(s.entryStep().evaluate().isNotEmpty, s.opensOnEntryStep);
          expect(_fileStep().evaluate().isNotEmpty, !s.opensOnEntryStep);
          await s.toFileStep(tester);
          expect(_field(tester, 'Patient ID (sub-)'), '08');
          expect(_field(tester, 'Task (task-)'), 'tuning');
          expect(_field(tester, 'Run'), '02');

          await s.add(tester, working, 'after opening');
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
            ..writeAsStringSync(s.otherKind());
          picker.file = pickedFile(other);

          await tester.tap(find.text('Open existing TSV'));
          await pumpUntilFound(tester, find.text(s.rejectsOther(_openedName)));
          await tester.pumpAndSettle();

          expect(find.text(s.rejectsOther(_openedName)), findsOneWidget);
          expect(find.textContaining('Opened '), findsNothing);
          expect(_fileStep(), findsOneWidget);
          expect(
            Directory('${working.path}/work').listSync().whereType<File>(),
            isEmpty,
          );

          await s.add(tester, working, 'after refusal');
          expect(other.readAsStringSync(), s.otherKind());
          expect(workingText(working), contains('after refusal'));
        });

        testWidgets('a picker that fails says so and changes nothing', (
          tester,
        ) async {
          final (working, _, _, picker) = await prepare(tester);
          picker.failure = Exception('no dialog');

          await tester.tap(find.text('Open existing TSV'));
          await pumpUntilFound(
            tester,
            find.text(s.pickerFailed('Exception: no dialog')),
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

          await tester.tap(find.text('Open existing TSV'));
          await pumpUntilFound(
            tester,
            find.text('Could not read $_openedName.'),
          );

          expect(find.textContaining('Opened '), findsNothing);
        });

        testWidgets('with entries recorded, the leave question comes first', (
          tester,
        ) async {
          final (working, _, file, _) = await prepare(tester);
          await s.add(tester, working, 'first entry');
          final oldCopy = Directory('${working.path}/work')
              .listSync()
              .whereType<File>()
              .single;
          await s.toFileStep(tester);

          await tester.tap(find.text('Open existing TSV'));
          await pumpUntilFound(tester, find.text(_guardTitle));
          await tester.pumpAndSettle();
          expect(find.text('Delete the only copy'), findsOneWidget);
          expect(find.textContaining('Opened '), findsNothing);

          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          await awaitRecoveryCheck(tester);
          expect(find.textContaining('Opened '), findsNothing);
          expect(oldCopy.readAsStringSync(), contains('first entry'));

          await tester.tap(find.text('Open existing TSV'));
          await pumpUntilFound(tester, find.text(_guardTitle));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete the only copy'));
          await pumpUntilFound(tester, find.text(s.opened(_openedName)));
          await tester.pumpAndSettle();

          expect(oldCopy.existsSync(), isFalse);
          expect(file.readAsStringSync(), s.planted('opened entry'));
        });
      });

      group('recording into a dataset', () {
        testWidgets('is filed at its BIDS path on the first entry', (
          tester,
        ) async {
          final dirs = useTempDirs();
          final dataset = Directory.systemTemp.createTempSync('dbs_dataset');
          addTearDown(() => removeQuietly(dataset));
          useFakePicker().directory = dataset.path;
          await s.show(tester);

          await _newIntoDataset(tester, dataset);

          expect(
            find.text('Recording into ${dataset.path}. ${s.filedHere}'),
            findsOneWidget,
          );
          expect(_datasetTsvs(dataset), isEmpty);
          expect(_fileStep(), findsNothing);

          await s.add(tester, dirs.working, 'dataset entry');
          await pumpUntilFound(tester, find.textContaining('Filed as '));

          final filed = _datasetTsvs(dataset).single;
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
          expect(find.text('Filed as $rel.'), findsOneWidget);
          expect(filed.readAsStringSync(), contains('dataset entry'));
          _expectSidecar(s, filed);

          await s.add(tester, dirs.working, 'second dataset entry');
          await settleUntil(
            tester,
            dirs.working,
            () => filed.readAsStringSync().contains('second dataset entry'),
          );
          expect(filed.readAsStringSync(), contains('dataset entry'));
          expect(_datasetTsvs(dataset), hasLength(1));
        });

        testWidgets('a name the dataset already holds is refused and kept in '
            'the app', (tester) async {
          final dirs = useTempDirs();
          final dataset = Directory.systemTemp.createTempSync('dbs_dataset');
          addTearDown(() => removeQuietly(dataset));
          useFakePicker().directory = dataset.path;
          await s.show(tester);
          final rel = await _newIntoDataset(tester, dataset);
          final taken = File('${dataset.path}/$rel')
            ..createSync(recursive: true)
            ..writeAsStringSync(s.planted('someone else'));

          await s.add(tester, dirs.working, 'dataset entry');
          await pumpUntilFound(
            tester,
            find.textContaining('That dataset already holds'),
          );

          expect(find.text(s.collision(_basename(rel))), findsOneWidget);
          expect(taken.readAsStringSync(), s.planted('someone else'));
          expect(workingText(dirs.working), contains('dataset entry'));
        });

        testWidgets('Open afterwards records into the opened file only', (
          tester,
        ) async {
          final dirs = useTempDirs();
          final dataset = Directory.systemTemp.createTempSync('dbs_dataset');
          addTearDown(() => removeQuietly(dataset));
          final picker = useFakePicker()..directory = dataset.path;
          final cache = useExportCache(tester);
          final loose = File('${dirs.saved.path}/$_openedName')
            ..writeAsStringSync(s.planted('opened entry'));
          await s.show(tester);
          await _newIntoDataset(tester, dataset, sessionLabel: 'visitA');
          await s.add(tester, dirs.working, 'dataset entry');
          await pumpUntilFound(tester, find.textContaining('Filed as '));
          final filed = _datasetTsvs(dataset).single;
          final filedText = filed.readAsStringSync();

          picker.file = pickedFile(loose);
          await s.toFileStep(tester);
          await tester.tap(find.text('Open existing TSV'));
          await pumpUntilFound(tester, find.text(_guardTitle));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Keep copy'));
          await pumpUntilFound(tester, find.text(s.opened(_openedName)));
          await tester.pumpAndSettle();
          await s.add(tester, dirs.working, 'after opening');
          await settleUntil(
            tester,
            dirs.working,
            () => loose.readAsStringSync().contains('after opening'),
          );

          expect(filed.readAsStringSync(), filedText);
          expect(_datasetTsvs(dataset), hasLength(1));
          final exported = await _exportedTsv(
            tester,
            s,
            dirs.working,
            dirs.saved,
            cache,
            known: {_openedName},
          );
          final today = BidsName.sessionStamp(DateTime.now());
          expect(_basename(exported.path), contains('_ses-${today}_'));
          expect(filed.path, contains('ses-visitA'));
        });
      });

      group('New', () {
        testWidgets('a loose file asks where, is announced and gets its '
            'sidecar', (tester) async {
          final dirs = useTempDirs();
          await s.show(tester);

          await tester.tap(find.text('New'));
          await tester.pumpAndSettle();
          expect(
            find.text('Where should ${s.askWhat} be saved?'),
            findsOneWidget,
          );
          expect(
            find.text(
              'A loose TSV goes wherever you choose. Into a dataset, it is '
              'filed at its BIDS path and the dataset index files are kept up '
              'to date as you record.',
            ),
            findsOneWidget,
          );
          await tester.tap(find.text('Loose TSV'));
          await pumpUntilFound(tester, find.textContaining(s.newSnack));
          await tester.pumpAndSettle();

          final created = dirs.saved.listSync().whereType<File>().singleWhere(
            (f) => f.path.endsWith('.tsv'),
          );
          expect(
            find.text(
              '${s.newSnack}${dirs.saved.path}/${_basename(created.path)}',
            ),
            findsOneWidget,
          );
          _expectSidecar(s, created);
        });

        testWidgets('a file that cannot be created keeps the only copy', (
          tester,
        ) async {
          final dirs = useTempDirs();
          await s.show(tester);
          await s.add(tester, dirs.working, 'first entry');
          final oldCopy = Directory('${dirs.working.path}/work')
              .listSync()
              .whereType<File>()
              .single;
          debugSaveDir = Directory('${dirs.saved.path}/missing');
          await s.toFileStep(tester);

          await tester.tap(find.text('New'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Loose TSV'));
          await pumpUntilFound(tester, find.text(_guardTitle));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Delete the only copy'));
          await pumpUntilFound(
            tester,
            find.textContaining('Could not start a new file: '),
          );
          await tester.pumpAndSettle();

          expect(find.textContaining(s.newSnack), findsNothing);
          expect(oldCopy.existsSync(), isTrue);
          expect(oldCopy.readAsStringSync(), contains('first entry'));
        });
      });

      group('Export', () {
        testWidgets('the TSV is named by its BIDS entities', (tester) async {
          final dirs = useTempDirs();
          final cache = useExportCache(tester);
          await s.show(tester);
          await s.add(tester, dirs.working, 'an entry');
          await s.toFileStep(tester);
          final subject = _field(tester, 'Patient ID (sub-)');
          final task = _field(tester, 'Task (task-)');
          final run = _field(tester, 'Run');
          await tester.tap(find.text(s.stepLabel));
          await tester.pumpAndSettle();

          final exported = await _exportedTsv(
            tester,
            s,
            dirs.working,
            dirs.saved,
            cache,
          );

          final today = BidsName.sessionStamp(DateTime.now());
          expect(
            _basename(exported.path),
            'sub-${subject.isEmpty ? 'unknown' : subject}_ses-${today}_'
            'task-${task}_run-${run}_beh.tsv',
          );
        });
      });

      group('the close guard', () {
        testWidgets('is set while the screen is open and cleared after', (
          tester,
        ) async {
          useTempDirs();
          await s.show(tester);
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
          await s.show(tester);

          final answer = activeSessionGuard!();
          await tester.pumpAndSettle();

          expect(await answer, isTrue);
          expect(find.byType(AlertDialog), findsNothing);
        });

        testWidgets('asks after an entry, and Cancel keeps the window open', (
          tester,
        ) async {
          final dirs = useTempDirs();
          await s.show(tester);
          await s.add(tester, dirs.working, 'an entry');

          final answer = activeSessionGuard!();
          await pumpUntilFound(tester, find.text(_guardTitle));
          await tester.pumpAndSettle();
          expect(find.text('Delete the only copy'), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          expect(await answer, isFalse);
          expect(find.text(_guardTitle), findsNothing);
          expect(workingText(dirs.working), contains('an entry'));
        });
      });

      group('a working folder that cannot be written', () {
        testWidgets('says the entry was not saved and warns on leaving', (
          tester,
        ) async {
          final dirs = useTempDirs();
          final blocker = File('${dirs.working.path}/not_a_folder')
            ..writeAsStringSync('in the way');
          debugWorkingDir = Directory(blocker.path);
          await s.show(tester);

          final insert = find.text(s.insertLabel).hitTestable();
          if (insert.evaluate().isEmpty) {
            await tester.tap(find.text(s.stepLabel));
            await tester.pumpAndSettle();
          }
          if (s.textLabel case final label?) {
            await tester.enterText(
              find.widgetWithText(TextField, label),
              'doomed note',
            );
          }
          await tester.ensureVisible(insert);
          await tester.tap(insert);
          await pumpUntilFound(tester, find.textContaining(s.entryFailed));
          await tester.pumpAndSettle();

          expect(find.textContaining(s.entryFailed), findsOneWidget);

          await tester.binding.handlePopRoute();
          await pumpUntilFound(tester, find.text('Entries could not be saved'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining(
              'The entries in this session could not be saved to disk and '
              'will be lost if you leave',
            ),
            findsOneWidget,
          );
          expect(find.text('Leave and lose them'), findsOneWidget);
          expect(find.text('Stay'), findsOneWidget);
        });
      });
    });
  }
}
