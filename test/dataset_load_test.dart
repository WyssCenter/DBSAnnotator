/// Loading a BIDS dataset into Reports, and the combined table written back
/// into it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/bids_dataset.dart';
import 'package:dbs_annotator/core/bids_merge.dart';
import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/session/tsv_kind.dart';
import 'package:dbs_annotator/report/upload_actions.dart';
import 'package:dbs_annotator/ui/bids_merge_ui.dart';
import 'package:dbs_annotator/ui/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _session = File(
  'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv',
).readAsStringSync();

String _beh(String sub, String ses, String task) =>
    'sub-$sub/ses-$ses/beh/sub-${sub}_ses-${ses}_task-${task}_run-01_beh.tsv';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('recordedFiles', () {
    test('keeps recorded TSVs by participant and nothing else', () {
      final found = recordedFiles([
        (path: _beh('02', 'a', 'programming'), content: ''),
        (path: _beh('01', 'a', 'notes'), content: ''),
        (
          path:
              'sub-01/ses-b/beh/sub-01_ses-b_task-programming_run-01_events.tsv',
          content: '',
        ),
        (
          path: _beh('01', 'a', 'notes').replaceAll('.tsv', '.json'),
          content: '',
        ),
        (path: 'sub-01/ses-a/anat/sub-01_ses-a_T1w.nii.gz', content: ''),
        (path: 'derivatives/x/${_beh('03', 'a', 'programming')}', content: ''),
        (path: 'participants.tsv', content: ''),
      ]);
      expect(found.keys, ['01', '02']);
      expect(found['01'], hasLength(2));
    });

    test('a folder dataset is read from its root, not from copies', () {
      final found = recordedFiles([
        for (final dir in [
          'old',
          'backup',
          'sourcedata',
          'code',
          'derivatives',
          '.hidden',
        ])
          (path: '$dir/${_beh('09', 'a', 'programming')}', content: ''),
        (path: _beh('01', 'a', 'programming'), content: ''),
      ]);
      expect(found.keys, ['01']);
    });

    group('in a zip', () {
      test('finds the dataset under one or several wrapper folders', () {
        final found = recordedFiles([
          (path: 'study/${_beh('01', 'a', 'programming')}', content: ''),
          (path: 'out/study/${_beh('02', 'a', 'programming')}', content: ''),
          (path: _beh('03', 'a', 'programming'), content: ''),
        ], inZip: true);
        expect(found.keys, ['01', '02', '03']);
      });

      test('leaves out copies, derived data, dot-folders and __MACOSX', () {
        final found = recordedFiles([
          for (final dir in [
            'sourcedata',
            'code',
            'derivatives',
            '.hidden',
            '__MACOSX',
            'study/__MACOSX',
            'study/sourcedata',
            '__MACOSX/study',
          ])
            (path: '$dir/${_beh('09', 'a', 'programming')}', content: ''),
          (path: 'study/${_beh('01', 'a', 'programming')}', content: ''),
        ], inZip: true);
        expect(found.keys, ['01']);
      });

      test('reads only the folder holding dataset_description.json', () {
        const description = 'dataset_description.json';
        for (final wrapper in ['', 'study/']) {
          final found = recordedFiles([
            (path: '$wrapper$description', content: '{}'),
            (path: '${wrapper}old/$description', content: '{}'),
            (path: '$wrapper${_beh('01', 'a', 'programming')}', content: ''),
            for (final dir in ['old', 'backup', 'study/old'])
              (
                path: '$wrapper$dir/${_beh('09', 'a', 'programming')}',
                content: '',
              ),
          ], inZip: true);
          expect(found.keys, ['01'], reason: 'wrapper "$wrapper"');
        }
      });

      test('a description inside __MACOSX does not become the root', () {
        final found = recordedFiles([
          (path: '__MACOSX/dataset_description.json', content: ''),
          (path: 'study/dataset_description.json', content: '{}'),
          (path: 'study/${_beh('01', 'a', 'programming')}', content: ''),
        ], inZip: true);
        expect(found.keys, ['01']);
      });

      test('datasets side by side at the shallowest depth all load', () {
        final found = recordedFiles([
          (path: 'siteA/dataset_description.json', content: '{}'),
          (path: 'siteB/dataset_description.json', content: '{}'),
          (path: 'siteB/old/dataset_description.json', content: '{}'),
          (path: 'siteA/${_beh('01', 'a', 'programming')}', content: ''),
          (path: 'siteB/${_beh('02', 'a', 'programming')}', content: ''),
          (path: 'siteB/old/${_beh('09', 'a', 'programming')}', content: ''),
        ], inZip: true);
        expect(found.keys, ['01', '02']);
      });

      test('entries starting with ./ are matched without it', () {
        final found = recordedFiles([
          (path: './dataset_description.json', content: '{}'),
          (path: './${_beh('01', 'a', 'programming')}', content: ''),
          (path: './old/${_beh('09', 'a', 'programming')}', content: ''),
        ], inZip: true);
        expect(found.keys, ['01']);
        expect(
          recordedFiles([
            (path: './${_beh('01', 'a', 'programming')}', content: ''),
          ], inZip: true).keys,
          ['01'],
        );
      });

      test('without a description any wrapper folder is accepted', () {
        final found = recordedFiles([
          (path: 'study/${_beh('01', 'a', 'programming')}', content: ''),
          (path: 'old/${_beh('02', 'a', 'programming')}', content: ''),
          (path: 'derivatives/${_beh('09', 'a', 'programming')}', content: ''),
        ], inZip: true);
        expect(found.keys, ['01', '02']);
      });
    });

    test('dot files such as macOS AppleDouble copies are skipped', () {
      final dot = _beh(
        '09',
        'a',
        'programming',
      ).replaceFirst('sub-09_ses-a_task', '._sub-09_ses-a_task');
      expect(
        recordedFiles([
          (path: dot, content: ''),
          (path: _beh('01', 'a', 'programming'), content: ''),
        ]).keys,
        ['01'],
      );
      expect(
        recordedFiles([
          (path: 'study/$dot', content: ''),
          (path: 'study/${_beh('01', 'a', 'programming')}', content: ''),
        ], inZip: true).keys,
        ['01'],
      );
    });
  });

  test('classifyUpload sorts by header, not by name', () {
    expect(classifyUpload('a.tsv', _session).file?.kind, TsvKind.programming);
    expect(
      classifyUpload('b.tsv', 'acq_time\tnotes\n').file?.kind,
      TsvKind.notes,
    );
    final wrong = classifyUpload('c.tsv', 'x\ty\n');
    expect(wrong.file, isNull);
    expect(wrong.rejected, isNotNull);
  });

  group('writeAggregateInto', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('dbs_agg'));
    tearDown(() => root.deleteSync(recursive: true));

    String dir() => '${root.path}/$aggregateDerivativeDir';

    test(
      'lands the table, its sidecar and the derivative description',
      () async {
        final written = await writeAggregateInto(
          root.path,
          tsv: 't1',
          sidecar: '{}',
        );
        final path = written.path;
        expect(path, '${dir()}/$aggregateStem.tsv');
        expect(written.warning, isNull);
        expect(File(path).readAsStringSync(), 't1');
        expect(File('${dir()}/$aggregateStem.json').existsSync(), isTrue);
        final description =
            jsonDecode(
                  File('${dir()}/dataset_description.json').readAsStringSync(),
                )
                as Map<String, dynamic>;
        expect(description['DatasetType'], 'derivative');
      },
    );

    test('a newer table replaces the old one and keeps it aside', () async {
      final raw = File('${root.path}/${_beh('01', 'a', 'programming')}')
        ..createSync(recursive: true)
        ..writeAsStringSync(_session);
      await writeAggregateInto(root.path, tsv: 't1', sidecar: '{}');
      await writeAggregateInto(root.path, tsv: 't2', sidecar: '{}');

      expect(File('${dir()}/$aggregateStem.tsv').readAsStringSync(), 't2');
      final kept = Directory(dir())
          .listSync()
          .map((e) => e.path.split(RegExp(r'[\\/]')).last)
          .where((n) => n.contains('.bak-'))
          .toList();
      expect(kept, hasLength(1), reason: 'only the table changed: $kept');
      expect(kept.single, startsWith('$aggregateStem.tsv.bak-'));
      expect(raw.readAsStringSync(), _session, reason: 'raw files untouched');
    });
  });

  testWidgets('loading a dataset fills the list with the chosen participants', (
    tester,
  ) async {
    debugDataset = (
      root: 'C:/Studies/OCD-DBS',
      files: [
        (path: _beh('01', 'a', 'programming'), content: _session),
        (path: _beh('01', 'b', 'programming'), content: _session),
        (path: _beh('02', 'a', 'programming'), content: _session),
        (path: 'dataset_description.json', content: '{}'),
      ],
    );
    addTearDown(() => debugDataset = null);
    await tester.binding.setSurfaceSize(const Size(1400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final catalog = ElectrodeCatalog.fromJson(
      jsonDecode(File('schema/electrode_models.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    await tester.pumpWidget(MaterialApp(home: ReportsScreen(catalog: catalog)));

    await tester.tap(find.text('Load from dataset'));
    await tester.pumpAndSettle();
    expect(find.text('Load which participants?'), findsOneWidget);
    await tester.tap(find.text('sub-02'));
    await tester.pump();
    await tester.tap(find.text('Load'));
    await tester.pumpAndSettle();

    expect(find.textContaining('sub-01_ses-a_'), findsOneWidget);
    expect(find.textContaining('sub-01_ses-b_'), findsOneWidget);
    expect(find.textContaining('sub-02_'), findsNothing);
    expect(find.text('Needs two or more TSVs.'), findsNothing);
  });

  testWidgets('a zip description that cannot be read still marks the root', (
    tester,
  ) async {
    debugDataset = (
      root: null,
      files: [
        (path: 'study/dataset_description.json', content: kUnreadContent),
        (path: 'study/${_beh('01', 'a', 'programming')}', content: _session),
        (
          path: 'study/old/${_beh('09', 'a', 'programming')}',
          content: _session,
        ),
        (path: 'other/${_beh('08', 'a', 'programming')}', content: _session),
      ],
    );
    addTearDown(() => debugDataset = null);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => loadDatasetTsvs(context, (_) {}),
            child: const Text('load'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('load'));
    await tester.pumpAndSettle();

    expect(find.text('sub-01'), findsOneWidget);
    expect(find.text('sub-09'), findsNothing);
    expect(find.text('sub-08'), findsNothing);
  });
}
