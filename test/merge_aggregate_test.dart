/// The combined table after a merge covers the whole dataset, the recorded
/// files it cannot include are reported, and the backups a folder merge leaves
/// are hidden from the BIDS validator.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dbs_annotator/app_info.dart';
import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/core/bids_dataset.dart';
import 'package:dbs_annotator/core/bids_merge.dart';
import 'package:dbs_annotator/core/tsv.dart';
import 'package:dbs_annotator/ui/bids_export.dart';
import 'package:dbs_annotator/ui/bids_merge_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _session = File(
  'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv',
).readAsStringSync();

const _aggregateTsv = '$aggregateDerivativeDir/$aggregateStem.tsv';
const _aggregateJson = '$aggregateDerivativeDir/$aggregateStem.json';
const _aggregateDescription =
    '$aggregateDerivativeDir/dataset_description.json';

BidsName _name(String subject, String session, {String task = 'programming'}) =>
    BidsName(subject: subject, session: session, task: task, run: '01');

String _path(BidsName n) => '${n.relativeDir}/${n.filename}';

/// A dataset holding one visit, `ses-a` of sub-01, and an aggregate that
/// covers only an earlier upload.
List<DatasetFile> _existing() => [
  (path: 'dataset_description.json', content: '{"Name": "Lab"}'),
  (path: 'README', content: 'Curated.'),
  (path: 'participants.tsv', content: 'participant_id\nsub-01\n'),
  (path: _path(_name('01', 'a')), content: _session),
  (path: _aggregateTsv, content: 'stale'),
  (path: _aggregateJson, content: 'stale'),
  (path: _aggregateDescription, content: '{"Name": "Curated derivative"}'),
];

const _otherLab = 'onset\tduration\ttrial_type\n1\t2\ta\n';
const _notATable = 'not\ta\tsession\n1\t2\t3\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = jsonDecode(
    File('schema/tsv_schema.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  List<DatasetFile> incomingVisit(BidsName name, {String? tsv}) =>
      buildBidsDataset(
        [
          datasetEntry(
            name: name,
            tsv: tsv ?? _session,
            contract: contract,
            kind: 'session_tsv',
            acqTime: '2026-03-10T10:00:00+00:00',
          ),
        ],
        appName: appName,
        appVersion: appVersion,
        repoUrl: repoUrl,
      );

  MergePlan planFor(List<DatasetFile> existing, List<DatasetFile> incoming) =>
      withRebuiltAggregate(
        existing,
        planBidsMerge(existing, incoming),
        contract,
      );

  Set<String> sourceFiles(String tsv) => {
    for (final r in parseTsvRecords(tsv)) r['source_file']!,
  };

  group('folder merge', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('dbs_merge_agg');
      for (final f in _existing()) {
        File('${root.path}/${f.path}')
          ..createSync(recursive: true)
          ..writeAsStringSync(f.content);
      }
    });
    tearDown(() => root.deleteSync(recursive: true));

    String read(String rel) => File('${root.path}/$rel').readAsStringSync();

    void put(String rel, String content) => File('${root.path}/$rel')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);

    List<String> backups() => [
      for (final e in root.listSync(recursive: true))
        if (e.path.contains('.bak-')) e.path.split(RegExp(r'[\\/]')).last,
    ];

    Future<MergePlan> merge(List<DatasetFile> incoming) async {
      final existing = await readDatasetDirectory(root.path);
      final plan = planFor(existing, incoming);
      await applyMergeToDirectory(root.path, plan);
      return plan;
    }

    test('the combined table covers existing and new sessions', () async {
      final incoming = _name('02', 'b');
      await merge(incomingVisit(incoming));

      expect(sourceFiles(read(_aggregateTsv)), {
        _name('01', 'a').filename,
        incoming.filename,
      });
    });

    test('a stale table and sidecar are replaced and backed up', () async {
      final plan = await merge(incomingVisit(_name('02', 'b')));

      expect(plan.rebuilt, [_aggregateTsv, _aggregateJson]);
      expect(plan.added, isNot(contains(_aggregateTsv)));
      expect(plan.rowMerged, isNot(contains(_aggregateTsv)));
      expect(read(_aggregateJson), isNot('stale'));
      expect(
        backups(),
        unorderedEquals([
          startsWith('$aggregateStem.tsv.bak-'),
          startsWith('$aggregateStem.json.bak-'),
          startsWith('participants.tsv.bak-'),
        ]),
      );
      final stale = Directory('${root.path}/$aggregateDerivativeDir')
          .listSync()
          .firstWhere((e) => e.path.contains('.tsv.bak-'));
      expect((stale as File).readAsStringSync(), 'stale');
    });

    test('a table that is new is added, not rebuilt', () async {
      File('${root.path}/$_aggregateTsv').deleteSync();
      File('${root.path}/$_aggregateJson').deleteSync();
      final plan = await merge(incomingVisit(_name('02', 'b')));

      expect(plan.added, containsAll([_aggregateTsv, _aggregateJson]));
      expect(plan.rebuilt, isEmpty);
    });

    test('a table that cannot be rebuilt is left as it is and listed', () {
      final existing = [
        for (final f in _existing())
          if (!f.path.startsWith('sub-')) f,
      ];
      final plan = planFor(existing, const []);

      expect(plan.write, isEmpty);
      expect(plan.rebuilt, isEmpty);
      expect(
        plan.keptAsIs,
        containsAll([_aggregateTsv, _aggregateJson, _aggregateDescription]),
      );
      expect(
        shownUnwritten(plan).unchanged,
        contains('$aggregateDerivativeDir/'),
      );
    });

    test('a table equal to the rebuilt one stays listed as unchanged', () {
      final rebuilt = planFor(_existing(), const []).write;
      String content(String p) =>
          rebuilt.firstWhere((f) => f.path == p).content;
      final current = [
        for (final f in _existing())
          if (f.path == _aggregateTsv || f.path == _aggregateJson)
            (path: f.path, content: content(f.path))
          else
            f,
      ];

      final same = planFor(current, const []);
      expect(same.write, isEmpty);
      expect(
        same.keptAsIs,
        containsAll([_aggregateTsv, _aggregateJson, _aggregateDescription]),
      );

      final oneStale = [
        for (final f in current)
          if (f.path == _aggregateTsv) (path: f.path, content: 'stale') else f,
      ];
      final partial = planFor(oneStale, const []);
      expect(partial.rebuilt, [_aggregateTsv]);
      expect(partial.keptAsIs, isNot(contains(_aggregateTsv)));
    });

    test('a rebuild lists no aggregate file as left unchanged', () {
      final plan = planFor(_existing(), incomingVisit(_name('02', 'b')));

      expect(plan.rebuilt, [_aggregateTsv, _aggregateJson]);
      expect(
        plan.keptAsIs.where((p) => p.startsWith(aggregateDerivativeDir)),
        isEmpty,
      );
      expect(
        shownUnwritten(plan).unchanged,
        isNot(contains('$aggregateDerivativeDir/')),
      );
    });

    test('the plan is described with the rebuilt files apart', () {
      final plan = planFor(_existing(), incomingVisit(_name('02', 'b')));
      final text = describeMergePlan(plan);
      expect(text, contains('2 rebuilt'));
      expect(text, contains('1 index file gaining rows'));
    });

    test('the derivative description stays as the lab left it', () async {
      await merge(incomingVisit(_name('02', 'b')));
      expect(read(_aggregateDescription), '{"Name": "Curated derivative"}');
    });

    test('raw recordings are never overwritten', () async {
      final raw = _path(_name('01', 'a'));
      final plan = await merge(incomingVisit(_name('01', 'a'), tsv: 'other'));

      expect(plan.refused, contains(raw));
      expect(read(raw), _session);
      expect(sourceFiles(read(_aggregateTsv)), {_name('01', 'a').filename});
    });

    test(
      'a recorded file that is not a session is left out and named',
      () async {
        final bad = _path(_name('03', 'c'));
        put(bad, _notATable);
        final plan = await merge(incomingVisit(_name('02', 'b')));

        expect(plan.leftOut.map((f) => f.path), [bad]);
        expect(plan.leftOut.single.reason, contains('not readable'));
        expect(plan.unread, isEmpty);
        expect(leftOutNotice(plan.leftOut), contains(bad));
        expect(sourceFiles(read(_aggregateTsv)), {
          _name('01', 'a').filename,
          _name('02', 'b').filename,
        });
        expect(read(bad), _notATable);
      },
    );

    test('a recorded file that was not read as text is left out', () {
      final unread = _path(_name('03', 'c'));
      final existing = [
        ..._existing(),
        (path: unread, content: kUnreadContent),
      ];
      final plan = planFor(existing, incomingVisit(_name('02', 'b')));
      expect(plan.leftOut.map((f) => f.path), [unread]);
      expect(plan.leftOut.single.reason, 'could not be read as text');
    });

    test('another lab\'s beh file is not reported, nor included', () async {
      final other = _path(_name('04', 'd', task: 'nback'));
      put(other, _otherLab);
      final unreadOther = _path(_name('05', 'e', task: 'nback'));
      final existing = [
        ...await readDatasetDirectory(root.path),
        (path: unreadOther, content: kUnreadContent),
      ];
      final plan = planFor(existing, incomingVisit(_name('02', 'b')));

      expect(plan.leftOut, isEmpty);
      expect(plan.unread, isEmpty);
      final table = plan.write.firstWhere((f) => f.path == _aggregateTsv);
      expect(sourceFiles(table.content), {
        _name('01', 'a').filename,
        _name('02', 'b').filename,
      });
    });

    test('a file with no ses- entity is left out with its path', () async {
      const noSession = 'sub-05/beh/sub-05_task-programming_beh.tsv';
      put(noSession, _session);
      final plan = await merge(incomingVisit(_name('02', 'b')));

      expect(plan.leftOut.map((f) => f.path), [noSession]);
      expect(plan.leftOut.single.reason, contains('ses-'));
    });

    test('a repeated file name leaves out the later copy', () async {
      final copy = 'sub-01/ses-z/beh/${_name('01', 'a').filename}';
      put(copy, _session);
      final plan = await merge(incomingVisit(_name('02', 'b')));

      expect(plan.leftOut.map((f) => f.path), [copy]);
      expect(plan.leftOut.single.reason, contains('already included'));
    });

    test(
      'copies under old, sourcedata, code and dot-folders are ignored',
      () async {
        for (final folder in ['old', 'sourcedata', 'code', '.stash']) {
          put('$folder/${_path(_name('01', 'a'))}', _session);
        }
        final plan = await merge(incomingVisit(_name('02', 'b')));

        expect(plan.leftOut, isEmpty);
        expect(sourceFiles(read(_aggregateTsv)), {
          _name('01', 'a').filename,
          _name('02', 'b').filename,
        });
      },
    );

    group('a file under a custom task', () {
      final path = _path(_name('06', 'f', task: 'rest'));
      final sidecarPath = path.replaceFirst(RegExp(r'\.tsv$'), '.json');
      final ours = jsonEncode({
        'GeneratedBy': [
          {'Name': appName, 'Version': '1'},
        ],
      });
      final theirs = jsonEncode({
        'GeneratedBy': [
          {'Name': 'SomeOtherTool', 'Version': '1'},
        ],
      });

      MergePlan planWith(String tsv, String? sidecar) => planFor([
        ..._existing(),
        (path: path, content: tsv),
        if (sidecar != null) (path: sidecarPath, content: sidecar),
      ], incomingVisit(_name('02', 'b')));

      test('is reported when this app wrote its sidecar', () {
        final plan = planWith(_notATable, ours);
        expect(plan.leftOut.map((f) => f.path), [path]);
        expect(plan.leftOut.single.reason, contains('not readable'));
      });

      test('is reported as unreadable when it was not read as text', () {
        final plan = planWith(kUnreadContent, ours);
        expect(plan.leftOut.single.reason, 'could not be read as text');
      });

      test('is not reported without this app\'s sidecar', () {
        expect(planWith(_notATable, theirs).leftOut, isEmpty);
        expect(planWith(_notATable, null).leftOut, isEmpty);
        expect(planWith(_notATable, 'not json').leftOut, isEmpty);
      });
    });

    test('a name without ses- twice is never called already included', () {
      const first = 'sub-05/beh/sub-05_task-programming_beh.tsv';
      const second = 'sub-06/beh/sub-05_task-programming_beh.tsv';
      final existing = [
        ..._existing(),
        (path: first, content: _session),
        (path: second, content: _session),
      ];
      final plan = planFor(existing, incomingVisit(_name('02', 'b')));

      expect(plan.leftOut.map((f) => f.path), unorderedEquals([first, second]));
      for (final f in plan.leftOut) {
        expect(f.reason, contains('ses-'));
      }
    });

    test('.bidsignore is created when a backup is written', () async {
      await merge(incomingVisit(_name('02', 'b')));
      expect(read('.bidsignore'), '$kBackupIgnoreLine\n');
    });

    test('no backup, no .bidsignore', () async {
      File('${root.path}/$_aggregateTsv').deleteSync();
      File('${root.path}/$_aggregateJson').deleteSync();
      File('${root.path}/participants.tsv').deleteSync();
      await merge(incomingVisit(_name('02', 'b')));
      expect(backups(), isEmpty);
      expect(File('${root.path}/.bidsignore').existsSync(), isFalse);
    });

    test('an existing .bidsignore gains the line and keeps its own', () async {
      File('${root.path}/.bidsignore').writeAsStringSync('*_scratch*\nnotes/');
      await merge(incomingVisit(_name('02', 'b')));
      expect(read('.bidsignore'), '*_scratch*\nnotes/\n$kBackupIgnoreLine\n');
    });

    test('a .bidsignore that has the line is left alone', () async {
      const own = '# mine\n$kBackupIgnoreLine\nextra\n';
      File('${root.path}/.bidsignore').writeAsStringSync(own);
      await merge(incomingVisit(_name('02', 'b')));
      expect(read('.bidsignore'), own);
    });

    test('a .bidsignore that is not UTF-8 does not abort the merge', () async {
      final bytes = [0xff, 0xfe, 0x80, 0x0a];
      File('${root.path}/.bidsignore').writeAsBytesSync(bytes);
      final existing = await readDatasetDirectory(root.path);
      final plan = planFor(existing, incomingVisit(_name('02', 'b')));

      final warning = await applyMergeToDirectory(root.path, plan);

      expect(warning, kBidsignoreWarning);
      expect(File('${root.path}/.bidsignore').readAsBytesSync(), bytes);
      expect(sourceFiles(read(_aggregateTsv)), hasLength(2));
      expect(backups(), isNotEmpty);
    });

    test('a .bidsignore that cannot be written does not abort', () async {
      Directory('${root.path}/.bidsignore').createSync();
      final existing = await readDatasetDirectory(root.path);
      final plan = planFor(existing, incomingVisit(_name('02', 'b')));

      expect(await ensureBackupsIgnored(root.path), isFalse);
      expect(File('${root.path}/.bidsignore.tmp').existsSync(), isFalse);
      expect(await applyMergeToDirectory(root.path, plan), kBidsignoreWarning);
      expect(sourceFiles(read(_aggregateTsv)), hasLength(2));
    });

    test(
      'the warning is passed on when a table save cannot hide backups',
      () async {
        File('${root.path}/.bidsignore').writeAsBytesSync([0xff, 0xfe]);
        final written = await writeAggregateInto(
          root.path,
          tsv: 'new',
          sidecar: '{}',
        );

        expect(written.warning, kBidsignoreWarning);
        expect(File(written.path).readAsStringSync(), 'new');
      },
    );

    test('merging the same visit again changes nothing', () async {
      await merge(incomingVisit(_name('02', 'b')));
      final again = planFor(
        await readDatasetDirectory(root.path),
        incomingVisit(_name('02', 'b')),
      );
      expect(again.write, isEmpty);
    });
  });

  group('zip merge', () {
    Uint8List zipOf(List<DatasetFile> files, {Map<String, String>? extra}) =>
        textZip({for (final f in files) f.path: f.content, ...?extra});

    test('the rebuilt table replaces the one in the zip', () {
      final source = zipOf(_existing());
      final existing = readDatasetZip(source);
      final incoming = incomingVisit(_name('02', 'b'));
      final plan = planFor(existing, incoming);

      final merged = ZipDecoder().decodeBytes(mergedZip(source, plan));
      final tsv = utf8.decode(merged.findFile(_aggregateTsv)!.readBytes()!);
      expect(sourceFiles(tsv), {
        _name('01', 'a').filename,
        _name('02', 'b').filename,
      });
      expect(
        utf8.decode(merged.findFile(_aggregateDescription)!.readBytes()!),
        '{"Name": "Curated derivative"}',
      );
      expect(
        utf8.decode(merged.findFile(_path(_name('01', 'a')))!.readBytes()!),
        _session,
      );
    });

    test('a .bidsignore in the zip is kept byte for byte', () {
      const own = '*_scratch*\n';
      final source = zipOf(_existing(), extra: {'.bidsignore': own});
      final plan = planFor(
        readDatasetZip(source),
        incomingVisit(_name('02', 'b')),
      );

      expect(plan.write.map((f) => f.path), isNot(contains('.bidsignore')));
      final merged = ZipDecoder().decodeBytes(mergedZip(source, plan));
      expect(utf8.decode(merged.findFile('.bidsignore')!.readBytes()!), own);
    });

    test('a zip with no table gets one', () {
      final source = zipOf([
        for (final f in _existing())
          if (!f.path.startsWith(aggregateDerivativeDir)) f,
      ]);
      final plan = planFor(
        readDatasetZip(source),
        incomingVisit(_name('02', 'b')),
      );
      expect(
        plan.added,
        containsAll([_aggregateTsv, _aggregateJson, _aggregateDescription]),
      );
    });
  });

  group('the confirmation', () {
    Future<void> open(
      WidgetTester tester,
      MergePlan plan, {
      bool keepsBackups = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => confirmMerge(
                context,
                plan,
                'target',
                keepsBackups: keepsBackups,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    final plan = planFor(_existing(), incomingVisit(_name('02', 'b')));

    testWidgets('a folder merge says the previous copy is kept', (
      tester,
    ) async {
      await open(tester, plan);
      expect(
        find.text('Rebuilt (previous copy kept as .bak-...) (2)'),
        findsOneWidget,
      );
      expect(find.textContaining('Gaining rows (1)'), findsOneWidget);
    });

    testWidgets('a zip merge says only that the table is rebuilt', (
      tester,
    ) async {
      await open(tester, plan, keepsBackups: false);
      expect(find.text('Rebuilt (2)'), findsOneWidget);
    });

    testWidgets('the rule says the table is rebuilt only when it is written', (
      tester,
    ) async {
      await open(tester, plan);
      expect(find.textContaining('is rebuilt from every session'), findsOne);
      expect(find.textContaining('is left as it is'), findsNothing);
    });

    testWidgets('a table that is not written is said to be left as it is', (
      tester,
    ) async {
      final existing = [
        for (final f in _existing())
          if (!f.path.startsWith('sub-')) f,
      ];
      await open(tester, planFor(existing, const []));
      expect(find.textContaining('is left as it is'), findsOneWidget);
      expect(
        find.textContaining('is rebuilt from every session'),
        findsNothing,
      );
    });

    testWidgets('a rebuilt sidecar alone counts as a rebuilt table', (
      tester,
    ) async {
      final rebuilt = planFor(_existing(), const []).write;
      String content(String p) =>
          rebuilt.firstWhere((f) => f.path == p).content;
      final staleSidecar = [
        for (final f in _existing())
          if (f.path == _aggregateTsv)
            (path: f.path, content: content(f.path))
          else if (f.path == _aggregateJson)
            (path: f.path, content: '{}')
          else
            f,
      ];
      final plan = planFor(staleSidecar, const []);
      expect(plan.rebuilt, [_aggregateJson]);
      await open(tester, plan);
      expect(find.textContaining('is rebuilt from every session'), findsOne);
      expect(find.textContaining('is not created'), findsNothing);
    });

    testWidgets('a current table with no description is left as it is', (
      tester,
    ) async {
      final rebuilt = planFor(_existing(), const []).write;
      String content(String p) =>
          rebuilt.firstWhere((f) => f.path == p).content;
      final noDescription = [
        for (final f in _existing())
          if (f.path == _aggregateTsv || f.path == _aggregateJson)
            (path: f.path, content: content(f.path))
          else if (f.path != _aggregateDescription)
            f,
      ];
      final plan = planFor(noDescription, const []);
      expect(plan.added, [_aggregateDescription]);
      expect(
        shownUnwritten(plan).unchanged,
        isNot(contains('$aggregateDerivativeDir/')),
      );
      await open(tester, plan);
      expect(find.textContaining('is left as it is'), findsOneWidget);
      expect(find.textContaining('is not created'), findsNothing);
    });

    testWidgets('a first table in the dataset is said to be created', (
      tester,
    ) async {
      final noTable = [
        for (final f in _existing())
          if (!f.path.startsWith(aggregateDerivativeDir)) f,
      ];
      final plan = planFor(noTable, const []);
      expect(plan.added, contains(_aggregateTsv));
      await open(tester, plan);
      expect(
        find.textContaining('is created from every session'),
        findsOneWidget,
      );
      expect(find.textContaining('is rebuilt'), findsNothing);
    });

    testWidgets('no table and none written says it is not created', (
      tester,
    ) async {
      final existing = [
        for (final f in _existing())
          if (!f.path.startsWith('sub-') &&
              !f.path.startsWith(aggregateDerivativeDir))
            f,
      ];
      await open(tester, planFor(existing, const []));
      expect(
        find.textContaining('is not created, because no recording'),
        findsOneWidget,
      );
      expect(find.textContaining('is left as it is'), findsNothing);
    });

    testWidgets('files left out are listed, and the index rule stays', (
      tester,
    ) async {
      final withLeftOut = (
        write: plan.write,
        added: plan.added,
        rowMerged: plan.rowMerged,
        rebuilt: plan.rebuilt,
        keptAsIs: plan.keptAsIs,
        unread: const <String>[],
        refused: plan.refused,
        leftOut: const [(path: 'sub-09/x.tsv', reason: 'no ses- entity')],
      );
      await open(tester, withLeftOut);
      expect(find.textContaining('sub-09/x.tsv (no ses- entity)'), findsOne);
      expect(find.textContaining('row in that session'), findsOneWidget);
    });
  });

  group('recording into a dataset', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('dbs_rec_agg'));
    tearDown(() => root.deleteSync(recursive: true));

    Future<({String path, List<String> unread, String? warning})?> record(
      String subject,
      String session,
    ) {
      return fileIntoDataset(
        root: root.path,
        name: _name(subject, session),
        tsv: _session,
        kind: 'session_tsv',
        acqTime: '2026-02-03T09:00:00+00:00',
      );
    }

    test('recording leaves the combined table as it was', () async {
      File('${root.path}/dataset_description.json').writeAsStringSync('{}');
      final table = File('${root.path}/$_aggregateTsv')
        ..createSync(recursive: true)
        ..writeAsStringSync('stale');
      final filed = await record('01', 'a');

      expect(filed, isNotNull);
      expect(File(filed!.path).existsSync(), isTrue);
      expect(filed.path, endsWith(_path(_name('01', 'a'))));
      expect(table.readAsStringSync(), 'stale');
      expect(File('${root.path}/$_aggregateJson').existsSync(), isFalse);
    });
  });
}
