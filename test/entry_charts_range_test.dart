import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/entry_charts.dart';
import 'package:flutter_test/flutter_test.dart';

SessionRow _row(String block, String name, String value) => SessionRow(
  acqTime: '2026-01-01T09:0$block:00',
  blockId: block,
  isInitial: '0',
  scaleName: name,
  scaleValue: value,
);

void main() {
  test('a value above the declared upper bound widens the scales axis', () {
    final data = buildEntryChartData(
      [_row('1', 'Tremor', '4'), _row('2', 'Tremor', '12')],
      scalePrefs: const [
        (
          name: 'Tremor',
          min: 0.0,
          max: 10.0,
          mode: ScaleMode.min,
          custom: null,
        ),
      ],
    );
    expect(data.panels.first.yMin, 0);
    expect(data.panels.first.yMax, 12);
  });

  test('a scale without bounds is not drawn outside another scale\'s', () {
    final data = buildEntryChartData(
      [
        _row('1', 'Tremor', '4'),
        _row('2', 'Mood', '25'),
        _row('3', 'Mood', '-3'),
      ],
      scalePrefs: const [
        (
          name: 'Tremor',
          min: 0.0,
          max: 10.0,
          mode: ScaleMode.min,
          custom: null,
        ),
      ],
    );
    expect(data.panels.first.yMin, -3);
    expect(data.panels.first.yMax, 25);
  });

  test('values inside the declared bounds leave the axis at the bounds', () {
    final data = buildEntryChartData(
      [_row('1', 'Tremor', '4')],
      scalePrefs: const [
        (
          name: 'Tremor',
          min: 0.0,
          max: 10.0,
          mode: ScaleMode.min,
          custom: null,
        ),
      ],
    );
    expect(data.panels.first.yMin, 0);
    expect(data.panels.first.yMax, 10);
  });

  test('reversed declared bounds are swapped', () {
    final data = buildEntryChartData(
      [_row('1', 'Tremor', '4')],
      scalePrefs: const [
        (
          name: 'Tremor',
          min: 10.0,
          max: 0.0,
          mode: ScaleMode.min,
          custom: null,
        ),
      ],
    );
    expect(data.panels.first.yMin, 0);
    expect(data.panels.first.yMax, 10);
  });

  test('a declared scale without data still contributes its bounds', () {
    final data = buildEntryChartData(
      [_row('1', 'Tremor', '4')],
      scalePrefs: const [
        (
          name: 'Tremor',
          min: 0.0,
          max: 10.0,
          mode: ScaleMode.min,
          custom: null,
        ),
        (name: 'Mood', min: 0.0, max: 100.0, mode: ScaleMode.max, custom: null),
      ],
    );
    expect(data.panels.first.yMin, 0);
    expect(data.panels.first.yMax, 100);
  });
}
