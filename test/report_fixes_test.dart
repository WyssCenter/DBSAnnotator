import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/docx_ooxml.dart';
import 'package:dbs_annotator/report/entry_charts.dart';
import 'package:dbs_annotator/report/longitudinal_data.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a value outside the declared scale range widens the chart', () {
    final spec = buildScalesChartSpec(
      timeline: {
        'VAS': {1: 55.0, 2: 3.0},
      },
      prefs: [
        scalePrefFromStrings(name: 'VAS', min: '0', max: '10', mode: 'min'),
      ],
    );

    expect(spec.yMin, 0);
    expect(spec.yMax, 55);
  });

  test('a declared range wider than the data is kept', () {
    final spec = buildScalesChartSpec(
      timeline: {
        'VAS': {1: 4.0, 2: 6.0},
      },
      prefs: [
        scalePrefFromStrings(name: 'VAS', min: '0', max: '10', mode: 'min'),
      ],
    );

    expect(spec.yMin, 0);
    expect(spec.yMax, 10);
  });

  group('a session spanning two days', () {
    final data = buildSessionReportData(
      rows: [
        const SessionRow(acqTime: '2026-07-29T09:00:00', blockId: '1'),
        const SessionRow(acqTime: '2026-07-30T08:30:00', blockId: '2'),
      ],
    );

    test('the stamp names the end date', () {
      expect(data.sessionStamp, '2026-07-29 09:00 to 2026-07-30 08:30');
    });

    test('a row on another day carries its date in the Time cell', () {
      final times = [for (final r in data.tableData) r[1].split('\n')];
      expect([for (final t in times) t.first], contains('09:00:00'));
      expect(
        times.any((t) => t.take(2).join(' ') == '2026-07-30 08:30:00'),
        isTrue,
      );
    });
  });

  group('notes across midnight', () {
    final data = buildSessionReportData(
      rows: [
        const SessionRow(acqTime: '2026-07-29T23:00:00', blockId: '1'),
        const SessionRow(acqTime: '2026-07-30T00:30:00', blockId: '2'),
      ],
      notes: const [
        Annotation(acqTime: '2026-07-30T00:10:00', notes: 'N2'),
        Annotation(acqTime: '2026-07-29T23:30:00', notes: 'N1'),
        Annotation(acqTime: '2026-07-31T01:00:00', notes: 'outside'),
        Annotation(acqTime: '2026-07-28T22:00:00', notes: 'before'),
      ],
    );

    test('notes from both days interleave with the blocks in order', () {
      final order = [
        for (final r in data.tableData)
          if (r[2] != 'R') r[0].isNotEmpty ? 'B${r[0]}' : r.last,
      ];
      expect(order, ['B1', 'N1', 'N2', 'B2']);
    });

    test('a later-day note carries its date on its own line', () {
      final note = data.tableData.firstWhere((r) => r.last == 'N2');
      expect(note[1], '2026-07-30\n00:10:00');
    });
  });

  test('a value outside a declared longitudinal range widens the axis', () {
    final data = buildLongitudinalReportData(
      files: {
        'sub-07_ses-20260101_task-programming_run-01_beh.tsv': const [
          SessionRow(
            acqTime: '2026-01-01T09:10:00',
            blockId: '1',
            isInitial: '0',
            scaleName: 'Tremor',
            scaleValue: '55',
            leftAmplitude: '2.0',
          ),
        ],
      },
      scalePrefs: const [
        (name: 'Tremor', min: 0, max: 10, mode: ScaleMode.min, custom: null),
      ],
    );

    expect(data.sessionChart.yMin, 0);
    expect(data.sessionChart.yMax, 55);
  });

  test('a one-day session keeps the short stamp', () {
    final data = buildSessionReportData(
      rows: [
        const SessionRow(acqTime: '2026-07-29T09:00:00', blockId: '1'),
        const SessionRow(acqTime: '2026-07-29T09:30:00', blockId: '2'),
      ],
    );

    expect(data.sessionStamp, '2026-07-29, 09:00-09:30');
  });

  test('a split amplitude is summed to 0.1 mA in the summary', () {
    final data = buildSessionReportData(
      rows: [
        const SessionRow(
          acqTime: '2026-07-29T09:00:00',
          blockId: '1',
          isInitial: '0',
          leftCathode: '1_2_3',
          leftAmplitude: '1.67_1.67_1.67',
        ),
      ],
    );

    expect(data.lastConfig['Left'], contains('= 5.0 mA'));
    expect(data.lastConfig['Left'], isNot(contains('5.01')));
  });

  test('tcBorders precedes shd in a cell', () {
    final cell = docxCell('x', fill: 'D9D9D9', topRule: true, widthTwips: 900);

    expect(cell.indexOf('<w:tcBorders>'), lessThan(cell.indexOf('<w:shd')));
    expect(cell.indexOf('<w:tcW'), lessThan(cell.indexOf('<w:tcBorders>')));
  });

  test('rows with an empty first cell are not merged together', () {
    final xml = docxTable(
      null,
      [
        ['', 'a'],
        ['', 'b'],
        ['1', 'c'],
        ['1', 'd'],
      ],
      mergeDownColumns: {0},
      weights: [1, 1],
      contentTwips: 1000,
    );

    expect('<w:vMerge/>'.allMatches(xml).length, 1);
    expect('<w:vMerge w:val="restart"/>'.allMatches(xml).length, 3);
  });

  test('untimed blocks are plotted once, not once per row', () {
    final data = buildEntryChartData([
      for (final b in ['1', '1', '2'])
        SessionRow(blockId: b, isInitial: '0', leftAmplitude: '2'),
    ]);

    expect(data.xs, [1, 2]);
  });
}
