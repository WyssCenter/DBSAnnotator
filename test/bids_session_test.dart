import 'dart:io';

import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:dbs_annotator/core/session/bids_session.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/core/session/tsv_kind.dart';
import 'package:dbs_annotator/core/tsv.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixture =
    'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv';

SessionTables _split(List<SessionRow> rows) =>
    splitSession(rows, sessionId: 'ses-20260203', participantId: 'sub-01');

List<SessionRow> _join(SessionTables t) => joinSession(
  behRows: parseTsvRecords(behTsv(t)),
  visit: t.visit,
  participant: t.participant,
  scaleNames: t.scaleNames,
);

/// What a row means, without the cells the BIDS tables renumber.
String _meaning(SessionRow r) {
  final m = r.toMap()
    ..remove('block_id')
    ..remove('append_id');
  return m.toString();
}

void main() {
  final rows = parseSessionTsv(File(_fixture).readAsStringSync());

  test('scale names become scale_ columns', () {
    expect(scaleColumnSlug('Mood'), 'scale_mood');
    expect(scaleColumnSlug('MDS-UPDRS 3.10 Gait'), 'scale_mds_updrs_3_10_gait');
    expect(scaleColumnSlug('  '), 'scale_unnamed');
  });

  test('the beh file has one row per configuration and no long columns', () {
    final t = _split(rows);
    final blocks = {
      for (final r in rows)
        if (!isInitialValue(r.isInitial)) r.blockId,
    };
    expect(t.behRows, hasLength(blocks.length));
    for (final gone in ['block_id', 'is_initial', 'scale_name', 'target']) {
      expect(t.behColumns, isNot(contains(gone)));
    }
    expect(t.behColumns.last, 'notes');
  });

  test('visit and person carry what does not change within the visit', () {
    final t = _split(rows);
    expect(t.visit['session_id'], 'ses-20260203');
    expect(t.visit['left_electrode_model'], electrodeModelIn(rows));
    expect(
      t.participant['dbs_indication'],
      sessionValueIn(rows, (r) => r.pathology),
    );
  });

  test('splitting and joining gives the same rows back', () {
    final back = _join(_split(rows));
    expect(back.map(_meaning).toList(), rows.map(_meaning).toList());
  });

  test('a beh file is a programming file, read on its own too', () {
    final tsv = behTsv(_split(rows));
    expect(sniffTsvKind(tsv), TsvKind.programming);
    final alone = parseAnySessionTsv(tsv);
    expect(alone.where((r) => isInitialValue(r.isInitial)), isEmpty);
    expect(
      alone.map((r) => r.blockId).toSet(),
      hasLength(_split(rows).behRows.length),
    );
  });

  test('two scale names with one slug get distinct columns', () {
    final t = _split(const [
      SessionRow(
        blockId: '1',
        isInitial: '0',
        scaleName: 'Mood',
        scaleValue: '3',
      ),
      SessionRow(
        blockId: '1',
        isInitial: '0',
        scaleName: 'mood',
        scaleValue: '4',
      ),
    ]);
    expect(t.scaleNames, {'scale_mood': 'Mood', 'scale_mood_2': 'mood'});
    expect(t.behRows.single['scale_mood_2'], '4');
  });

  test('a scale not rated in a block is n/a there', () {
    final t = _split(const [
      SessionRow(
        blockId: '1',
        isInitial: '0',
        scaleName: 'Mood',
        scaleValue: '3',
      ),
      SessionRow(
        blockId: '2',
        isInitial: '0',
        scaleName: 'Tremor',
        scaleValue: '1',
      ),
    ]);
    expect(behTsv(t).trim().split('\n').last, contains('n/a'));
  });
}
