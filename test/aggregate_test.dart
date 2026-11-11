/// The combined table: identity columns, determinism, and the two refusals.
///
/// Built from const [SessionRow] literals rather than fixture files, the way
/// `test/longitudinal_report_test.dart` already does: `test/fixtures/` holds one
/// subject at one session, and inventing two more on-disk files to exercise a
/// pure function would be waste.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/bids_sidecar.dart';
import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:dbs_annotator/core/session/aggregate.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/core/tsv.dart';
import 'package:flutter_test/flutter_test.dart';

const _visitA = 'sub-01_ses-20260203_task-programming_run-01_beh.tsv';
const _visitB = 'sub-01_ses-20260615_task-programming_run-02_beh.tsv';
const _otherSubject = 'sub-07_ses-20260701_task-programming_run-01_beh.tsv';

/// Two blocks, two scales each, so block ordering is observable.
List<SessionRow> _rows(String day) => [
  SessionRow(
    acqTime:
        '2026-$day'
        'T09:00:00+01:00',
    blockId: '1',
    appendId: '1',
    isInitial: '0',
    scaleName: 'Obsessions',
    scaleValue: '6',
  ),
  SessionRow(
    acqTime:
        '2026-$day'
        'T09:00:00+01:00',
    blockId: '1',
    appendId: '1',
    isInitial: '0',
    scaleName: 'Mood',
    scaleValue: '4',
  ),
  SessionRow(
    acqTime:
        '2026-$day'
        'T09:10:00+01:00',
    blockId: '2',
    appendId: '1',
    isInitial: '0',
    scaleName: 'Obsessions',
    scaleValue: '5',
  ),
];

List<AggregateSource> _twoVisits() => [
  (filename: _visitA, rows: _rows('02-03')),
  (filename: _visitB, rows: _rows('06-15')),
];

List<List<String>> _table(String tsv) => parseTsv(tsv);

void main() {
  group('the header', () {
    test('is the identity columns, the visit, then the session columns', () {
      final header = aggregateColumns(['scale_mood']);
      expect(header.take(5), [
        'participant_id',
        'session_id',
        'run_id',
        'source_file',
        'is_initial',
      ]);
      expect(header, containsAll(sessionColumns));
      expect(header, containsAll(['dbs_indication', 'target']));
      expect(header.sublist(header.length - 2), ['scale_mood', 'notes']);
    });

    test('session_id is the BIDS session label, never a counter', () {
      expect(aggregateColumns(), isNot(contains('append_id')));
      final out = buildAggregate(_twoVisits());
      final header = _table(out.tsv).first;
      expect(header, isNot(contains('append_id')));
      for (final row in _table(out.tsv).skip(1)) {
        expect(row[header.indexOf('session_id')], startsWith('ses-'));
      }
    });

    test('is what the document actually starts with', () {
      final out = buildAggregate(_twoVisits());
      expect(_table(out.tsv).first, aggregateColumns(out.scaleNames.keys));
      expect(out.scaleNames, {
        'scale_obsessions': 'Obsessions',
        'scale_mood': 'Mood',
      });
    });
  });

  group('identity columns', () {
    test('are the parsed entities, not invented', () {
      final out = buildAggregate(_twoVisits());
      final rows = _table(out.tsv);
      final header = rows.first;
      final first = rows[1];
      expect(first[header.indexOf('participant_id')], 'sub-01');
      expect(first[header.indexOf('session_id')], 'ses-20260203');
      expect(first[header.indexOf('run_id')], '01');
      expect(first[header.indexOf('source_file')], _visitA);
    });

    test('participant_id matches the participants.tsv value shape', () {
      // `sub-<label>` is what `buildBidsDataset` writes into participants.tsv,
      // so the aggregate joins onto it with no transformation. That is the
      // point of using the BIDS spelling rather than a bare label.
      final out = buildAggregate([
        ..._twoVisits(),
        (filename: _otherSubject, rows: _rows('07-01')),
      ]);
      expect(out.subjects, ['sub-01', 'sub-07']);
    });

    test('a second subject aggregates alongside the first', () {
      final out = buildAggregate([
        ..._twoVisits(),
        (filename: _otherSubject, rows: _rows('07-01')),
      ]);
      expect(out.fileCount, 3);
      expect(out.rowCount, 6);
      expect(out.skipped, isEmpty);
    });
  });

  test('nothing is silently dropped: rowCount is the sum of the inputs', () {
    final sources = _twoVisits();
    final expected = sources.fold(
      0,
      (n, s) => n + s.rows.map((r) => r.blockId).toSet().length,
    );
    final out = buildAggregate(sources);
    expect(out.rowCount, expected);
    expect(_table(out.tsv).length, expected + 1, reason: '+1 for the header');
  });

  group('determinism', () {
    // A shared table that reshuffles between exports cannot be diffed, and
    // being diffable is most of what makes one file easier to work with than a
    // folder of them. Asserted by aggregating the same set in the opposite
    // order and demanding byte equality.
    test('input order does not change the output', () {
      final forward = buildAggregate(_twoVisits());
      final reversed = buildAggregate(_twoVisits().reversed.toList());
      expect(reversed.tsv, forward.tsv);
    });

    test('rows are ordered by subject, session, run, then configuration', () {
      final out = buildAggregate([
        (filename: _otherSubject, rows: _rows('07-01')),
        (filename: _visitB, rows: _rows('06-15')),
        (filename: _visitA, rows: _rows('02-03')),
      ]);
      final rows = _table(out.tsv);
      final header = rows.first;
      final p = header.indexOf('participant_id');
      final s = header.indexOf('session_id');
      final o = header.indexOf('scale_obsessions');

      expect(rows.skip(1).map((r) => r[p]).toList(), [
        ...List.filled(4, 'sub-01'),
        ...List.filled(2, 'sub-07'),
      ]);
      expect(
        rows.skip(1).take(2).map((r) => r[s]),
        everyElement('ses-20260203'),
      );
      expect(rows.skip(1).take(2).map((r) => r[o]).toList(), ['6', '5']);
    });
  });

  group('refusals', () {
    test('a file with no sub- entity is skipped AND reported', () {
      final out = buildAggregate([
        ..._twoVisits(),
        (filename: 'my-notes-copy.tsv', rows: _rows('09-09')),
      ]);
      expect(out.fileCount, 2);
      expect(out.skipped.map((s) => s.filename), ['my-notes-copy.tsv']);
      expect(out.skipped.single.reason, contains('sub-'));
      expect(out.rowCount, 4, reason: 'its rows are not in the table');
    });

    test('a file with no ses- entity is skipped', () {
      final out = buildAggregate([
        (
          filename: 'sub-01_task-programming_run-01_beh.tsv',
          rows: _rows('1-1'),
        ),
      ]);
      expect(out.fileCount, 0);
      expect(out.tsv, '');
      expect(out.skipped, hasLength(1));
    });

    // Importing the same file twice today lists it twice: `_files.addAll` has no
    // name check. For a report that is merely odd; for an analysis table it
    // doubles every row and every count derived from them, invisibly.
    test('the same filename twice is refused, not concatenated', () {
      final out = buildAggregate([
        (filename: _visitA, rows: _rows('02-03')),
        (filename: _visitA, rows: _rows('02-03')),
      ]);
      expect(out.fileCount, 1);
      expect(out.rowCount, 2, reason: 'not 4');
      expect(out.skipped.single.filename, _visitA);
      expect(out.skipped.single.reason, contains('already included'));
    });

    test('no includable files yields an empty document, not a lone header', () {
      final out = buildAggregate(const []);
      expect(out.tsv, '');
      expect(out.rowCount, 0);
      expect(out.subjects, isEmpty);
    });
  });

  test('an empty cell is written as n/a, per BIDS', () {
    final out = buildAggregate([
      (filename: _visitA, rows: const [SessionRow(blockId: '1')]),
    ]);
    expect(out.tsv, contains('\tn/a'));
  });

  test(
    'a legacy filename aggregates, and keeps its own suffix in source_file',
    () {
      // A 0.4.x `_events.tsv` still parses to entities, so it belongs in the
      // table; `source_file` records what it was actually called.
      const legacy = 'sub-01_ses-20260101_task-programming_run-01_events.tsv';
      final out = buildAggregate([(filename: legacy, rows: _rows('01-01'))]);
      final rows = _table(out.tsv);
      expect(out.fileCount, 1);
      expect(rows[1][rows.first.indexOf('source_file')], legacy);
    },
  );

  group('the sidecar', () {
    late Map<String, dynamic> contract;

    setUpAll(() {
      contract = jsonDecode(
        File('schema/tsv_schema.json').readAsStringSync(),
      ) as Map<String, dynamic>;
    });

    // The guard that stops the sidecar drifting from the header: every column
    // the table writes must be documented, or a consumer meets a column with
    // no definition - which for a clinical derivative is the whole point of
    // shipping a sidecar at all.
    test('documents every column in the header, and no others', () {
      final json = jsonDecode(
        aggregateSidecarJson(contract, appVersion: 'test'),
      ) as Map<String, dynamic>;
      const documentLevel = {
        'GeneratedBy',
        'SchemaVersion',
        'MissingValueCode',
      };
      final documented = json.keys.where((k) => !documentLevel.contains(k));
      expect(documented, unorderedEquals(aggregateColumns()));
    });

    test('says acq_time may be computed for a pre-0.5.0 row', () {
      final json = jsonDecode(
        aggregateSidecarJson(contract, appVersion: 'test'),
      ) as Map<String, dynamic>;
      expect(
        (json['acq_time'] as Map)['Description'] as String,
        contains('COMPUTED'),
      );
    });

    test('describes session_id as the BIDS session', () {
      final json = jsonDecode(
        aggregateSidecarJson(contract, appVersion: 'test'),
      ) as Map<String, dynamic>;
      expect(
        (json['session_id'] as Map)['Description'] as String,
        contains('sessions.tsv'),
      );
      expect(json.containsKey('append_id'), isFalse);
    });
  });

  test('visits are ordered by when they happened, not by their label', () {
    // `ses-postop` sorts before `ses-preop` alphabetically, the wrong way round.
    const pre = 'sub-01_ses-preop_task-programming_run-01_beh.tsv';
    const post = 'sub-01_ses-postop_task-programming_run-01_beh.tsv';
    final out = buildAggregate([
      (filename: post, rows: _rows('06-15')),
      (filename: pre, rows: _rows('02-03')),
    ]);
    final files = parseTsvRecords(out.tsv).map((r) => r['source_file']);
    expect(files.first, pre);
    expect(files.last, post);
  });
}
