import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the stimulation defaults and steps against schema/limits.json.
/// Run `flutter test` from the repo root.
void main() {
  StimLimits loadLimits() {
    final file = File('schema/limits.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'schema/*.json is a committed contract; restore it from git.',
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return StimLimits.fromJson(json);
  }

  test('each indication starts from its curated settings', () {
    final limits = loadLimits();
    // A default is delivered unless changed, so values are pinned, not counts.
    expect(limits.defaults, {
      'PD': [130, 1.5, 60],
      'OCD': [130, 5.0, 90],
    });
    for (final [f, a, pw] in limits.defaults.values) {
      expect(f, inInclusiveRange(limits.frequency.min, limits.frequency.max));
      expect(a, inInclusiveRange(limits.amplitude.min, limits.amplitude.max));
      expect(
        pw,
        inInclusiveRange(limits.pulseWidth.min, limits.pulseWidth.max),
      );
    }
  });

  test('step1 / decimals / omitted_tsv are parsed from the contract', () {
    final limits = loadLimits();
    // The - / + stepper buttons move by these (stimulation.*.step1).
    expect(limits.frequencyStep, 10);
    expect(limits.amplitudeStep, 1);
    expect(limits.pulseWidthStep, 10);
    // The single arrows move by step2.
    expect(limits.frequencyFineStep, 1);
    expect(limits.amplitudeFineStep, 0.1);
    expect(limits.pulseWidthFineStep, 1);
    expect(limits.amplitudeDecimals, 2);
    // Omitted session scales write this literal to the scale_value cell.
    // `n/a` since v0.5.0: BIDS requires it, and `NaN` was never a legal cell.
    expect(limits.sessionScaleOmittedTsv, 'n/a');
  });

  test('step1 / decimals / omitted_tsv fall back to defaults when absent', () {
    final json = jsonDecode(
      File('schema/limits.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final stim = json['stimulation'] as Map<String, dynamic>;
    for (final key in ['frequency', 'amplitude', 'pulse_width']) {
      (stim[key] as Map<String, dynamic>).remove('step1');
    }
    (stim['amplitude'] as Map<String, dynamic>).remove('decimals');
    (json['session_scale'] as Map<String, dynamic>).remove('omitted_tsv');
    final limits = StimLimits.fromJson(json);
    expect(limits.frequencyStep, 10);
    expect(limits.amplitudeStep, 1);
    expect(limits.pulseWidthStep, 10);
    expect(limits.amplitudeDecimals, 2);
    expect(limits.sessionScaleOmittedTsv, 'NaN');
  });

  test('steppedLabel keeps decimals then strips trailing zeros', () {
    expect(steppedLabel(110, 0), '110');
    expect(steppedLabel(112.6, 0), '113');
    expect(steppedLabel(2.5, 2), '2.5');
    expect(steppedLabel(2.0, 2), '2');
    expect(steppedLabel(0.1 + 0.2 + 0.2, 2), '0.5');
  });

  test('defaults are optional: a contract without them has none', () {
    final json = jsonDecode(
      File('schema/limits.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    json.remove('stimulation_defaults');
    expect(StimLimits.fromJson(json).defaults, isEmpty);
  });

  test('presetLabel drops trailing .0 like the desktop combos', () {
    expect(presetLabel(25), '25');
    expect(presetLabel(0.0), '0');
    expect(presetLabel(1.5), '1.5');
    expect(presetLabel(120), '120');
  });

  test("the user's defaults replace the contract's; null keeps them", () {
    final limits = loadLimits();
    final over = limits.withDefaults({
      'ET': [130, 2, 60],
    });
    expect(over.defaults.keys, ['ET']);
    expect(over.amplitudeFineStep, limits.amplitudeFineStep);
    expect(limits.withDefaults(null).defaults, limits.defaults);
  });
}
