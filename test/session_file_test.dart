import 'dart:io';

import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/timestamps.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final stamp = DateTime(2026, 7, 27, 10, 30, 5);

  group('buildInsertRows', () {
    test('one row per valid scale, sharing insert-level fields', () {
      final rows = buildInsertRows(
        blockId: 3,
        appendId: 2,
        scales: const [
          (name: 'Mood', value: '7'),
          (name: 'Anxiety', value: ''), // blank value -> dropped
          (name: 'Tremor', value: '2.5'),
        ],
        programId: 'B',
        leftElectrodeModel: 'SenSight B33005',
        rightElectrodeModel: 'SenSight B33005',
        notes: 'felt better',
        leftStimFreq: '130',
        leftAnode: 'C',
        leftCathode: '2',
        leftAmplitude: '1.5_1',
        leftPulseWidth: '60',
        rightStimFreq: '130',
        at: stamp,
      );

      expect(rows.length, 2);
      expect(rows.map((r) => r.scaleName), ['Mood', 'Tremor']);
      expect(rows.map((r) => r.scaleValue), ['7', '2.5']);
      for (final row in rows) {
        expect(row.blockId, '3');
        expect(row.appendId, '2');
        expect(row.isInitial, '0');
        // One instant, offset included, instead of three cells that could
        // disagree. The offset is the recording machine's, so only its shape
        // is asserted.
        expect(row.acqTime, startsWith('2026-07-27T10:30:05'));
        expect(row.acqTime, matches(RegExp(r'[+-][0-9][0-9]:[0-9][0-9]$')));
        expect(row.programId, 'B');
        expect(row.leftElectrodeModel, 'SenSight B33005');
        expect(row.notes, 'felt better');
        expect(row.leftStimFreq, '130');
        expect(row.leftAmplitude, '1.5_1');
        expect(row.rightStimFreq, '130');
        expect(row.rightAmplitude, '');
      }
    });

    test('no valid scales -> a single row with empty scale fields', () {
      final rows = buildInsertRows(
        blockId: 0,
        appendId: 1,
        scales: const [(name: 'Mood', value: '   ')],
        notes: 'stim only',
        at: stamp,
      );

      expect(rows.length, 1);
      expect(rows.single.scaleName, '');
      expect(rows.single.scaleValue, '');
      expect(rows.single.isInitial, '0');
      expect(rows.single.notes, 'stim only');
    });
  });

  group('nextBlockId / nextAppendId', () {
    test('continue numbering from the max, like open_file_append', () {
      const existing = [
        SessionRow(blockId: '0', appendId: '1'),
        SessionRow(blockId: '2.0', appendId: '1'), // float-style cell
        SessionRow(blockId: 'junk', appendId: ''), // malformed -> skipped
        SessionRow(blockId: '1', appendId: '3'),
      ];
      expect(nextBlockId(existing), 3);
      expect(nextAppendId(existing), 4);
    });

    test('empty file -> block 0, session 1', () {
      expect(nextBlockId(const []), 0);
      expect(nextAppendId(const []), 1);
    });
  });

  group('session TSV round trip', () {
    test('parse -> serialize -> parse preserves every cell', () {
      final original = buildInsertRows(
        blockId: 5,
        appendId: 2,
        scales: const [(name: 'Mood', value: '4')],
        programId: 'A',
        leftElectrodeModel: 'Cartesia X',
        rightElectrodeModel: 'Cartesia X',
        notes: 'multi\nline note with a\ttab',
        leftStimFreq: '125.5',
        leftAnode: 'C',
        leftCathode: '1_2',
        leftAmplitude: '1.5_1', // split amplitude must survive verbatim
        leftPulseWidth: '60',
        rightStimFreq: '130',
        rightAnode: 'C',
        rightCathode: '9',
        rightAmplitude: '2.0',
        rightPulseWidth: '90',
        at: stamp,
      );

      final reparsed = parseSessionTsv(serializeSessionTsv(original));
      expect(reparsed.length, original.length);
      for (var i = 0; i < original.length; i++) {
        expect(reparsed[i].toMap(), original[i].toMap());
      }
      expect(reparsed.single.leftAmplitude, '1.5_1');
      expect(reparsed.single.notes, 'multi\nline note with a\ttab');
    });

    test('header is the canonical column order, in full', () {
      // Spelled out rather than spot-checked: this line IS the published
      // contract, so a column silently renamed or reordered should fail here
      // and not first in someone's analysis script.
      expect(
        serializeSessionTsv(const []).trimRight(),
        'acq_time\tblock_id\tappend_id\tis_initial\tis_final\tis_starred\t'
        'scale_name\tscale_value\tpathology\ttarget\tleft_electrode_model\t'
        'right_electrode_model\tleft_ipg_model\tright_ipg_model\t'
        'program_id\t'
        'left_stim_freq\tleft_anode\tleft_cathode\tleft_amplitude\t'
        'left_pulse_width\tright_stim_freq\tright_anode\tright_cathode\t'
        'right_amplitude\tright_pulse_width\tmedications\tnotes',
      );
    });

    test('column names are BIDS-style snake_case', () {
      // BIDS: "It is RECOMMENDED that the column names ... are written in
      // snake_case with the first letter in lower case." The `block_ID` /
      // `session_ID` / `program_ID` spellings that `readColumn` accepts are not.
      for (final column in sessionColumns) {
        expect(
          column,
          matches(RegExp(r'^[a-z][a-z0-9_]*$')),
          reason: '$column is not snake_case',
        );
      }
    });

    test('a pre-0.5.0 file with block_ID / NaN still reads', () {
      final legacy = File(
        'test/fixtures/legacy_0.4_sub-01_ses-20260203_'
        'task-programming_run-01_events.tsv',
      ).readAsStringSync();
      final rows = parseSessionTsv(legacy);

      expect(rows, isNotEmpty);
      // The pre-rename spellings resolve through `readColumn`.
      expect(rows.first.blockId, '0');
      expect(rows.first.appendId, '1');
      expect(rows.first.programId, 'B');
      expect(rows.first.leftElectrodeModel, 'Medtronic SenSight B33005');
      // The fixture has no `acq_time` column at all, only `date`, `time` and
      // a free-text `timezone`, yet reading it produces a complete instant,
      // offset included, so every consumer downstream sees one populated
      // timestamp column without knowing the source predates it.
      expect(
        rows.first.acqTime,
        '2026-02-03T09:00:00+00:00',
        reason: 'backfilled from date + time + the offset in the timezone cell',
      );
      // The offset is the recording machine's, taken from the file and never
      // this machine's, so the instant is the same wherever the file is read.
      expect(rows.first.timestamp, DateTime.utc(2026, 2, 3, 9).toLocal());
      // Display reads the wall clock as recorded, with no zone conversion.
      expect(recordedDate(rows.first.acqTime), '2026-02-03');
      expect(recordedTime(rows.first.acqTime), '09:00:00');
    });
  });
}
