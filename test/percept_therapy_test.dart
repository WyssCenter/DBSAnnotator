import 'dart:io';

import 'package:dbs_annotator/percept/therapy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'percept_fixture.dart';

final _t0 = DateTime.utc(2026, 2, 3, 9);

DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

void main() {
  test('lib/percept imports only the Dart SDK and itself', () {
    for (final file in Directory('lib/percept').listSync().whereType<File>()) {
      for (final line in file.readAsLinesSync()) {
        if (!line.startsWith('import ')) continue;
        expect(
          line.contains("'dart:") ||
              !(line.contains('package:') || line.contains('../')),
          isTrue,
          reason: '${file.path}: $line',
        );
      }
    }
  });

  test('only a Percept export is recognised as one', () {
    expect(isPerceptExport(perceptJson(start: _t0, end: _at(60))), isTrue);
    expect(isPerceptExport({'TaskName': 'programming'}), isFalse);
    expect(isPerceptExport([1, 2]), isFalse);
  });

  test('contacts keep their export names, polarity and share', () {
    final left = perceptTimeline(
      perceptJson(
        start: _t0,
        end: _at(60),
        initial: [
          programGroup(
            'B',
            left: programSide(
              amplitude: 5,
              electrodes: monopolar([('Sensight_1c', 26)]),
            ),
          ),
        ],
      ),
    ).initial!.left!;
    expect(left.contacts, [
      (electrode: 'Sensight_1c', cathode: true, share: 26 / 64),
      (electrode: 'Case', cathode: false, share: null),
    ]);
  });

  test('a program per hemisphere is read, two programs are not', () {
    final timeline = perceptTimeline(
      perceptJson(
        start: _t0,
        end: _at(60),
        initial: [
          {
            'GroupId': 'GroupIdDef.GROUP_A',
            'ActiveGroup': true,
            'ProgramSettings': {
              'RateInHertz': 130,
              'LeftHemisphere': {
                'Programs': {
                  'AmplitudeInMilliAmps': 2.9,
                  'PulseWidthInMicroSecond': 60,
                  'ElectrodeState': monopolar([('FourElectrodes_1', null)]),
                },
              },
              'RightHemisphere': {
                'Programs': [
                  {'AmplitudeInMilliAmps': 1.0},
                  {'AmplitudeInMilliAmps': 2.0},
                ],
              },
            },
          },
          sensingGroup('C', active: false),
        ],
      ),
    );
    final initial = timeline.initial!;
    expect(initial.group, 'A');
    expect(initial.left!.rate, 130);
    expect(initial.left!.amplitude, 2.9);
    expect(initial.left!.contacts!.first.electrode, 'FourElectrodes_1');
    expect(initial.right, isNull);
    expect(timeline.notes.single, contains('right side runs 2 programs'));
  });

  test('a BrainSense group gives no amplitude, and says so', () {
    final timeline = perceptTimeline(
      perceptJson(
        start: _t0,
        end: _at(60),
        initial: [
          sensingGroup(
            'B',
            left: sensingSide(electrodes: monopolar([('SenSight_1b', null)])),
          ),
        ],
      ),
    );
    final left = timeline.initial!.left!;
    expect(left.rate, 125);
    expect(left.amplitude, isNull);
    expect(left.contacts!.first.electrode, 'SenSight_1b');
    expect(timeline.notes.single, contains('left amplitude at the start'));
  });

  test('stimulation off at the start gives no initial setting', () {
    final timeline = perceptTimeline(
      perceptJson(
        start: _t0,
        end: _at(60),
        initial: [sensingGroup('B')],
        stimulation: {
          'InitialStimStatus': 'StimStatusDef.OFF',
          'FinalStimStatus': 'StimStatusDef.ON',
        },
      ),
    );
    expect(timeline.initial, isNull);
    expect(timeline.notes.single, contains('off at the start'));
  });

  group('streaming', () {
    final side = snapshotSide(electrodes: monopolar([('SenSight_00', null)]));

    test('each change of amplitude starts a run, timed from the ticks', () {
      final timeline = perceptTimeline(
        perceptJson(
          start: _t0,
          end: _at(120),
          segments: [
            segment(
              _at(0),
              [(0, 1.0, 2.0), (30, 1.5, 2.0), (31, 2.0, 2.0)],
              endSeconds: 90,
              left: side,
              right: side,
            ),
          ],
        ),
      );
      final runs = timeline.runs;
      expect(runs.length, 3);
      expect(runs[0].start, _at(0));
      expect(runs[0].end, _at(30));
      expect(runs[1].held, const Duration(seconds: 1));
      expect(runs[2].end, _at(90));
      expect(runs[2].group, 'B');
      expect(runs[2].left!.amplitude, 2.0);
      expect(runs[2].left!.contacts!.first.electrode, 'SenSight_00');
      expect(stableSettings(runs).map((s) => s.left!.amplitude), [1.0, 2.0]);
    });

    test('the device clock rolling over does not move samples back', () {
      final timeline = perceptTimeline(
        perceptJson(
          start: _t0,
          end: _at(60),
          segments: [
            segment(
              _at(0),
              [(0, 1.0, null), (20, 2.0, null)],
              endSeconds: 40,
              left: side,
              firstTick: 3276800 - 10000,
            ),
          ],
        ),
      );
      expect(timeline.runs.last.start, _at(20));
      expect(timeline.runs.last.end, _at(40));
      expect(timeline.runs.last.right, isNull);
    });

    test('equal settings either side of a short break are one', () {
      Map<String, dynamic> from(int seconds) => segment(
        _at(seconds),
        [(0, 1.0, 1.0)],
        endSeconds: 40,
        left: side,
        right: side,
      );
      final timeline = perceptTimeline(
        perceptJson(start: _t0, end: _at(200), segments: [from(0), from(50)]),
      );
      expect(timeline.runs.length, 2);
      expect(stableSettings(timeline.runs).single.end, _at(90));
    });

    test('a single segment written as an object is still read', () {
      final json = perceptJson(start: _t0, end: _at(60))
        ..['BrainSenseLfp'] = segment(
          _at(0),
          [(0, 1.0, 1.0)],
          endSeconds: 20,
          left: side,
          right: side,
        );
      expect(
        perceptTimeline(json).runs.single.held,
        const Duration(seconds: 20),
      );
    });
  });

  test('lead models are read per side', () {
    final timeline = perceptTimeline(
      perceptJson(start: _t0, end: _at(60), rightLead: '3389'),
    );
    expect(timeline.leadModels, {'left': 'B33005', 'right': '3389'});
  });
}
