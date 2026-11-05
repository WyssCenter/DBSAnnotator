import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/ui/scales_chart_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const spec = ScalesChartSpec(
    xs: [1, 2, 3],
    series: {
      'Tremor': {1: 3.0, 2: 4.0, 3: 5.0},
    },
    aggregateIndex: {},
    amplitude: {},
    bestXs: [],
    secondXs: [],
    yMin: 0,
    yMax: 10,
    title: 'Session scales',
    xLabel: 'Block',
    yLabel: 'Score',
  );

  testWidgets('a size with no room for the plot area yields no image', (
    tester,
  ) async {
    final png = await tester.runAsync(
      () => renderScalesChartPng(spec, size: const Size(30, 30)),
    );
    expect(png, isNull);
  });

  testWidgets('a normal size yields a PNG', (tester) async {
    final png = await tester.runAsync(
      () =>
          renderScalesChartPng(spec, size: const Size(800, 376), pixelRatio: 1),
    );
    expect(png, isNotNull);
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
  });
}
