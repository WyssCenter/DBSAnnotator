/// One case per row of the enablement matrix, which is the feature: the
/// reports screen offers every action and greys out what the upload cannot
/// support, so a wrong answer here is a control that lies.
library;

import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/core/session/tsv_kind.dart';
import 'package:dbs_annotator/report/upload_actions.dart';
import 'package:flutter_test/flutter_test.dart';

const _row = SessionRow(
  blockId: '1',
  isInitial: '0',
  acqTime: '2026-02-03T09:00:00',
);

Uploaded session(String name) => (
  name: name,
  kind: TsvKind.programming,
  rows: const [_row],
  notes: const <Annotation>[],
);

Uploaded notes(String name) => (
  name: name,
  kind: TsvKind.notes,
  rows: const <SessionRow>[],
  notes: const [Annotation(acqTime: '2026-02-03T09:00:00', notes: 'n')],
);

void main() {
  const a = 'sub-01_ses-20260203_task-programming_run-01_beh.tsv';
  const b = 'sub-01_ses-20260310_task-programming_run-01_beh.tsv';
  const other = 'sub-02_ses-20260310_task-programming_run-01_beh.tsv';

  test('nothing uploaded leaves every action off', () {
    expect(availableActions(const []), isEmpty);
    for (final action in ReportAction.values) {
      expect(unavailableReason(action, const []), 'Import a session first.');
    }
  });

  test('one session: report and dataset, but not the aggregate', () {
    expect(availableActions([session(a)]), {
      ReportAction.sessionReport,
      ReportAction.bidsDataset,
      ReportAction.addToDataset,
    });
  });

  test('one older notes file: no report of its own, a BIDS folder', () {
    expect(
      availableActions([
        notes('sub-01_ses-20260203_task-notes_run-01_beh.tsv'),
      ]),
      {ReportAction.bidsDataset, ReportAction.addToDataset},
    );
  });

  test('two sessions of one patient: everything', () {
    expect(availableActions([session(a), session(b)]), {
      ReportAction.longitudinalReport,
      ReportAction.aggregateTsv,
      ReportAction.bidsDataset,
      ReportAction.addToDataset,
    });
  });

  test(
    'two patients: aggregate and dataset, never the longitudinal report',
    () {
      final files = [session(a), session(other)];
      expect(availableActions(files), {
        ReportAction.aggregateTsv,
        ReportAction.bidsDataset,
        ReportAction.addToDataset,
      });
      // Combining two people into one longitudinal report is a safety problem.
      expect(
        unavailableReason(ReportAction.longitudinalReport, files),
        'These files name different patients.',
      );
    },
  );

  test('a session and its notes are two files, so longitudinal', () {
    final files = [
      session(a),
      notes('sub-01_ses-20260203_task-notes_run-01_beh.tsv'),
    ];
    expect(availableActions(files), contains(ReportAction.longitudinalReport));
    expect(availableActions(files), contains(ReportAction.aggregateTsv));
    expect(
      unavailableReason(ReportAction.sessionReport, files),
      'Import one session; several give a report across visits.',
    );
  });

  test('two notes files and no session still give a longitudinal report', () {
    expect(
      availableActions([
        notes('sub-01_ses-20260203_task-notes_run-01_beh.tsv'),
        notes('sub-01_ses-20260310_task-notes_run-01_beh.tsv'),
      ]),
      contains(ReportAction.longitudinalReport),
    );
  });

  test('a notes file joins the combined table as one row per note', () {
    final sources = aggregateSources([
      session(a),
      notes('sub-01_ses-20260203_task-notes_run-01_beh.tsv'),
    ]);
    expect(sources.first.rows, const [_row]);
    final note = sources.last.rows.single;
    expect(note.acqTime, '2026-02-03T09:00:00');
    expect(note.notes, 'n');
    expect(note.blockId, '0', reason: 'each note is a row of its own');
  });

  test('every action explains itself', () {
    for (final action in ReportAction.values) {
      expect(action.how, isNotEmpty, reason: action.name);
      expect(action.needs, isNotEmpty, reason: action.name);
      expect(action.creates, isNotEmpty, reason: action.name);
    }
  });

  test('several sessions turn the single report off, with a reason', () {
    expect(
      unavailableReason(ReportAction.sessionReport, [session(a), session(b)]),
      'Import one session; several give a report across visits.',
    );
  });

  test('a tablet can still merge, by zip rather than by folder', () {
    // The platform decides HOW a dataset is merged, not whether it can be:
    // iPadOS and Android take the dataset as a zip and give a new one back.
    for (final action in [
      ReportAction.bidsDataset,
      ReportAction.addToDataset,
    ]) {
      expect(
        unavailableReason(action, [session(a)], canWriteFolder: false),
        isNull,
        reason: action.name,
      );
    }
  });

  test('a filename with no sub- entity cannot become a dataset path', () {
    final files = [session('my notes export.tsv')];
    expect(
      unavailableReason(ReportAction.bidsDataset, files),
      'No imported file name carries a sub- entity.',
    );
    expect(
      unavailableReason(ReportAction.sessionReport, files),
      isNull,
      reason: 'a report needs no entities, it names itself after the file',
    );
  });

  test('the summary names what was uploaded', () {
    expect(uploadSummary(const []), 'No files imported.');
    expect(uploadSummary([session(a)]), '1 session');
    expect(uploadSummary([session(a), session(b)]), '2 sessions');
    expect(
      uploadSummary([session(a), notes('sub-01_task-notes_beh.tsv')]),
      '1 session and 1 notes file',
    );
  });

  test('uploads are ordered by patient, then earliest to latest', () {
    Uploaded at(String name, String when) => (
      name: name,
      kind: TsvKind.programming,
      rows: [SessionRow(blockId: '1', isInitial: '0', acqTime: when)],
      notes: const <Annotation>[],
    );
    final picked = [
      at(b, '2026-03-10T09:00:00'),
      at(other, '2026-01-01T09:00:00'),
      at(a, '2026-02-03T09:00:00'),
    ];
    expect(chronological(picked).map((f) => f.name), [a, b, other]);
  });
}
