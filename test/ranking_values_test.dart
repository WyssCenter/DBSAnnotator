/// Pins the aggregate index to exact numbers over the committed example, not
/// just to which block wins. The other tests assert only the ranking's
/// outcome, so a regression that shifted every value while preserving their
/// order (a changed weight, clip or default bound) would pass silently.
library;

import 'dart:io';

import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_ranking_prefs.dart';

List<SessionRow> _example() => parseSessionTsv(
  File('test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv')
      .readAsStringSync(),
);

void main() {
  late SessionReportData data;

  setUp(
    () =>
        data = rankedReportData(_example(), generatedAt: DateTime(2026, 2, 3)),
  );

  test('the aggregate index per block, to three decimals', () {
    // Four MDS-UPDRS III items, all mode `min` over 0..4, so each block scores
    // the mean of (1 - value/4) across its four ratings.
    const expected = {
      1: 0.375,
      2: 0.500,
      3: 0.4375,
      4: 0.4375,
      5: 0.250,
      6: 0.625,
      7: 0.750,
    };
    expect(data.chart.aggregateIndex.keys, expected.keys);
    for (final e in expected.entries) {
      expect(
        data.chart.aggregateIndex[e.key],
        closeTo(e.value, 5e-4),
        reason: 'block ${e.key}',
      );
    }
  });

  test('the ranking margin is smaller than the session\'s own noise', () {
    // Blocks 6 and 7 are byte-identical in all ten stimulation columns, rated
    // 9 s apart, so the gap between them measures re-rating noise, not any
    // stimulation effect. It is also the report's "optimal" vs "second-best".
    final idx = data.chart.aggregateIndex;
    final replicateSpread = (idx[7]! - idx[6]!).abs();
    final betweenSettings = (idx[2]! - idx[3]!).abs();
    expect(replicateSpread, closeTo(0.125, 5e-4));
    expect(betweenSettings, closeTo(0.0625, 5e-4));
    expect(
      replicateSpread,
      greaterThan(betweenSettings),
      reason:
          'within-setting re-rating varies more than blocks 2 vs 3 do, '
          'so a rank order at this resolution is not defensible',
    );
  });

  test('the worked example is 7 recording blocks over 6 distinct settings', () {
    // Blocks 6 and 7 are the identical pair; every other block differs.
    expect(data.numConfigs, 7);
    expect(data.numDistinctConfigs, 6);
    expect(configCountText(data), '7 (6 distinct settings)');
  });

  test('the session date and clock span come from the rows', () {
    expect(data.sessionDate, '2026-02-03');
    expect(data.generatedOn, '2026-02-03');
    expect(data.startTime, isNotEmpty);
    expect(data.sessionStamp, contains('2026-02-03'));
    // ASCII only: generated text must survive the PDF's Latin-1 fallback.
    expect(data.sessionStamp.runes.every((r) => r < 0x80), isTrue);
  });
}
