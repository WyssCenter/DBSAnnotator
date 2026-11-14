/// Recording a visit straight into a BIDS dataset.
///
/// The screen decides WHEN to file (on the first insert, so the dataset is
/// never left holding a header-only TSV that no scans.tsv lists). What it files
/// goes through the same `planBidsMerge` as every other write into a dataset,
/// which is what this pins: the study's own columns survive, and a visit
/// already filed there is refused rather than overwritten.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dbs_annotator/app_info.dart';
import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/core/bids_dataset.dart';
import 'package:dbs_annotator/core/bids_merge.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/core/tsv.dart';
import 'package:dbs_annotator/ui/bids_export.dart';
import 'package:dbs_annotator/ui/bids_merge_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _name = BidsName(
  subject: '01',
  session: 'preop',
  task: 'programming',
  run: '01',
);

/// A dataset a lab curates by hand, on disk.
Future<Directory> _seed() async {
  final root = Directory.systemTemp.createTempSync('dbs_ds');
  Future<void> put(String rel, String content) async {
    final f = File('${root.path}/$rel');
    await f.parent.create(recursive: true);
    await f.writeAsString(content);
  }

  await put(
    'dataset_description.json',
    '{"Name": "OCD cohort", "Authors": ["Poma L"], '
        '"DatasetDOI": "doi:10.5281/zenodo.99"}',
  );
  await put('README', 'Hand curated.');
  await put(
    'participants.tsv',
    writeTsvRecords(
      const ['participant_id', 'age', 'group'],
      const [
        {'participant_id': 'sub-01', 'age': '54', 'group': 'OCD'},
      ],
    ),
  );
  await put('sub-01/ses-20250101/anat/sub-01_ses-20250101_T1w.json', '{}');
  return root;
}

DatasetEntry _entry(
  Map<String, dynamic> contract, {
  String note = 'x',
  String target = 'STN',
}) => sessionEntry(
  name: _name,
  rows: [
    SessionRow(
      blockId: '1',
      isInitial: '0',
      acqTime: '2026-02-03T09:00:00+00:00',
      pathology: 'PD',
      target: target,
      notes: note,
    ),
  ],
  contract: contract,
);

List<DatasetFile> _visit(Map<String, dynamic> contract, {String tsv = 'x'}) =>
    buildBidsDataset(
      [_entry(contract, note: tsv)],
      contract: contract,
      appName: appName,
      appVersion: appVersion,
      repoUrl: repoUrl,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  // Read from the repo rather than the asset bundle, which a plain
  // `flutter test` has no binding for.
  final contract = jsonDecode(
    File('schema/tsv_schema.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  setUp(() async => root = await _seed());
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> file({String tsv = 'x'}) async {
    final plan = planBidsMerge(
      await readDatasetDirectory(root.path),
      _visit(contract, tsv: tsv),
    );
    await applyMergeToDirectory(root.path, plan);
  }

  test('the visit lands at its BIDS path with its sidecar', () async {
    await file();
    final dir = '${root.path}/${_name.relativeDir}';
    expect(File('$dir/${_name.filename}').existsSync(), isTrue);
    expect(File('$dir/${_name.sidecarFilename}').existsSync(), isTrue);
  });

  test('a new patient gets a derivatives folder for reports', () async {
    await file();
    expect(
      Directory('${root.path}/derivatives/sub-${_name.subject}').existsSync(),
      isTrue,
    );
  });

  test('a non-date session label is honoured, not replaced', () async {
    await file();
    // `ses-preop`, because plenty of studies do not label sessions by date.
    expect(
      Directory('${root.path}/sub-01/ses-preop').existsSync(),
      isTrue,
      reason: 'the label the user chose is the one used',
    );
  });

  test('scans.tsv is written so the dataset is self-consistent', () async {
    await file();
    final scans = File(
      '${root.path}/sub-01/ses-preop/sub-01_ses-preop_scans.tsv',
    );
    expect(scans.existsSync(), isTrue);
    final rows = parseTsvRecords(scans.readAsStringSync());
    expect(rows.single['filename'], 'beh/${_name.filename}');
    expect(rows.single['acq_time'], '2026-02-03T09:00:00+00:00');
  });

  test('the curated files are left exactly as they were', () async {
    final before = File('${root.path}/dataset_description.json')
        .readAsStringSync();
    final readme = File('${root.path}/README').readAsStringSync();
    await file();
    expect(
      File('${root.path}/dataset_description.json').readAsStringSync(),
      before,
      reason: 'the DOI and authors are the lab\'s, not the app\'s',
    );
    expect(File('${root.path}/README').readAsStringSync(), readme);
  });

  test('participants.tsv keeps its own columns', () async {
    await file();
    final rows = parseTsvRecords(
      File('${root.path}/participants.tsv').readAsStringSync(),
    );
    expect(rows.single['participant_id'], 'sub-01');
    expect(rows.single['age'], '54');
    expect(rows.single['group'], 'OCD');
    expect(rows.single['dbs_indication'], 'PD');
  });

  test('the visit gets its row in sessions.tsv', () async {
    await file();
    final rows = parseTsvRecords(
      File('${root.path}/sub-01/sub-01_sessions.tsv').readAsStringSync(),
    );
    expect(rows.single['session_id'], 'ses-preop');
    expect(rows.single['target'], 'STN');
  });

  test('recording the visit again updates its own rows only', () async {
    expect(
      await fileIntoDataset(root: root.path, entry: _entry(contract)),
      isNotNull,
    );
    final filed = await fileIntoDataset(
      root: root.path,
      entry: _entry(contract, note: 'second block', target: 'GPi'),
      filed: true,
    );
    expect(File(filed!.path).readAsStringSync(), contains('second block'));
    final visit = parseTsvRecords(
      File('${root.path}/sub-01/sub-01_sessions.tsv').readAsStringSync(),
    ).single;
    expect(visit['target'], 'GPi');
    final person = parseTsvRecords(
      File('${root.path}/participants.tsv').readAsStringSync(),
    ).single;
    expect(person['age'], '54', reason: "the lab's columns survive");
    expect(
      Directory(root.path)
          .listSync(recursive: true)
          .where((e) => e.path.contains('.bak-')),
      isEmpty,
      reason: 'recording leaves no backup copies behind',
    );
  });

  test('imaging alongside the session is untouched', () async {
    const rel = 'sub-01/ses-20250101/anat/sub-01_ses-20250101_T1w.json';
    await file();
    expect(File('${root.path}/$rel').existsSync(), isTrue);
  });

  test('re-filing the same visit is refused, never an overwrite', () async {
    await file(tsv: 'first recording');
    final plan = planBidsMerge(
      await readDatasetDirectory(root.path),
      _visit(contract, tsv: 'a DIFFERENT recording'),
    );
    expect(plan.refused, contains('${_name.relativeDir}/${_name.filename}'));

    await applyMergeToDirectory(root.path, plan);
    expect(
      File('${root.path}/${_name.relativeDir}/${_name.filename}')
          .readAsStringSync(),
      contains('first recording'),
      reason: 'the archived visit survives',
    );
  });

  test('autosaving the same visit again changes nothing', () async {
    await file();
    final plan = planBidsMerge(
      await readDatasetDirectory(root.path),
      _visit(contract),
    );
    expect(plan.write, isEmpty);
  });

  test('a report travels as bytes and is never overwritten', () async {
    const path = '$reportsDerivativeDir/sub-01/ses-preop/beh/r_report.pdf';
    final bytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0xff]);
    final incoming = [(path: path, content: kBinaryContent)];

    final plan = planBidsMerge(await readDatasetDirectory(root.path), incoming);
    expect(plan.added, [path]);
    await applyMergeToDirectory(root.path, plan, binary: {path: bytes});
    expect(File('${root.path}/$path').readAsBytesSync(), bytes);

    final zip = ZipDecoder().decodeBytes(
      mergedZip(textZip(const {}), plan, binary: {path: bytes}),
    );
    expect(zip.findFile(path)!.readBytes(), bytes);

    final again = planBidsMerge(
      await readDatasetDirectory(root.path),
      incoming,
    );
    expect(again.refused, [path]);
  });

  test('a merged zip keeps binary and non-UTF-8 entries byte for byte', () {
    final pdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0xff, 0x00, 0xfe]);
    final latin1Json = Uint8List.fromList([0x7b, 0xe9, 0x7d]);
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('docs/report.pdf', pdf))
      ..addFile(ArchiveFile.bytes('participants.json', latin1Json))
      ..addFile(ArchiveFile.bytes('LICENSE', Uint8List.fromList([65, 66])));
    final source = Uint8List.fromList(ZipEncoder().encode(archive));

    final existing = readDatasetZip(source);
    final incoming = [(path: 'sub-01/new.tsv', content: 'a\tb\n')];
    final plan = planBidsMerge(existing, incoming);

    final merged = ZipDecoder().decodeBytes(mergedZip(source, plan));
    expect(merged.findFile('docs/report.pdf')!.readBytes(), pdf);
    expect(merged.findFile('participants.json')!.readBytes(), latin1Json);
    expect(merged.findFile('LICENSE')!.readBytes(), [65, 66]);
    expect(
      String.fromCharCodes(merged.findFile('sub-01/new.tsv')!.readBytes()!),
      'a\tb\n',
    );
  });

  test('a non-UTF-8 participants.tsv survives a merge and is reported', () {
    final original = Uint8List.fromList([
      ...'participant_id\tname\nsub-01\tM'.codeUnits,
      0xfc,
      ...'ller\n'.codeUnits,
    ]);
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('participants.tsv', original))
      ..addFile(
        ArchiveFile.bytes(
          'dataset_description.json',
          Uint8List.fromList([123, 125]),
        ),
      );
    final source = Uint8List.fromList(ZipEncoder().encode(archive));

    final plan = planBidsMerge(readDatasetZip(source), [
      (path: 'participants.tsv', content: 'participant_id\nsub-02\n'),
      (path: 'sub-02/new.tsv', content: 'a\n'),
    ]);

    expect(plan.unread, ['participants.tsv']);
    expect(plan.rowMerged, isEmpty);
    final merged = ZipDecoder().decodeBytes(mergedZip(source, plan));
    expect(merged.findFile('participants.tsv')!.readBytes(), original);
    expect(merged.findFile('sub-02/new.tsv'), isNotNull);
  });
}
