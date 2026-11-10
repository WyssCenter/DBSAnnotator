import 'dart:io';

import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/tsv_kind.dart';
import 'package:dbs_annotator/report/upload_actions.dart';

const exampleFixture =
    'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv';

/// The follow-up visit: the example months later, with lower clinical totals
/// and a few session ratings moved, so the longitudinal figures and the
/// change column show a real change rather than a copy.
const _followUp = {
  '2026-02-03': '2026-09-18',
  '\tUPDRS-III\t38\t': '\tUPDRS-III\t29\t',
  '\tPDQ-39\t31\t': '\tPDQ-39\t24\t',
  '\tUDysRS\t14\t': '\tUDysRS\t10\t',
  '\tMDS-UPDRS 3.3 Rigidity RUE\t3\t': '\tMDS-UPDRS 3.3 Rigidity RUE\t2\t',
  '\tMDS-UPDRS 3.17 Rest tremor RUE\t2\t':
      '\tMDS-UPDRS 3.17 Rest tremor RUE\t1\t',
};

/// The two visits as they would be on disk: filename to TSV text.
Map<String, String> exampleVisitTexts({
  bool mismatchedPatients = false,
  String root = '.',
}) {
  final source = File('$root/$exampleFixture').readAsStringSync();
  return {
    'sub-01_ses-20260203_task-programming_run-01_beh.tsv': source,
    mismatchedPatients
        ? 'sub-04_ses-20260918_task-programming_run-01_beh.tsv'
        : 'sub-01_ses-20260918_task-programming_run-02_beh.tsv': _followUp
        .entries
        .fold(source, (text, e) => text.replaceAll(e.key, e.value)),
  };
}

/// The committed example, and for more than one visit the follow-up above.
List<Uploaded> exampleVisits({
  bool mismatchedPatients = false,
  int count = 2,
  String root = '.',
}) => [
  for (final e in exampleVisitTexts(
    mismatchedPatients: mismatchedPatients,
    root: root,
  ).entries.take(count))
    (
      name: e.key,
      kind: TsvKind.programming,
      rows: parseSessionTsv(e.value),
      notes: const <Annotation>[],
    ),
];
