import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final stamp = DateTime(2026, 7, 29, 9, 15, 0);
  const stim = {
    'left_stim_freq': '130',
    'left_anode': 'case',
    'left_cathode': 'E1a_E1b',
    'left_amplitude': '2.5',
    'left_pulse_width': '60',
    'right_stim_freq': '125',
    'right_anode': 'case',
    'right_cathode': 'E2',
    'right_amplitude': '1.5_1',
    'right_pulse_width': '90',
  };

  test(
    'two recording inserts: blocks 0 then 1, same session, is_initial 0',
    () {
      final a = SessionAuthoring();
      expect(a.blockId, 0);
      expect(a.appendId, 1);

      final first = a.addInsert(isInitial: false, stim: stim, at: stamp);
      final second = a.addInsert(isInitial: false, stim: stim, at: stamp);

      expect(first.single.blockId, '0');
      expect(second.single.blockId, '1');
      for (final row in [...first, ...second]) {
        expect(row.appendId, '1');
        expect(row.isInitial, '0');
        expect(row.leftCathode, 'E1a_E1b');
        expect(row.rightAmplitude, '1.5_1');
      }
      expect(a.blockId, 2); // Desktop: block_id += 1 after each write.
      expect(a.rows.length, 2);
    },
  );

  test('baseline insert writes is_initial 1 (write_clinical_scales)', () {
    final a = SessionAuthoring();
    final rows = a.addInsert(
      isInitial: true,
      stim: stim,
      scales: const [(name: 'MDS-UPDRS Part III', value: '32')],
      programId: 'A',
      leftElectrodeModel: 'SenSight B33005',
      rightElectrodeModel: 'SenSight B33005',
      notes: 'pre-programming baseline',
      at: stamp,
    );
    expect(rows.single.isInitial, '1');
    expect(rows.single.scaleName, 'MDS-UPDRS Part III');
    expect(rows.single.scaleValue, '32');
    expect(rows.single.programId, 'A');
  });

  test('replacing rewrites a block in place and keeps the numbering', () {
    final a = SessionAuthoring();
    a.addInsert(
      isInitial: true,
      stim: stim,
      scales: const [(name: 'MDS-UPDRS Part III', value: '32')],
      at: stamp,
    );
    a.addInsert(isInitial: false, stim: stim, at: stamp);
    final rewritten = a.addInsert(
      isInitial: true,
      stim: stim,
      scales: const [
        (name: 'MDS-UPDRS Part III', value: '30'),
        (name: 'PDQ-39', value: '41'),
      ],
      at: stamp,
      replacing: 0,
    );
    expect(rewritten.map((r) => r.blockId), ['0', '0']);
    expect(a.rows.map((r) => (r.blockId, r.scaleValue)), [
      ('0', '30'),
      ('0', '41'),
      ('1', ''),
    ]);
    expect(a.blockId, 2);
  });

  test('baseline drops unnamed scales, recording keeps them '
      '(is_valid vs has_value)', () {
    const scales = [(name: '   ', value: '5'), (name: 'Tremor', value: '2')];

    final baseline = buildInsertRows(
      blockId: 0,
      appendId: 1,
      isInitial: true,
      scales: scales,
      at: stamp,
    );
    expect(baseline.map((r) => r.scaleName), ['Tremor']);

    final recording = buildInsertRows(
      blockId: 0,
      appendId: 1,
      scales: scales,
      at: stamp,
    );
    expect(recording.length, 2);
  });

  test('loadExisting continues numbering like open_file_append', () {
    final existing = serializeSessionTsv([
      ...buildInsertRows(blockId: 3, appendId: 1, at: stamp),
      ...buildInsertRows(blockId: 4, appendId: 2, at: stamp),
    ]);

    final a = SessionAuthoring()..loadExisting(parseSessionTsv(existing));
    expect(a.rows.length, 2);
    expect(a.blockId, 5);
    expect(a.appendId, 3);

    final inserted = a.addInsert(isInitial: false, stim: stim, at: stamp);
    expect(inserted.single.blockId, '5');
    expect(inserted.single.appendId, '3');
    expect(a.blockId, 6);
    expect(a.rows.length, 3);
  });

  test('serialize -> parse round-trips every cell', () {
    final a = SessionAuthoring();
    a.addInsert(
      isInitial: true,
      stim: stim,
      scales: const [(name: 'MDS-UPDRS Part III', value: '32')],
      leftElectrodeModel: 'Cartesia X',
      rightElectrodeModel: 'Cartesia X',
      notes: 'multi\nline\twith tab',
      at: stamp,
    );
    a.addInsert(isInitial: false, stim: stim, at: stamp);

    final reparsed = parseSessionTsv(a.serialize());
    expect(reparsed.length, a.rows.length);
    for (var i = 0; i < a.rows.length; i++) {
      expect(reparsed[i].toMap(), a.rows[i].toMap());
    }

    // Reloading the serialized document continues numbering correctly.
    final b = SessionAuthoring()..loadExisting(parseSessionTsv(a.serialize()));
    expect(b.blockId, 2);
    expect(b.appendId, 2);
  });

  test('a 2-scale insert yields 2 rows sharing block and session', () {
    final a = SessionAuthoring();
    final rows = a.addInsert(
      isInitial: false,
      stim: stim,
      scales: const [
        (name: 'Rigidity', value: '3'),
        (name: 'Tremor', value: '1.5'),
      ],
      at: stamp,
    );

    expect(rows.length, 2);
    expect(rows.map((r) => r.scaleName), ['Rigidity', 'Tremor']);
    expect(rows.map((r) => r.scaleValue), ['3', '1.5']);
    expect(rows.map((r) => r.blockId).toSet(), {'0'});
    expect(rows.map((r) => r.appendId).toSet(), {'1'});
    // The NEXT insert still advances by one block, not one per row.
    expect(a.blockId, 1);
  });
}
