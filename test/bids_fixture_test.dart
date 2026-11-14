/// The committed example BIDS folder in `test/fixtures/bids/`: the two
/// synthetic visits of patient 01, written by the app's own export code.
///
/// Regenerate after a format change:
///   $env:FIXTURES_WRITE = "1"; flutter test test/bids_fixture_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/app_info.dart';
import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/core/bids_dataset.dart';
import 'package:dbs_annotator/core/schema_columns.dart' show isInitialValue;
import 'package:dbs_annotator/core/session/bids_folder.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/ui/bids_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'docs/example_visits.dart';

const _root = 'test/fixtures/bids';

Map<String, List<SessionRow>> _visits() => {
  for (final MapEntry(:key, :value) in exampleVisitTexts().entries)
    key: parseSessionTsv(value),
};

List<DatasetFile> _build() {
  final contract = jsonDecode(
    File('schema/tsv_schema.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return buildBidsDataset(
    [
      for (final MapEntry(:key, :value) in _visits().entries)
        sessionEntry(
          name: BidsName.parse(key)!,
          rows: value,
          contract: contract,
        ),
    ],
    contract: contract,
    appName: appName,
    appVersion: appVersion,
    repoUrl: repoUrl,
  );
}

Set<String> _committed() => {
  for (final f in Directory(_root).listSync(recursive: true))
    if (f is File) f.path.substring(_root.length + 1).replaceAll(r'\', '/'),
};

/// What a row means clinically, without the fields the BIDS layout renumbers.
List<Map<String, String>> _content(List<SessionRow> rows) => [
  for (final r in rows)
    {...r.toMap()}
      ..remove('block_id')
      ..remove('append_id'),
];

void main() {
  test(
    'writes the folder',
    () {
      final dir = Directory(_root);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      for (final f in _build()) {
        File('$_root/${f.path}')
          ..createSync(recursive: true)
          ..writeAsStringSync(f.content);
      }
    },
    skip: Platform.environment['FIXTURES_WRITE'] == '1'
        ? false
        : 'set FIXTURES_WRITE=1 to regenerate',
  );

  test('holds exactly the files the app writes for these visits', () {
    expect(_committed(), {for (final f in _build()) f.path});
  });

  test('every visit reads back as the rows it was written from', () async {
    for (final MapEntry(:key, :value) in _visits().entries) {
      final name = BidsName.parse(key)!;
      final path = '$_root/sub-${name.subject}/ses-${name.session}/beh/$key';
      final back = await readSessionFile(
        File(path).readAsStringSync(),
        path: path,
      );
      expect(_content(back), _content(value), reason: key);
    }
  });

  test('two runs on one day keep their own initial assessment, and a third '
      'starts from the second', () async {
    final rows = _visits().values.first;
    final dir = Directory.systemTemp.createTempSync('bids_runs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final contract = jsonDecode(
      File('schema/tsv_schema.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    List<SessionRow> withInitialNotes(String notes) => [
      for (final r in rows)
        isInitialValue(r.isInitial)
            ? SessionRow.fromMap({...r.toMap(), 'notes': notes})
            : r,
    ];
    BidsName run(String n) => BidsName.parse(
      'sub-01_ses-20260203_task-programming_run-${n}_beh.tsv',
    )!;
    final files = buildBidsDataset(
      [
        sessionEntry(
          name: run('01'),
          rows: withInitialNotes('morning, before the dose'),
          contract: contract,
        ),
        sessionEntry(
          name: run('02'),
          rows: withInitialNotes('afternoon, after the dose'),
          contract: contract,
        ),
      ],
      contract: contract,
      appName: appName,
      appVersion: appVersion,
      repoUrl: repoUrl,
    );
    for (final f in files) {
      File('${dir.path}/${f.path}')
        ..createSync(recursive: true)
        ..writeAsStringSync(f.content);
    }

    Future<String> initialNotes(String n) async {
      final path = '${dir.path}/sub-01/ses-20260203/beh/${run(n).filename}';
      final back = await readSessionFile(
        File(path).readAsStringSync(),
        path: path,
      );
      return back.firstWhere((r) => isInitialValue(r.isInitial)).notes;
    }

    expect(await initialNotes('01'), 'morning, before the dose');
    expect(await initialNotes('02'), 'afternoon, after the dose');
    final next = await earlierInitial(dir.path, run('03'));
    expect(next.first.notes, 'afternoon, after the dose');
  });

  test('the patient history comes from the last visit', () async {
    expect(await participantsIn(_root), ['01']);
    final history = await patientHistory(_root, '01');
    expect(history.indication, 'OCD');
    expect(history.lastVisit['session_id'], 'ses-20260918');
  });
}
