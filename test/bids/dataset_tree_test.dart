/// Write a real BIDS dataset tree to disk, for the validator to judge.
///
/// Opt-in: a plain `flutter test` skips it, so the working tree is never
/// dirtied. From the repo root:
///
/// ```powershell
/// $env:BIDS_DATASET_DIR = "build/bids-dataset"
/// flutter test test/bids/dataset_tree_test.dart
/// ```
///
/// BIDS compliance here is our reading of the specification, and the validator
/// is the only check on that reading. It is Deno-based and cannot run on this
/// machine, so the test writes the tree and CI validates it.
///
/// The shape is chosen to exercise what a single session cannot:
///  * two sessions of one subject, the only way `scans.tsv` grouping runs;
///  * a second subject, the only way `participants.tsv` gets more than one row
///    and the combined table's cross-subject path is reached;
///  * a notes file beside a programming file, so both sidecar kinds appear;
///  * the combined table as a derivative, whose placement is the one part of
///    this layout not yet confirmed against the spec.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/app_info.dart';
import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/core/bids_dataset.dart';
import 'package:dbs_annotator/core/bids_merge.dart';
import 'package:dbs_annotator/core/bids_sidecar.dart';
import 'package:dbs_annotator/core/session/aggregate.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/ui/bids_export.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the tree is written. Unset means "do nothing".
final String? _outDir = Platform.environment['BIDS_DATASET_DIR'];

const _fixture =
    'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv';

/// The four source files the tree is built from: the one committed fixture
/// with its dates shifted, since a second on-disk fixture per subject would
/// add maintenance for no extra coverage.
List<({BidsName name, String tsv, String kind})> _sources(String source) {
  BidsName programming(String subject, String session, String run) => BidsName(
    subject: subject,
    session: session,
    task: 'programming',
    run: run,
  );
  return [
    (
      name: programming('01', '20260203', '01'),
      tsv: source,
      kind: 'session_tsv',
    ),
    (
      name: programming('01', '20260918', '01'),
      tsv: source.replaceAll('2026-02-03', '2026-09-18'),
      kind: 'session_tsv',
    ),
    (
      name: programming('07', '20260401', '01'),
      tsv: source.replaceAll('2026-02-03', '2026-04-01'),
      kind: 'session_tsv',
    ),
    (
      name: const BidsName(
        subject: '01',
        session: '20260203',
        task: 'notes',
        run: '01',
      ),
      tsv: writeAnnotations([
        Annotation.now('first note', at: DateTime.utc(2026, 2, 3, 9, 5)),
        Annotation.now('second note', at: DateTime.utc(2026, 2, 3, 9, 40)),
      ]),
      kind: 'annotation_tsv',
    ),
  ];
}

void main() {
  final source = File(_fixture).readAsStringSync();
  final contract = jsonDecode(
    File('schema/tsv_schema.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  /// Every file the dataset consists of, raw tree plus derivative.
  List<DatasetFile> buildTree() {
    final sources = _sources(source);
    final files = buildBidsDataset(
      [
        for (final s in sources)
          s.kind == 'session_tsv'
              ? sessionEntry(
                  name: s.name,
                  rows: parseSessionTsv(s.tsv),
                  contract: contract,
                )
              : notesEntry(
                  name: s.name,
                  tsv: s.tsv,
                  contract: contract,
                  acqTime: '2026-02-03T09:00:00+00:00',
                ),
      ],
      contract: contract,
      appName: appName,
      appVersion: appVersion,
      repoUrl: repoUrl,
    );

    final aggregate = buildAggregate([
      for (final s in sources.where((s) => s.kind == 'session_tsv'))
        (filename: s.name.filename, rows: parseSessionTsv(s.tsv)),
    ]);

    return [
      ...files,
      derivativeDescription(
        dir: aggregateDerivativeDir,
        name: '$appName combined sessions',
        appName: appName,
        appVersion: appVersion,
        repoUrl: repoUrl,
      ),
      (
        path: '$aggregateDerivativeDir/$aggregateStem.tsv',
        content: aggregate.tsv,
      ),
      (
        path: '$aggregateDerivativeDir/$aggregateStem.json',
        content: aggregateSidecarJson(contract, appVersion: appVersion),
      ),
    ];
  }

  // These run unconditionally: they are the parts a validator cannot check,
  // and they are cheap. The write below is what needs opting in.
  group('the tree the validator will see', () {
    test('carries the dataset-level files BIDS requires', () {
      final paths = buildTree().map((f) => f.path).toSet();
      expect(
        paths,
        containsAll(<String>{
          'dataset_description.json',
          'participants.tsv',
          'participants.json',
          'README',
        }),
      );
    });

    test('groups scans.tsv per subject and session, not per file', () {
      // Two sessions of sub-01 and one of sub-07, so three scans.tsv, and the
      // notes file must land in its session's file rather than in a fourth.
      final scans = buildTree()
          .map((f) => f.path)
          .where((p) => p.endsWith('_scans.tsv'))
          .toList();
      expect(scans, hasLength(3));
      expect(
        scans.where((p) => p.contains('sub-01_ses-20260203')).single,
        contains('sub-01/ses-20260203/'),
      );
    });

    test('participants.tsv lists both subjects, once each', () {
      final file = buildTree().firstWhere((f) => f.path == 'participants.tsv');
      final ids = [
        for (final line in file.content.trim().split('\n').skip(1))
          line.split('\t').first,
      ];
      expect(file.content, startsWith('participant_id\tdbs_indication\n'));
      expect(ids, ['sub-01', 'sub-07']);
    });

    test('each subject gets one sessions.tsv row per visit', () {
      final file = buildTree().firstWhere(
        (f) => f.path == 'sub-01/sub-01_sessions.tsv',
      );
      final ids = [
        for (final line in file.content.trim().split('\n').skip(1))
          line.split('\t').first,
      ];
      expect(ids, ['ses-20260203', 'ses-20260918']);
    });

    test('every raw data file sits in a beh/ datatype directory', () {
      for (final file in buildTree()) {
        if (!file.path.endsWith('.tsv')) continue;
        if (file.path.startsWith('derivatives/')) continue;
        if (!file.path.contains('/')) continue; // participants.tsv
        if (file.path.endsWith('_scans.tsv')) continue;
        if (file.path.endsWith('_sessions.tsv')) continue;
        expect(
          file.path,
          contains('/${BidsName.datatype}/'),
          reason: '${file.path} is not in a beh/ directory',
        );
      }
    });

    test('the derivative carries its own description', () {
      // "derivatives datasets MUST include a dataset_description.json file at
      // the root level": without it the whole dataset is invalid, not just
      // the derivative.
      final paths = buildTree().map((f) => f.path).toSet();
      expect(
        paths,
        containsAll(<String>{
          '$aggregateDerivativeDir/dataset_description.json',
          '$aggregateDerivativeDir/$aggregateStem.tsv',
          '$aggregateDerivativeDir/$aggregateStem.json',
        }),
      );
    });

    test('no two files claim the same path', () {
      // A duplicate path means a zip with two members of one name, where
      // extraction silently keeps whichever came last.
      final paths = buildTree().map((f) => f.path).toList();
      expect(paths.toSet(), hasLength(paths.length));
    });
  });

  test('write the tree for the validator', () async {
    final dir = _outDir;
    if (dir == null) {
      markTestSkipped('BIDS_DATASET_DIR not set');
      return;
    }
    final root = Directory(dir);
    if (root.existsSync()) root.deleteSync(recursive: true);
    for (final file in buildTree()) {
      final out = File('$dir/${file.path}');
      await out.parent.create(recursive: true);
      await out.writeAsString(file.content);
    }

    // Then MERGE a further visit into it, so what the validator judges is a
    // merged tree and not just a freshly built one. A merge that unions
    // participants.tsv or a scans.tsv wrongly produces a dataset that is
    // broken in exactly the way only a validator catches.
    final extra = buildBidsDataset(
      [
        sessionEntry(
          name: const BidsName(
            subject: '99',
            session: '20260401',
            task: 'programming',
            run: '01',
          ),
          rows: const [
            SessionRow(
              blockId: '1',
              isInitial: '0',
              acqTime: '2026-04-01T09:00:00+00:00',
            ),
          ],
          contract: contract,
        ),
      ],
      contract: contract,
      appName: appName,
      appVersion: appVersion,
      repoUrl: repoUrl,
    );
    final existing = [
      for (final f in buildTree()) (path: f.path, content: f.content),
    ];
    final plan = planBidsMerge(existing, extra);
    expect(
      plan.refused,
      isEmpty,
      reason: 'a new subject collides with nothing',
    );
    for (final file in plan.write) {
      final out = File('$dir/${file.path}');
      await out.parent.create(recursive: true);
      await out.writeAsString(file.content);
    }
    // Report what was written, so a failing validator run in CI can be read
    // against the tree that produced it.
    final written =
        root
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path.substring(dir.length + 1).replaceAll(r'\', '/'))
            .toList()
          ..sort();
    stdout.writeln('wrote ${written.length} files to $dir:');
    for (final path in written) {
      stdout.writeln('  $path');
    }
    expect(written, isNotEmpty);
  });

  group('dataset entries', () {
    const name = BidsName(
      subject: '01',
      session: '20260203',
      task: 'programming',
      run: '01',
    );

    test('builds the sidecar for the kind of file', () {
      final session = sessionEntry(
        name: name,
        rows: const [SessionRow(blockId: '1', isInitial: '0')],
        contract: contract,
      );
      final notes = notesEntry(
        name: name,
        tsv: 'x',
        contract: contract,
        acqTime: '2026-02-03T09:00:00+00:00',
      );
      final sessionJson = jsonDecode(session.sidecar) as Map<String, dynamic>;
      final notesJson = jsonDecode(notes.sidecar) as Map<String, dynamic>;

      expect(sessionJson.keys, contains('is_final'));
      expect(sessionJson.keys, isNot(contains('block_id')));
      expect(
        notesJson.keys,
        isNot(contains('is_final')),
        reason: 'a notes sidecar must not document session columns',
      );
      expect(notesJson.keys, contains('acq_time'));
    });

    test('an empty acq_time becomes n/a, never a blank cell', () {
      final entry = sessionEntry(
        name: name,
        rows: const [],
        contract: contract,
      );
      expect(entry.acqTime, 'n/a');
    });

    test('passes a notes tsv and its name through untouched', () {
      final entry = notesEntry(
        name: name,
        tsv: 'header\nrow\n',
        contract: contract,
        acqTime: '2026-02-03T09:00:00+00:00',
      );
      expect(entry.tsv, 'header\nrow\n');
      expect(entry.name.filename, name.filename);
    });

    test('the sidecar is pretty-printed and newline-terminated', () {
      final entry = sessionEntry(
        name: name,
        rows: const [],
        contract: contract,
      );
      expect(entry.sidecar, contains('\n  "'));
      expect(entry.sidecar, endsWith('\n'));
    });
  });
}
