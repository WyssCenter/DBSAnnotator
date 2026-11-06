import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the quick-picks against the contract: StimLimits MUST expose the
/// `stimulation_presets` values from schema/limits.json. Run
/// `flutter test` from the repo root.
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

  test('stimulation quick-picks match the curated preset list', () {
    final limits = loadLimits();
    // Curated down from the desktop's original combos: 25 Hz, 1.5 and 10.0 mA
    // and 120 us were dropped. Values, not just counts, because a quick-pick is
    // a one-tap dose - a wrong number here is delivered, not merely displayed.
    expect(limits.frequencyPresets, [55, 100, 125]);
    expect(limits.amplitudePresets, [3.0, 5.0, 7.0]);
    expect(limits.pulseWidthPresets, [40, 60, 90]);

    // Every quick-pick is inside its own field's allowed range.
    for (final v in limits.frequencyPresets) {
      expect(v, inInclusiveRange(limits.frequency.min, limits.frequency.max));
    }
    for (final v in limits.amplitudePresets) {
      expect(v, inInclusiveRange(limits.amplitude.min, limits.amplitude.max));
    }
    for (final v in limits.pulseWidthPresets) {
      expect(v, inInclusiveRange(limits.pulseWidth.min, limits.pulseWidth.max));
    }
  });

  test('step1 / decimals / omitted_tsv are parsed from the contract', () {
    final limits = loadLimits();
    // The - / + stepper buttons move by these (stimulation.*.step1).
    expect(limits.frequencyStep, 10);
    expect(limits.amplitudeStep, 1);
    expect(limits.pulseWidthStep, 10);
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

  test('presets are optional: contract without them parses to empty lists', () {
    final json = jsonDecode(
      File('schema/limits.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    json.remove('stimulation_presets');
    final limits = StimLimits.fromJson(json);
    expect(limits.frequencyPresets, isEmpty);
    expect(limits.amplitudePresets, isEmpty);
    expect(limits.pulseWidthPresets, isEmpty);
  });

  test('presetLabel drops trailing .0 like the desktop combos', () {
    expect(presetLabel(25), '25');
    expect(presetLabel(0.0), '0');
    expect(presetLabel(1.5), '1.5');
    expect(presetLabel(120), '120');
  });

  test('withPresets overrides only the given lists (F7 user overrides)', () {
    final limits = loadLimits();
    final over = limits.withPresets(frequencies: const [1, 2, 3]);
    // Overridden list replaced; the others fall back to the contract; ranges
    // and steps are carried through unchanged.
    expect(over.frequencyPresets, [1, 2, 3]);
    expect(over.amplitudePresets, limits.amplitudePresets);
    expect(over.pulseWidthPresets, limits.pulseWidthPresets);
    expect(over.frequency.max, limits.frequency.max);
    expect(over.amplitudeStep, limits.amplitudeStep);
    expect(over.sessionScaleOmittedTsv, limits.sessionScaleOmittedTsv);

    // A null keeps the contract default (the merge is per-list).
    expect(limits.withPresets().frequencyPresets, limits.frequencyPresets);
  });
}
