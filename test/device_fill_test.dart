import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/percept/therapy.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/bids_folder.dart';
import 'package:dbs_annotator/core/session/bids_session.dart';
import 'package:dbs_annotator/core/session/device_fill.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:flutter_test/flutter_test.dart';

import 'percept_fixture.dart';

final _t0 = DateTime.utc(2026, 2, 3, 9);

DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

const _model = 'Medtronic SenSight B33005';

final _cathodeE0 = monopolar([('SenSight_00', null)]);
final _cathodeE3 = monopolar([('SenSight_03', null)]);

PerceptTimeline _visit({
  Map<String, dynamic>? leftSnapshot,
  List<Map<String, dynamic>>? last,
  String leftLead = 'B33005',
}) => perceptTimeline(
  perceptJson(
    start: _at(0),
    end: _at(700),
    leftLead: leftLead,
    initial: [
      sensingGroup(
        'B',
        left: sensingSide(electrodes: _cathodeE0),
        right: sensingSide(electrodes: _cathodeE3),
      ),
    ],
    last:
        last ??
        [
          sensingGroup(
            'B',
            left: sensingSide(electrodes: _cathodeE0),
            right: sensingSide(electrodes: _cathodeE3),
          ),
        ],
    segments: [
      segment(
        _at(60),
        [(0, 1.0, 4.0), (200, 2.0, 4.0), (400, 2.5, 4.0), (401, 3.0, 4.0)],
        endSeconds: 600,
        left: leftSnapshot ?? snapshotSide(electrodes: _cathodeE0),
        right: snapshotSide(electrodes: _cathodeE3),
      ),
    ],
  ),
);

List<SessionRow> _block(
  int id,
  int seconds, {
  Map<String, String> stim = const {},
  bool initial = false,
}) => buildInsertRows(
  blockId: id,
  appendId: 1,
  isInitial: initial,
  scales: [(name: 'Mood', value: '5')],
  leftElectrodeModel: _model,
  rightElectrodeModel: _model,
  target: 'STN',
  leftStimFreq: stim['left_stim_freq'] ?? '130',
  leftAmplitude: stim['left_amplitude'] ?? '1.5',
  leftPulseWidth: stim['left_pulse_width'] ?? '60',
  leftCathode: stim['left_cathode'] ?? '',
  leftAnode: stim['left_anode'] ?? '',
  rightStimFreq: stim['right_stim_freq'] ?? '130',
  rightAmplitude: stim['right_amplitude'] ?? '1.5',
  rightPulseWidth: stim['right_pulse_width'] ?? '60',
  at: _at(seconds),
);

BlockFill _fillOf(DeviceFillPlan plan, String id) =>
    plan.fills.singleWhere((f) => f.blockId == id);

void main() {
  test('defaults inside a segment are replaced and listed as from the '
      'device', () {
    final plan = planDeviceFill([..._block(0, 150)], [_visit()]);
    final fill = _fillOf(plan, '0');
    expect(fill.changes, {
      'program_id': 'B',
      'left_stim_freq': '125',
      'left_anode': 'case',
      'left_cathode': 'E0',
      'left_amplitude': '1',
      'left_pulse_width': '90',
      'right_stim_freq': '125',
      'right_anode': 'case',
      'right_cathode': 'E3',
      'right_amplitude': '4',
      'right_pulse_width': '90',
    });
    expect(fill.held, const Duration(seconds: 90));

    final authoring = SessionAuthoring()..rows.addAll(_block(0, 150));
    applyDeviceFill(authoring, plan, add: false);
    final row = authoring.rows.single;
    expect(row.leftAmplitude, '1');
    expect(
      row.fromDevice,
      'program_id left_stim_freq left_anode left_cathode left_amplitude '
      'left_pulse_width right_stim_freq right_anode right_cathode '
      'right_amplitude right_pulse_width',
    );
  });

  test('values entered as the device has them stay entered', () {
    final entered = {
      'left_stim_freq': '125',
      'left_amplitude': '2',
      'left_pulse_width': '90',
    };
    final rows = _block(0, 300, stim: entered);
    final plan = planDeviceFill(rows, [_visit()]);
    final authoring = SessionAuthoring()..rows.addAll(rows);
    applyDeviceFill(authoring, plan, add: false);
    final kept = deviceColumnsOf(authoring.rows.single);
    expect(kept, isNot(contains('left_amplitude')));
    expect(kept, isNot(contains('left_stim_freq')));
    expect(kept, contains('left_cathode'));
  });

  test('a configuration the clinician keeps is left as entered', () {
    final rows = [..._block(0, 150), ..._block(1, 300)];
    final plan = planDeviceFill(rows, [_visit()]);
    final authoring = SessionAuthoring()..rows.addAll(rows);
    applyDeviceFill(authoring, plan, keep: {'0'}, add: false);
    final first = authoring.rows.firstWhere((r) => r.blockId == '0');
    expect(first.leftAmplitude, '1.5');
    expect(first.fromDevice, '');
    expect(
      authoring.rows.firstWhere((r) => r.blockId == '1').leftAmplitude,
      '2',
    );
  });

  test('contacts the snapshot lacks stay as the clinician entered them', () {
    final rows = _block(
      0,
      150,
      stim: {'left_cathode': 'E1a', 'left_anode': 'case'},
    );
    final plan = planDeviceFill(rows, [_visit(leftSnapshot: snapshotSide())]);
    final changes = _fillOf(plan, '0').changes;
    expect(changes.containsKey('left_cathode'), isFalse);
    expect(changes['left_amplitude'], '1');
    final authoring = SessionAuthoring()..rows.addAll(rows);
    applyDeviceFill(authoring, plan, add: false);
    expect(authoring.rows.single.leftCathode, 'E1a');
    expect(
      deviceColumnsOf(authoring.rows.single),
      isNot(contains('left_cathode')),
    );
  });

  test('a configuration outside the streaming is listed and untouched', () {
    final plan = planDeviceFill(_block(0, 680), [_visit()]);
    expect(plan.fills, isEmpty);
    expect(plan.uncovered.single.blockId, '0');
  });

  test('a save during a ramp step takes that step, and says how long', () {
    final fill = _fillOf(planDeviceFill(_block(0, 460), [_visit()]), '0');
    expect(fill.device['left_amplitude'], '2.5');
    expect(fill.held, Duration.zero);
  });

  test('stable settings the clinician did not save are added in time '
      'order', () {
    final rows = _block(0, 300);
    final plan = planDeviceFill(rows, [_visit()]);
    expect(plan.additions.map((a) => a.isInitial), [true, false, false]);
    expect(
      plan.additions.skip(1).map((a) => cellsOf(a.setting)['left_amplitude']),
      ['1', '3'],
    );

    final authoring = SessionAuthoring()..rows.addAll(rows);
    applyDeviceFill(authoring, plan);
    final blocks = <String, SessionRow>{
      for (final r in authoring.rows) r.blockId: r,
    };
    expect(blocks.keys, ['0', '1', '2', '3']);
    expect(blocks['0']!.isInitial, '1');
    expect(blocks['0']!.acqTime, '2026-02-03T09:00:00+00:00');
    expect(blocks['1']!.leftAmplitude, '1');
    expect(blocks['1']!.acqTime, '2026-02-03T09:04:20+00:00');
    expect(blocks['2']!.leftAmplitude, '2');
    expect(blocks['2']!.scaleName, 'Mood');
    expect(blocks['3']!.leftAmplitude, '3');
    expect(blocks['3']!.scaleName, '');
    expect(blocks['3']!.target, 'STN');
    expect(deviceColumnsOf(blocks['3']!), contains('right_cathode'));
    expect(authoring.blockId, 4);
  });

  test('the initial assessment is matched to the start of the visit', () {
    final rows = _block(0, -60, initial: true);
    final fill = _fillOf(planDeviceFill(rows, [_visit()]), '0');
    expect(fill.held, isNull);
    expect(fill.device['left_cathode'], 'E0');
    expect(fill.device.containsKey('left_amplitude'), isFalse);
  });

  test('an end setting that differs from the last one is added at the '
      'end', () {
    final plan = planDeviceFill(_block(0, 500), [
      _visit(
        last: [
          sensingGroup(
            'C',
            left: sensingSide(electrodes: _cathodeE0),
            right: sensingSide(electrodes: _cathodeE3),
          ),
        ],
      ),
    ]);
    final end = plan.additions.last.setting;
    expect(end.start, _at(700));
    expect(cellsOf(end)['program_id'], 'C');
    expect(cellsOf(end).containsKey('left_amplitude'), isFalse);
  });

  test('an end setting equal to the last one adds nothing', () {
    final plan = planDeviceFill(_block(0, 500), [_visit()]);
    expect(plan.additions.where((a) => a.setting.start == _at(700)), isEmpty);
  });

  test('the side swap reads the left lead as the right', () {
    final fill = _fillOf(
      planDeviceFill(_block(0, 150), [_visit()], swapSides: true),
      '0',
    );
    expect(fill.device['left_cathode'], 'E3');
    expect(fill.device['right_cathode'], 'E0');
  });

  test('a different lead or another day is refused', () {
    expect(
      planDeviceFill(_block(0, 150), [_visit(leftLead: '3389')]).refusal,
      contains('3389'),
    );
    final otherDay = buildInsertRows(
      blockId: 0,
      appendId: 1,
      at: _t0.add(const Duration(days: 2)),
    );
    expect(
      planDeviceFill(otherDay, [_visit()]).refusal,
      contains('2026-02-03'),
    );
    expect(planDeviceFill(_block(0, 150), const []).refusal, isNotNull);
  });

  test('an edit keeps the source of the values it did not change', () {
    final before = SessionRow.fromMap({
      'left_amplitude': '2',
      'left_pulse_width': '90',
      'from_device': 'left_amplitude left_pulse_width',
    });
    final after = SessionRow.fromMap({
      'left_amplitude': '2.5',
      'left_pulse_width': '90',
    });
    expect(keptDeviceColumns(before, after), 'left_pulse_width');
  });

  test('from_device survives the BIDS tables', () {
    final authoring = SessionAuthoring()
      ..rows.addAll([..._block(0, -60, initial: true), ..._block(1, 150)]);
    applyDeviceFill(
      authoring,
      planDeviceFill(authoring.rows, [_visit()]),
      add: false,
    );
    final tables = splitSession(
      authoring.rows,
      sessionId: 'ses-20260203',
      participantId: 'sub-01',
    );
    final back = joinSession(
      behRows: tables.behRows,
      visit: tables.visit,
      initial: tables.initial,
    );
    expect(
      {for (final r in back) r.fromDevice},
      {for (final r in authoring.rows) r.fromDevice},
    );
    expect(back.first.fromDevice, contains('left_cathode'));
  });

  test('exports are found in the visit ieeg folder by their content', () async {
    final root = Directory.systemTemp.createTempSync('percept_');
    addTearDown(() => root.deleteSync(recursive: true));
    final ieeg = Directory('${root.path}/sub-01/ses-20260203/ieeg')
      ..createSync(recursive: true);
    File('${ieeg.path}/Report_Json_Session_Report_20260203T090000.json')
        .writeAsStringSync(
          jsonEncode(
            perceptJson(
              start: _at(0),
              end: _at(700),
              initial: [
                sensingGroup('B', left: sensingSide(electrodes: _cathodeE0)),
              ],
            ),
          ),
        );
    File('${ieeg.path}/sub-01_ses-20260203_ieeg.json')
        .writeAsStringSync('{"TaskName": "programming"}');
    File('${ieeg.path}/broken.json').writeAsStringSync('{"SessionDate": ');

    final found = await perceptExportsIn(
      root.path,
      const BidsName(
        subject: '01',
        session: '20260203',
        task: 'programming',
        run: '01',
      ),
    );
    expect(
      found.map((e) => e.file),
      ['Report_Json_Session_Report_20260203T090000.json', 'broken.json']
        ..sort(),
    );
    final export = found.firstWhere((e) => e.timeline != null);
    expect(cellsOf(export.timeline!.initial!)['left_cathode'], 'E0');
    expect(found.firstWhere((e) => e.file == 'broken.json').error, isNotNull);
  });

  group('contacts in the app grammar', () {
    Map<String, String> cells(List<Map<String, dynamic>> electrodes) => cellsOf(
      perceptTimeline(
        perceptJson(
          start: _at(0),
          end: _at(60),
          initial: [
            programGroup(
              'B',
              rate: 125,
              left: programSide(amplitude: 5, electrodes: electrodes),
            ),
          ],
        ),
      ).initial!,
    );

    test('segments in either spelling, with the split from the fractions', () {
      final c = cells(monopolar([('SenSight_1b', 32), ('Sensight_1c', 32)]));
      expect(c['left_anode'], 'case');
      expect(c['left_cathode'], 'E1b_E1c');
      expect(c['left_amplitude'], '2.5_2.5');
      expect(c['program_id'], 'B');
      expect(c['left_stim_freq'], '125');
      expect(c['left_pulse_width'], '90');
    });

    test('an uneven split is kept as the device stores it', () {
      final c = cells(monopolar([('SenSight_1b', 38), ('SenSight_1c', 26)]));
      expect(c['left_amplitude'], '2.97_2.03');
    });

    test('rings, and a ring on a segmented level as its three segments', () {
      expect(
        cells(monopolar([('FourElectrodes_2', null)]))['left_cathode'],
        'E2',
      );
      expect(cells(monopolar([('SenSight_00', null)]))['left_cathode'], 'E0');
      expect(
        cells(monopolar([('SenSight_2', null)]))['left_cathode'],
        'E2a_E2b_E2c',
      );
    });

    test('without fractions several cathodes get the total alone', () {
      final c = cells(
        monopolar([('SenSight_1a', null), ('SenSight_1b', null)]),
      );
      expect(c['left_cathode'], 'E1a_E1b');
      expect(c['left_amplitude'], '5');
    });

    test('an electrode it does not know leaves the contacts unfilled', () {
      final c = cells(monopolar([('SenSight_07', null)]));
      expect(c.containsKey('left_cathode'), isFalse);
      expect(c.containsKey('left_anode'), isFalse);
      expect(c['left_amplitude'], '5');
    });
  });
}
