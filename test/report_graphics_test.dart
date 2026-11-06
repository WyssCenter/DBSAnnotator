import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/session_docx.dart' show pngSize;
import 'package:dbs_annotator/ui/report_images.dart';
import 'package:dbs_annotator/ui/scales_chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_ranking_prefs.dart';

/// The committed export the desktop docs are built from: real clinical shape
/// (7 blocks, 5 session scales, clinical baseline), so the scoring can be
/// compared against the reference figure in
/// docs/_static/session_report_session_scales_figure.png.
List<SessionRow> _exampleRows() => parseSessionTsv(
  File('test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv')
      .readAsStringSync(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('chart spec (scoring wired into the reports)', () {
    late SessionReportData data;

    setUp(() {
      data = rankedReportData(
        _exampleRows(),
        generatedAt: DateTime(2026, 6, 26),
      );
    });

    test('plots the session scales over the recording blocks', () {
      expect(data.chart.series.keys, [
        'Obsessions',
        'Compulsions',
        'Anxiety',
        'Mood',
        'Energy',
      ]);
      expect(data.chart.xs, [1, 2, 3, 4, 5, 6, 7]);
      expect(data.chart.isEmpty, isFalse);
    });

    test('clamps the y-axis to the declared scale range', () {
      // Every scale declares 0..10, so the axis is pinned there rather than
      // hugging the data (the desktop `get_declared_scale_range`).
      expect(data.chart.yMin, 0);
      expect(data.chart.yMax, 10);
    });

    test('ranks blocks by aggregate index, best first', () {
      expect(data.chart.aggregateIndex, hasLength(7));
      // One ordering for the bands, the row shading and the printed rank: the
      // highest index is banded dark green and the next lightest green, with
      // no second notion of a winner anywhere in the document.
      expect(data.chart.bestXs, [7]);
      expect(data.chart.secondXs, [6]);
      for (final v in data.chart.aggregateIndex.values) {
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });

    test('the replicate spread is reported as the ranking resolution', () {
      // The only estimate the session offers of how much the index moves when
      // nothing changes: 0.070 between blocks 6 and 7. That is 7x the 0.010
      // separating blocks 2, 3 and 4, so a third-decimal margin is not a
      // finding and the document must say so.
      expect(data.replicateSpread, closeTo(0.070, 5e-4));
      expect(data.rankingResolutionNote, contains('0.070'));
      expect(data.rankingResolutionNote, contains('not distinguishable'));
    });

    test('the table shades by the same ranking the figure bands by', () {
      // One algorithm, so a row can never be shaded rank 1 while its Index
      // cell prints rank 2.
      expect(data.bestBlocks, data.chart.bestXs);
      expect(data.secondBlocks, data.chart.secondXs);
      expect(data.bestBlocks, isNotEmpty);
      expect(data.bestBlocks, isNot(equals(data.secondBlocks)));
    });

    test(
      'lists only the SESSION scales as targets, not clinical baselines',
      () {
        expect(data.targetsText, contains('Obsessions: min'));
        expect(
          data.targetsText,
          isNot(contains('Y-BOCS')),
          reason: 'clinical baseline scales are not session targets',
        );
      },
    );

    test('resolves the electrode rows the text describes', () {
      expect(data.initialRow, isNotNull);
      expect(data.finalRow, isNotNull);
      expect(coerceInt(data.initialRow!.isInitial), 1);
      expect(coerceInt(data.finalRow!.isInitial), isNot(1));
    });

    test('respects explicit scale prefs (max flips the ranking)', () {
      final maxPrefs = [
        for (final name in [
          'Obsessions',
          'Compulsions',
          'Anxiety',
          'Mood',
          'Energy',
        ])
          (name: name, min: 0.0, max: 10.0, mode: ScaleMode.max, custom: null),
      ];
      final flipped = buildSessionReportData(
        rows: _exampleRows(),
        scalePrefs: maxPrefs,
      );
      // Maximising instead of minimising must not pick the same best block.
      expect(flipped.chart.bestX, isNot(7));
    });

    test('a single scale is still ranked (the desktop suppresses it)', () {
      // Deliberate divergence: the desktop draws no index below two scales,
      // so a one-scale session got no green bands at all, yet a single scale
      // against its own target ranks the blocks perfectly well. The rows
      // differ in amplitude, so they are two settings, not one rated twice.
      const rows = [
        SessionRow(
          blockId: '1',
          isInitial: '0',
          scaleName: 'Tremor',
          scaleValue: '3',
          leftAmplitude: '2.0',
        ),
        SessionRow(
          blockId: '2',
          isInitial: '0',
          scaleName: 'Tremor',
          scaleValue: '1',
          leftAmplitude: '3.0',
        ),
      ];
      final one = rankedReportData(rows);
      expect(one.chart.series, hasLength(1));
      expect(one.chart.aggregateIndex, hasLength(2));
      // Two different settings here, so one block each. Default mode is min,
      // so the lower score wins.
      expect(one.chart.bestXs, [2]);
      expect(one.chart.secondXs, [1]);
      // And the table shades the SAME blocks, from the same ranking.
      expect(one.bestBlocks, [2]);
      expect(one.secondBlocks, [1]);
      // Nothing was rated twice, so the session offers no resolution estimate.
      expect(one.replicateSpread, isNull);
      expect(one.rankingResolutionNote, isNull);
    });

    test('no session scales -> an empty chart the builders can skip', () {
      final none = buildSessionReportData(
        rows: const [
          SessionRow(
            blockId: '0',
            isInitial: '1',
            scaleName: 'UPDRS',
            scaleValue: '30',
          ),
        ],
      );
      expect(none.chart.isEmpty, isTrue);
    });
  });

  group('rasterisers', () {
    test('renderScalesChartPng produces a PNG at the requested size', () async {
      final data = buildSessionReportData(rows: _exampleRows());
      final png = await renderScalesChartPng(
        data.chart,
        size: const Size(400, 200),
        pixelRatio: 2,
      );
      expect(png, isNotNull);
      expect(pngSize(png!), (800, 400));
    });

    test(
      'renderScalesChartPng returns null when there is nothing to plot',
      () async {
        final empty = buildSessionReportData(rows: const []);
        expect(await renderScalesChartPng(empty.chart), isNull);
      },
    );

    test('renderElectrodePng produces a PNG at the requested size', () async {
      final catalog = ElectrodeCatalog.fromJson(
        jsonDecode(File('schema/electrode_models.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final png = await renderElectrodePng(
        catalog.models['Medtronic SenSight B33005']!,
        'case',
        'E2b_E2c',
        size: const Size(150, 320),
        pixelRatio: 2,
      );
      // Nullable so a rasterisation failure degrades to the text fallback
      // rather than aborting the export.
      expect(png, isNotNull);
      expect(pngSize(png!), (300, 640));
    });
  });
}
