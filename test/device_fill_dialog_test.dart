import 'package:dbs_annotator/percept/therapy.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/ui/device_fill_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'percept_fixture.dart';

final _t0 = DateTime.utc(2026, 2, 3, 9);

DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

PerceptTimeline _visit() {
  final side = snapshotSide(electrodes: monopolar([('SenSight_00', null)]));
  return perceptTimeline(
    perceptJson(
      start: _at(0),
      end: _at(700),
      segments: [
        segment(
          _at(60),
          [(0, 1.0, 4.0), (200, 2.0, 4.0), (400, 3.0, 4.0)],
          endSeconds: 600,
          left: side,
          right: side,
        ),
      ],
    ),
  );
}

List<SessionRow> _rows() => [
  for (final (id, seconds) in [(0, 150), (1, 300)])
    ...buildInsertRows(
      blockId: id,
      appendId: 1,
      leftAmplitude: '1.5',
      leftElectrodeModel: 'Medtronic SenSight B33005',
      at: _at(seconds),
    ),
];

Widget _host(
  List<SessionRow> rows,
  List<PerceptFile> exports,
  void Function(DeviceFillChoice?) done,
) => MaterialApp(
  home: Builder(
    builder: (context) => TextButton(
      onPressed: () async => done(
        await showDeviceFillDialog(context, rows: rows, exports: exports),
      ),
      child: const Text('open'),
    ),
  ),
);

void main() {
  testWidgets('the preview lists the changes and returns what was kept', (
    tester,
  ) async {
    DeviceFillChoice? choice;
    await tester.pumpWidget(
      _host(_rows(), [
        (file: 'export.json', timeline: _visit(), error: null),
        (file: 'broken.json', timeline: null, error: 'bad JSON'),
      ], (c) => choice = c),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Read from export.json'), findsOneWidget);
    expect(find.text('Could not read broken.json: bad JSON'), findsOneWidget);
    expect(find.text('#0 at 09:02:30'), findsOneWidget);
    expect(find.textContaining('Left amplitude (mA): 1.5 → 1'), findsOneWidget);
    expect(find.textContaining('Left amplitude (mA): 1.5 → 2'), findsOneWidget);
    expect(
      find.textContaining('the device held that were not saved'),
      findsOneWidget,
    );

    await tester.tap(find.text('#0 at 09:02:30'));
    await tester.pump();
    await tester.tap(find.text('Fill'));
    await tester.pumpAndSettle();

    final accepted = choice!;
    expect(accepted.keep, {'0'});
    expect(accepted.add, isFalse, reason: 'unrated settings are opt-in');
    expect(accepted.plan.fills.map((f) => f.blockId), ['0', '1']);
  });

  testWidgets('a refused export cannot be filled', (tester) async {
    await tester.pumpWidget(
      _host(
        buildInsertRows(
          blockId: 0,
          appendId: 1,
          leftElectrodeModel: 'Medtronic 3389',
          at: _at(150),
        ),
        [(file: 'export.json', timeline: _visit(), error: null)],
        (_) {},
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('B33005 lead on the left side'), findsOneWidget);
    final fill = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Fill'),
    );
    expect(fill.onPressed, isNull);
  });
}
