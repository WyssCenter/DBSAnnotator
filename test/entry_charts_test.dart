import 'dart:io';

import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/report/entry_charts.dart';
import 'package:flutter_test/flutter_test.dart';

List<SessionRow> _example() => parseSessionTsv(
  File('test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv')
      .readAsStringSync(),
);

void main() {
  group('buildEntryChartData over the committed example', () {
    late EntryChartData data;

    setUp(() => data = buildEntryChartData(_example()));

    test('x positions are the recording blocks, baseline excluded', () {
      // The example has blocks 0..7 with 0 as the is_initial baseline.
      expect(data.xs, [1, 2, 3, 4, 5, 6, 7]);
    });

    test('every block gets an HH:MM tick label', () {
      expect(data.xLabels.length, data.xs.length);
      for (final label in data.xLabels.values) {
        expect(label, matches(RegExp(r'^\d{2}:\d{2}$')));
      }
    });

    test('tick labels are the recorded wall clock, not this machine\'s', () {
      // The fixture records +00:00, so anywhere but UTC the instant converted
      // to local time is a different hour, and the axis would then contradict
      // the entries table printed directly beneath it.
      expect(data.xLabels[1], '09:03');
      expect(data.xLabels[7], '09:14');
    });

    test('produces exactly the four panels, in the default order', () {
      expect(data.panels.map((p) => p.id), kEntryPanelIds);
      expect(data.panels.map((p) => p.title), [
        'Session scales',
        'Amplitude (mA)',
        'Pulse width (µs)',
        'Frequency (Hz)',
      ]);
    });

    test('the scales panel carries one series per session scale', () {
      final scales = data.panels.first;
      expect(
        scales.series.keys,
        containsAll(['Obsessions', 'Compulsions', 'Anxiety', 'Mood', 'Energy']),
      );
    });

    test('amplitude sums split values instead of plotting the first part', () {
      final amp = data.panels[1];
      // Block 1 left is "3.0_2.0" -> 5.0 mA total, which is the clinically
      // meaningful number; plotting 3.0 would understate the dose.
      expect(amp.series['Left']![1], closeTo(5.0, 0.001));
      // Block 4 right splits three ways, "2.0_2.0_2.0" -> 6.0. Since v0.5.0
      // encodeAmplitude distributes the rounding remainder so the parts sum
      // exactly to the dose; amplitude_total_test.dart covers that directly,
      // and the legacy fixture still carries independently-rounded parts.
      expect(amp.series['Right']![4], closeTo(6.0, 0.001));
    });

    test('pulse width and frequency read through their unit suffixes', () {
      expect(data.panels[2].series['Left']![1], 60);
      expect(data.panels[3].series['Left']![1], 130);
    });

    test('y ranges are padded so a flat series still has an axis', () {
      // Frequency never changes in the example (125 throughout).
      final freq = data.panels[3];
      expect(freq.yMax, greaterThan(freq.yMin));
    });
  });

  test('declared scale bounds win over the data range', () {
    const rows = [
      SessionRow(
        acqTime: '2026-01-01T09:00:00',
        blockId: '1',
        isInitial: '0',
        scaleName: 'Tremor',
        scaleValue: '4',
      ),
    ];
    final auto = buildEntryChartData(rows);
    final declared = buildEntryChartData(
      rows,
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
    expect(declared.panels.first.yMin, 0);
    expect(declared.panels.first.yMax, 10);
    expect(auto.panels.first.yMax, isNot(10));
    expect(declared.bestXs, [1], reason: 'the only rated block is the best');
    expect(auto.bestXs, isEmpty, reason: 'no targets, so nothing is ranked');
  });

  test('blocks are ordered by time, not by block id', () {
    // A TSV whose block ids do not ascend with the clock (e.g. re-opened file).
    const rows = [
      SessionRow(
        acqTime: '2026-01-01T10:00:00',
        blockId: '7',
        isInitial: '0',
        leftStimFreq: '130',
      ),
      SessionRow(
        acqTime: '2026-01-01T09:00:00',
        blockId: '3',
        isInitial: '0',
        leftStimFreq: '120',
      ),
    ];
    final data = buildEntryChartData(rows);
    expect(data.xs, [3, 7], reason: '09:00 must precede 10:00');
  });

  test('rows with no parseable timestamp still appear, ordered by block', () {
    const rows = [
      SessionRow(blockId: '2', isInitial: '0', leftStimFreq: '130'),
      SessionRow(blockId: '1', isInitial: '0', leftStimFreq: '130'),
    ];
    final data = buildEntryChartData(rows);
    expect(data.xs, [1, 2]);
    expect(data.xLabels, isEmpty, reason: 'no time to label with');
  });

  test('empty input yields empty panels rather than throwing', () {
    final data = buildEntryChartData(const []);
    expect(data.xs, isEmpty);
    expect(data.panels, hasLength(4));
    for (final p in data.panels) {
      expect(p.series, isEmpty);
    }
  });

  group('orderPanels', () {
    final panels = buildEntryChartData(_example()).panels;

    test('applies a persisted order', () {
      final out = orderPanels(panels, ['freq', 'scales']);
      expect(out.map((p) => p.id).take(2), ['freq', 'scales']);
      expect(out, hasLength(4), reason: 'the rest are appended, not dropped');
    });

    test('a stale preference cannot lose a panel', () {
      final out = orderPanels(panels, ['gone', 'freq', 'alsoGone']);
      expect(out.first.id, 'freq');
      expect(out.map((p) => p.id).toSet(), kEntryPanelIds.toSet());
    });

    test('null or empty keeps the default order', () {
      expect(orderPanels(panels, null).map((p) => p.id), kEntryPanelIds);
      expect(orderPanels(panels, const []).map((p) => p.id), kEntryPanelIds);
    });
  });
}
