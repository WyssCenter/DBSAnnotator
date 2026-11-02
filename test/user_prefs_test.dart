import 'package:dbs_annotator/core/prefs/user_prefs.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('UserPrefs round-trips through JSON', () {
    final p = UserPrefs(
      stimFrequencies: [10, 20, 30],
      programs: ['None', 'A', 'Custom'],
      clinical: {
        'OCD': ['Y-BOCS', 'MADRS'],
      },
      session: {
        'PD': [
          ['Tremor', '0', '10'],
        ],
      },
    );
    final back = UserPrefs.fromJson(p.toJson());
    expect(back.stimFrequencies, [10, 20, 30]);
    expect(back.programs, ['None', 'A', 'Custom']);
    expect(back.clinical!['OCD'], ['Y-BOCS', 'MADRS']);
    expect(back.session!['PD']!.first, ['Tremor', '0', '10']);
    // Unset fields stay null (fall back to bundled defaults).
    expect(back.stimAmplitudes, isNull);
  });

  test('the session report remembers its sections', () {
    final back = UserPrefs.fromJson(
      UserPrefs(reportSections: ['baseline']).toJson(),
    );
    expect(back.reportSections, ['baseline']);
  });

  test('empty prefs serialize to an empty object and read back empty', () {
    expect(UserPrefs().toJson(), isEmpty);
    expect(UserPrefs.fromJson(const {}).programs, isNull);
  });

  group('mergeScalePresets (F7 effective presets)', () {
    const base = ScalePresets(
      buttons: ['OCD', 'PD'],
      clinical: {
        'OCD': ['Y-BOCS'],
        'PD': ['UPDRS'],
      },
      session: {
        'PD': [(name: 'Tremor', min: '0', max: '10', mode: 'min', step: '')],
      },
    );

    test('empty prefs leave the bundled contract unchanged', () {
      final m = mergeScalePresets(base, UserPrefs());
      expect(m.buttons, ['OCD', 'PD']);
      expect(m.clinical['OCD'], ['Y-BOCS']);
      expect(m.session['PD']!.single.name, 'Tremor');
    });

    test('a user override wins over the default for that group only', () {
      final m = mergeScalePresets(
        base,
        UserPrefs(
          clinical: {
            'OCD': ['Y-BOCS', 'HAM-A'],
          },
        ),
      );
      expect(m.clinical['OCD'], ['Y-BOCS', 'HAM-A']); // overridden
      expect(m.clinical['PD'], ['UPDRS']); // untouched default
    });

    test('a new group name is appended to the button bar and rows parse', () {
      final m = mergeScalePresets(
        base,
        UserPrefs(
          clinical: {
            'ET': ['TETRAS'],
          },
          session: {
            'ET': [
              ['Tremor', '0', '4'],
            ],
          },
        ),
      );
      expect(m.buttons, ['OCD', 'PD', 'ET']); // contract order, then new
      expect(m.clinical['ET'], ['TETRAS']);
      // A 3-cell override row predates the optimization-mode field.
      expect(m.session['ET']!.single, (
        name: 'Tremor',
        min: '0',
        max: '4',
        mode: 'min',
        step: '',
      ));
    });

    test('an override row carries its optimization mode through the merge', () {
      final m = mergeScalePresets(
        base,
        UserPrefs(
          session: {
            'PD': [
              ['Mood', '0', '10', 'max', '1'],
            ],
          },
        ),
      );
      expect(m.session['PD']!.single, (
        name: 'Mood',
        min: '0',
        max: '10',
        mode: 'max',
        step: '1',
      ));
    });

    test('an override row with a bogus mode falls back to the default', () {
      final m = mergeScalePresets(
        base,
        UserPrefs(
          session: {
            'PD': [
              ['Mood', '0', '10', 'upwards'],
            ],
          },
        ),
      );
      expect(m.session['PD']!.single.mode, defaultScaleOptimizationMode);
    });
  });
}
