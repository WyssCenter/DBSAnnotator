import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/ui/session/entries_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two blocks, three scales each: the shape the table has to keep readable.
const _rows = [
  SessionRow(
    blockId: '1',
    isInitial: '0',
    acqTime: '2026-01-01T09:00:00',
    programId: 'A',
    leftStimFreq: '130',
    leftAmplitude: '2.5',
    leftPulseWidth: '60',
    scaleName: 'Tremor',
    scaleValue: '4',
    notes: 'transient warmth',
  ),
  SessionRow(
    blockId: '1',
    isInitial: '0',
    acqTime: '2026-01-01T09:00:00',
    programId: 'A',
    leftStimFreq: '130',
    leftAmplitude: '2.5',
    leftPulseWidth: '60',
    scaleName: 'Rigidity',
    scaleValue: '2',
    notes: 'transient warmth',
  ),
  SessionRow(
    blockId: '2',
    isInitial: '0',
    acqTime: '2026-01-01T09:12:00',
    programId: 'A',
    leftStimFreq: '130',
    leftAmplitude: '3.5',
    leftPulseWidth: '60',
    scaleName: 'Tremor',
    scaleValue: '1',
  ),
];

Future<void> _pump(WidgetTester tester, List<SessionRow> rows) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SessionEntriesTable(rows: rows)),
      ),
    );

void main() {
  test('testedCount counts configurations, not rows or the initial one', () {
    expect(testedCount(_rows), 2);
    expect(
      testedCount([..._rows, const SessionRow(blockId: '0', isInitial: '1')]),
      2,
    );
    expect(testedCount(const []), 0);
  });

  testWidgets('block-level columns are printed once per block', (tester) async {
    await _pump(tester, _rows);

    // Two blocks share the same programme, so the cell appears twice, not
    // once per scale row.
    expect(find.text('A'), findsNWidgets(2));
    expect(
      find.text('2026-01-01 09:00:00'),
      findsOneWidget,
      reason: 'no baseline row here, so the first block keeps the date',
    );
    expect(
      find.text('09:12:00'),
      findsOneWidget,
      reason: 'later blocks show the clock time only',
    );
    expect(find.text('-\n130 Hz / 2.5 mA / 60 µs'), findsOneWidget);
    expect(find.text('transient warmth'), findsOneWidget);

    // Scale and value are the columns that actually differ, so every row keeps
    // its own pair.
    expect(find.text('Tremor'), findsNWidgets(2));
    expect(find.text('Rigidity'), findsOneWidget);
  });

  testWidgets('the date is carried by the baseline row, not by every block', (
    tester,
  ) async {
    await _pump(tester, [
      const SessionRow(
        blockId: '0',
        isInitial: '1',
        acqTime: '2026-01-01T08:55:00',
        scaleName: 'Y-BOCS',
        scaleValue: '30',
      ),
      ..._rows,
    ]);
    // Baseline: the date, which is a property of the session.
    expect(find.text('2026-01-01'), findsOneWidget);
    // Recording blocks: the clock time only.
    expect(find.text('09:00:00'), findsOneWidget);
    expect(find.text('09:12:00'), findsOneWidget);
    expect(find.textContaining('2026-01-01 09:'), findsNothing);
  });

  testWidgets('each side says where the current goes, then its dose', (
    tester,
  ) async {
    await _pump(tester, const [
      SessionRow(
        blockId: '1',
        isInitial: '0',
        acqTime: '2026-01-01T09:00:00',
        leftAnode: 'case',
        leftCathode: 'E2b_E2c',
        leftAmplitude: '3.0_2.0',
        leftStimFreq: '130',
        leftPulseWidth: '60',
        scaleName: 'Tremor',
        scaleValue: '1',
      ),
    ]);
    expect(
      find.text('2b(60%) 2c(40%)- / case+\n130 Hz / 5.0 mA / 60 µs'),
      findsOneWidget,
    );
    expect(find.textContaining('3.0_2.0'), findsNothing);
  });

  testWidgets('empty rows show a message rather than a bare header', (
    tester,
  ) async {
    await _pump(tester, const []);
    expect(find.text('No configurations saved yet.'), findsOneWidget);
  });
}
