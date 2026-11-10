/// The longitudinal report: two date-axis figures, a per-visit table, and both
/// formats.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/longitudinal_data.dart';
import 'package:dbs_annotator/report/longitudinal_pdf.dart';
import 'package:dbs_annotator/report/report_data.dart' show kVisitsIndexHeader;
import 'package:flutter_test/flutter_test.dart';

String _part(List<int> bytes, String name) => utf8.decode(
  ZipDecoder()
      .decodeBytes(bytes)
      .files
      .firstWhere((f) => f.name == name)
      .content,
);

/// Two visits of the same patient: a clinical baseline plus rated blocks, so
/// both figures and the delta column have something to show.
Map<String, List<SessionRow>> _twoVisits() => {
  'sub-07_ses-20260101_task-programming_run-01_beh.tsv': const [
    SessionRow(
      acqTime: '2026-01-01T09:00:00',
      blockId: '0',
      isInitial: '1',
      scaleName: 'UPDRS-III',
      scaleValue: '40',
    ),
    SessionRow(
      acqTime: '2026-01-01T09:10:00',
      blockId: '1',
      isInitial: '0',
      scaleName: 'Tremor',
      scaleValue: '6',
      leftAmplitude: '2.0',
      leftStimFreq: '130',
      leftPulseWidth: '60',
      programId: 'A',
    ),
    SessionRow(
      acqTime: '2026-01-01T09:20:00',
      blockId: '2',
      isInitial: '0',
      scaleName: 'Tremor',
      scaleValue: '4',
      leftAmplitude: '3.0',
      leftStimFreq: '130',
      leftPulseWidth: '60',
      programId: 'A',
    ),
  ],
  'sub-07_ses-20260615_task-programming_run-02_events.tsv': const [
    SessionRow(
      acqTime: '2026-06-15T10:00:00',
      blockId: '0',
      isInitial: '1',
      scaleName: 'UPDRS-III',
      scaleValue: '28',
    ),
    SessionRow(
      acqTime: '2026-06-15T10:10:00',
      blockId: '1',
      isInitial: '0',
      scaleName: 'Tremor',
      scaleValue: '3',
      leftAmplitude: '3.5',
      leftStimFreq: '130',
      leftPulseWidth: '60',
      programId: 'B',
    ),
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LongitudinalReportData data;
  setUp(
    () => data = buildLongitudinalReportData(
      files: _twoVisits(),
      generatedAt: DateTime(2026, 7, 1),
    ),
  );

  test('visits are ordered by date and carry both kinds of scale', () {
    expect(data.visits.map((v) => v.date), ['2026-01-01', '2026-06-15']);
    expect(data.visits.first.clinicalScales, {'UPDRS-III': 40.0});
    expect(data.visits.first.sessionScales['Tremor'], {1: 6.0, 2: 4.0});
    expect(data.visits.first.blocks, [1, 2]);
    expect(data.patientId, '07');
  });

  test('the clinical figure has one point per VISIT, labelled by date', () {
    final chart = data.clinicalChart;
    expect(chart.series.keys, ['UPDRS-III']);
    // Two visits, so two x positions: not two blocks, and not a block index
    // concatenated across files.
    expect(chart.xs, [0, 1]);
    expect(chart.xTickLabels[0], '2026-01-01');
    expect(chart.xTickLabels[1], '2026-06-15');
  });

  test('session targets bound the session figure, never the clinical one', () {
    // A 0-10 session-scale range applied to UPDRS-III 40 drew an empty chart.
    final ranked = buildLongitudinalReportData(
      files: _twoVisits(),
      scalePrefs: const [
        (name: 'Tremor', min: 0, max: 10, mode: ScaleMode.min, custom: null),
      ],
    );
    expect(ranked.sessionChart.yMax, 10);
    expect(ranked.clinicalChart.yMin, 0);
    expect(ranked.clinicalChart.yMax, greaterThanOrEqualTo(40));
  });

  test('with targets, two configurations are marked across all visits', () {
    final ranked = buildLongitudinalReportData(
      files: _twoVisits(),
      scalePrefs: const [
        (name: 'Tremor', min: 0, max: 10, mode: ScaleMode.min, custom: null),
      ],
    );
    // Not two per visit: the ranking runs over every visit together.
    final marked = [
      for (final fills in ranked.rankedBlocks.values) ...fills.values,
    ];
    expect(marked.toSet().length, 2, reason: 'one best, one second');
    expect(ranked.sessionChart.bestXs, isNotEmpty);
    expect(ranked.sessionChart.secondXs, isNotEmpty);
    // The table prints the same overall rank the shading shows: the first
    // visit's best block is second overall, so it must not read "rank 1".
    final first = ranked.visits.first;
    final col = ranked.tableHeadersFor(first).indexOf(kVisitsIndexHeader);
    final cells = [
      for (final r in ranked.tableRowsFor(first))
        if (r[col].isNotEmpty) r[col],
    ];
    expect(cells.any((c) => c.contains('(rank 2)')), isTrue);
    expect(cells.any((c) => c.contains('(rank 1)')), isFalse);
    // Without targets nothing is ranked.
    expect(data.rankedBlocks, isEmpty);
    // The report names the targets it ranked by, and none when it did not.
    expect(ranked.rankingTargets, contains('Tremor: min of 0-10'));
    expect(data.rankingTargets, isEmpty);
  });

  test('neither figure carries an index or bands', () {
    // The aggregate index is normalised WITHIN a session, so a value from
    // January and one from June were never on the same scale. The desktop
    // passes show_general_index=False here for the same reason.
    expect(data.clinicalChart.aggregateIndex, isEmpty);
    expect(data.clinicalChart.bestXs, isEmpty);
    expect(data.clinicalChart.secondXs, isEmpty);
    expect(data.sessionChart.aggregateIndex, isEmpty);
    expect(data.sessionChart.bestXs, isEmpty);
  });

  test('the session figure has one point per (visit, block)', () {
    final chart = data.sessionChart;
    // 2 blocks + 1 block = 3 positions.
    expect(chart.xs, [0, 1, 2]);
    expect(chart.series['Tremor'], {0: 6.0, 1: 4.0, 2: 3.0});
    // Each tick is the block number; the visit's date is printed once,
    // centred under its blocks, so nothing has to be rotated to fit.
    expect(chart.xTickLabels, {0: '1', 1: '2', 2: '1'});
    expect(chart.xGroups, [
      (from: 0, to: 1, label: '2026-01-01'),
      (from: 2, to: 2, label: '2026-06-15'),
    ]);
  });

  test('the visit table reports the programme and the change', () {
    expect(data.visitTable, hasLength(2));
    expect(data.visitTable[0][1], '2026-01-01');
    expect(data.visitTable[0][3], '2', reason: 'two blocks');
    expect(data.visitTable[0][4], 'UPDRS-III: 40');
    expect(data.visitTable[1][4], 'UPDRS-III: 28');
    // The latest visit's programme is the page-1 summary's, not repeated.
    expect(data.visitTable[1][2], kSeeSummary);
    final summary = latestVisitSummary(data)!;
    expect(summary.heading, contains('2026-06-15'));
    expect(summary.lines.join('\n'), contains('3.5 mA'));
    expect(summary.lines, contains('Group: B'));
    // Left and Right on their own lines of one cell, read down not across.
    // A side with nothing recorded is left out rather than printed as "-".
    final lines = data.visitTable[0][2].split('\n');
    expect(lines.first, startsWith('Left: '));
    expect(lines.last, 'Group: A');
  });

  test('every clinical scale is listed, one per line', () {
    SessionRow baseline(String day, String name, String value) => SessionRow(
      acqTime:
          '2026-$day'
          'T09:00:00',
      blockId: '0',
      isInitial: '1',
      scaleName: name,
      scaleValue: value,
    );
    final two = buildLongitudinalReportData(
      files: {
        'sub-07_ses-20260101_task-programming_run-01_beh.tsv': [
          baseline('01-01', 'Y-BOCS', '28'),
          baseline('01-01', 'MADRS', '24'),
        ],
        'sub-07_ses-20260615_task-programming_run-01_beh.tsv': [
          baseline('06-15', 'Y-BOCS', '21'),
          baseline('06-15', 'MADRS', '17'),
        ],
      },
    );
    // Not one scale picked on some rule: all of them, one per line.
    expect(two.visitTable.last[4], 'Y-BOCS: 21\nMADRS: 17');
  });

  test('a mixed-patient import is reported, not silently merged', () {
    final mixed = buildLongitudinalReportData(
      files: {
        ..._twoVisits(),
        'sub-99_ses-20260701_task-programming_run-01_beh.tsv': const [
          SessionRow(
            acqTime: '2026-07-01T11:00:00',
            blockId: '0',
            isInitial: '1',
            scaleName: 'UPDRS-III',
            scaleValue: '30',
          ),
        ],
      },
    );
    expect(mixed.mismatchedPatients, isNotEmpty);
  });

  test('both formats build', () async {
    final pdf = await buildLongitudinalPdf(data: data);
    expect(pdf.bytes.sublist(0, 4), '%PDF'.codeUnits);

    final bytes = buildLongitudinalDocx(data: data);
    final names = ZipDecoder()
        .decodeBytes(bytes)
        .files
        .map((f) => f.name)
        .toList();
    expect(
      names,
      containsAll(<String>[
        '[Content_Types].xml',
        'word/document.xml',
        'word/footer1.xml',
        'word/styles.xml',
        'docProps/core.xml',
      ]),
    );
    final doc = _part(bytes, 'word/document.xml');
    expect(doc, contains('Longitudinal report'));
    expect(doc, contains('Clinical scales by visit'));
    expect(
      doc,
      contains('Symptom and side effect ratings by visit and configuration'),
    );
    expect(doc, contains('UPDRS-III: 28'));
    // Provenance is an appendix, not the content.
    expect(doc, contains('Source files'));
  });

  test('no visits still yields a valid document', () async {
    final empty = buildLongitudinalReportData(files: const {});
    expect(empty.isEmpty, isTrue);
    final pdf = await buildLongitudinalPdf(data: empty);
    expect(pdf.bytes.sublist(0, 4), '%PDF'.codeUnits);
    expect(
      _part(buildLongitudinalDocx(data: empty), 'word/document.xml'),
      contains('No session file was imported.'),
    );
  });

  test('a real committed session imports as one visit', () {
    const name = 'sub-01_ses-20260203_task-programming_run-01_beh.tsv';
    final real = buildLongitudinalReportData(
      files: {
        name: parseSessionTsv(File('test/fixtures/$name').readAsStringSync()),
      },
    );
    expect(real.visits, hasLength(1));
    expect(real.visits.first.blocks, [1, 2, 3, 4, 5, 6, 7]);
    expect(real.visits.first.clinicalScales.keys, contains('UPDRS-III'));
    expect(real.sessionChart.xs, hasLength(7));
  });
}
