import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/session_docx.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime.utc(2026, 2, 3, 9);

  SessionAuthoring visit() => SessionAuthoring()
    ..addInsert(
      isInitial: true,
      stim: const {},
      scales: const [(name: 'UPDRS-III', value: '32')],
      pathology: 'PD',
      target: 'STN',
      leftIpgModel: 'Medtronic Percept PC',
      rightIpgModel: 'Medtronic Percept PC',
      medications: 'Levodopa 100 mg three times a day',
      at: at,
    )
    ..addInsert(
      isInitial: false,
      stim: const {'left_amplitude': '2'},
      pathology: 'PD',
      target: 'STN',
      leftIpgModel: 'Medtronic Percept PC',
      rightIpgModel: 'Medtronic Percept PC',
      at: at,
    )
    ..addInsert(
      isInitial: false,
      stim: const {'left_amplitude': '3'},
      pathology: 'PD',
      target: 'STN',
      leftIpgModel: 'Medtronic Percept PC',
      rightIpgModel: 'Medtronic Percept PC',
      starred: true,
      at: at,
    );

  test('pathology, target, IPG and medications round-trip', () {
    final back = parseSessionTsv(visit().serialize());
    expect(sessionValueIn(back, (r) => r.pathology), 'PD');
    expect(sessionValueIn(back, (r) => r.target), 'STN');
    expect(
      sessionValueIn(back, (r) => r.rightIpgModel),
      'Medtronic Percept PC',
    );
    expect(back.first.medications, 'Levodopa 100 mg three times a day');
    expect(back.skip(1).every((r) => r.medications.isEmpty), isTrue);
  });

  test('any number of blocks can be starred and unstarred', () {
    final a = visit();
    expect(starredBlocksIn(a.rows), {'2'});
    a.setStarred('1', true);
    expect(starredBlocksIn(parseSessionTsv(a.serialize())), {'1', '2'});
    a.setStarred('2', false);
    expect(starredBlocksIn(a.rows), {'1'});
    expect(a.rows.length, 3);
  });

  test('the report names the session details, medications and stars', () {
    final data = buildSessionReportData(rows: visit().rows);
    expect(
      data.sessionDetails,
      'DBS indication: PD    Target: STN    IPG: Medtronic Percept PC',
    );
    expect(data.medications, 'Levodopa 100 mg three times a day');
    expect(data.hasStars, isTrue);
    expect(data.tableData.map((r) => r.first).toSet(), {'1', '2 *'});

    final doc = utf8.decode(
      ZipDecoder()
          .decodeBytes(buildSessionDocx(data: data, subjectId: '01'))
          .findFile('word/document.xml')!
          .readBytes()!,
    );
    expect(doc, contains('DBS indication: PD'));
    expect(doc, contains('Medications: Levodopa'));
    expect(doc, contains('Starred by the clinician during the visit'));
  });

  test('two different IPGs are named per side', () {
    final a = SessionAuthoring()
      ..addInsert(
        isInitial: false,
        stim: const {},
        leftIpgModel: 'Medtronic Activa SC',
        rightIpgModel: 'Abbott Infinity 5',
        at: at,
      );
    expect(
      buildSessionReportData(rows: a.rows).sessionDetails,
      'IPG: left Medtronic Activa SC, right Abbott Infinity 5',
    );
  });

  test('without stars the report adds no star legend', () {
    final a = visit()..setStarred('2', false);
    final data = buildSessionReportData(rows: a.rows);
    expect(data.hasStars, isFalse);
    expect(data.tableData.map((r) => r.first).toSet(), {'1', '2'});
  });

  test('a file written before these columns opens with them empty', () {
    const older =
        'acq_time\tblock_id\tappend_id\tis_initial\tis_final\tscale_name\t'
        'scale_value\tleft_electrode_model\tright_electrode_model\tprogram_id\t'
        'left_stim_freq\tleft_anode\tleft_cathode\tleft_amplitude\t'
        'left_pulse_width\tright_stim_freq\tright_anode\tright_cathode\t'
        'right_amplitude\tright_pulse_width\tnotes\n'
        '2026-02-03T09:00:00+00:00\t0\t1\t0\t0\tTremor\t2\t\t\t\t\t\t\t2\t\t\t'
        '\t\t\t\t\n';
    final rows = parseSessionTsv(older);
    expect(rows.single.scaleValue, '2');
    expect(sessionValueIn(rows, (r) => r.pathology), '');
    expect(starredBlocksIn(rows), isEmpty);
  });
}
