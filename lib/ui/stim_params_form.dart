import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// A [min, max] pair from schema/limits.json.
typedef LimitRange = ({double min, double max});

/// Numeric bounds from the generated contract `schema/limits.json`, whose
/// source of truth is the desktop app's config.
class StimLimits {
  const StimLimits({
    required this.frequency,
    required this.amplitude,
    required this.pulseWidth,
    required this.sessionScale,
    this.frequencyStep = 10,
    this.amplitudeStep = 1,
    this.pulseWidthStep = 10,
    this.frequencyFineStep = 1,
    this.amplitudeFineStep = 0.1,
    this.pulseWidthFineStep = 1,
    this.amplitudeDecimals = 2,
    this.sessionScaleOmittedTsv = 'NaN',
    this.defaults = const {},
  });

  factory StimLimits.fromJson(Map<String, dynamic> json) {
    LimitRange range(Map<String, dynamic> m) =>
        (min: (m['min'] as num).toDouble(), max: (m['max'] as num).toDouble());
    double step1(Map<String, dynamic> m, double fallback) =>
        ((m['step1'] as num?) ?? fallback).toDouble();
    double step2(Map<String, dynamic> m, double fallback) =>
        ((m['step2'] as num?) ?? fallback).toDouble();
    final stim = json['stimulation'] as Map<String, dynamic>;
    final freq = stim['frequency'] as Map<String, dynamic>;
    final amp = stim['amplitude'] as Map<String, dynamic>;
    final pw = stim['pulse_width'] as Map<String, dynamic>;
    final sessionScale = json['session_scale'] as Map<String, dynamic>;
    final defaults =
        (json['stimulation_defaults'] as Map<String, dynamic>?) ?? const {};
    return StimLimits(
      frequency: range(freq),
      amplitude: range(amp),
      pulseWidth: range(pw),
      sessionScale: range(sessionScale),
      frequencyStep: step1(freq, 10),
      amplitudeStep: step1(amp, 1),
      pulseWidthStep: step1(pw, 10),
      frequencyFineStep: step2(freq, 1),
      amplitudeFineStep: step2(amp, 0.1),
      pulseWidthFineStep: step2(pw, 1),
      amplitudeDecimals: ((amp['decimals'] as num?) ?? 2).toInt(),
      sessionScaleOmittedTsv: (sessionScale['omitted_tsv'] as String?) ?? 'NaN',
      defaults: {
        for (final MapEntry(:key, :value) in defaults.entries)
          key: [
            for (final k in ['frequency', 'amplitude', 'pulse_width'])
              (value as Map<String, dynamic>)[k] as num,
          ],
      },
    );
  }

  final LimitRange frequency; // Hz
  final LimitRange amplitude; // mA
  final LimitRange pulseWidth; // µs
  final LimitRange sessionScale;

  /// Coarse increment (`step1`), the double-chevron column.
  final double frequencyStep;
  final double amplitudeStep;
  final double pulseWidthStep;

  /// Fine increment (`step2`), the single-chevron column.
  final double frequencyFineStep;
  final double amplitudeFineStep;
  final double pulseWidthFineStep;

  /// Decimal places for amplitude values (`stimulation.amplitude.decimals`).
  final int amplitudeDecimals;

  /// Literal written to the scale_value TSV cell for a scale that was not
  /// assessed (`session_scale.omitted_tsv`).
  final String sessionScaleOmittedTsv;

  /// Starting frequency, amplitude and pulse width per DBS indication.
  final Map<String, List<num>> defaults;

  /// Copy with [defaults] replaced by the user's, when there are any.
  StimLimits withDefaults(Map<String, List<num>>? defaults) => StimLimits(
    frequency: frequency,
    amplitude: amplitude,
    pulseWidth: pulseWidth,
    sessionScale: sessionScale,
    frequencyStep: frequencyStep,
    amplitudeStep: amplitudeStep,
    pulseWidthStep: pulseWidthStep,
    frequencyFineStep: frequencyFineStep,
    amplitudeFineStep: amplitudeFineStep,
    pulseWidthFineStep: pulseWidthFineStep,
    amplitudeDecimals: amplitudeDecimals,
    sessionScaleOmittedTsv: sessionScaleOmittedTsv,
    defaults: defaults ?? this.defaults,
  );
}

/// Loads the limits contract from the bundled asset, which the build copies
/// from repo-root `schema/*.json`. Tests read that file directly instead.
Future<StimLimits> loadStimLimits() async {
  final raw = await rootBundle.loadString('schema/limits.json');
  return StimLimits.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// Validation message for a numeric field. Null when [text] is blank, since
/// an empty TSV cell is allowed, or parses to a value within [range].
String? rangeError(String text, LimitRange range) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || !v.isFinite) return 'Not a number';
  if (v < range.min || v > range.max) {
    return 'Allowed: ${_fmt(range.min)}-${_fmt(range.max)}';
  }
  return null;
}

String _fmt(double v) => v == v.truncateToDouble() ? '${v.truncate()}' : '$v';

/// A value as typed in a field, without a trailing `.0`.
String presetLabel(num v) => _fmt(v.toDouble());

/// Text for a stepped value, fixed to [decimals] places with trailing zeros
/// stripped. Rounding first keeps repeated steps free of float noise.
String steppedLabel(double v, int decimals) {
  var out = v.toStringAsFixed(decimals);
  if (out.contains('.')) {
    while (out.endsWith('0')) {
      out = out.substring(0, out.length - 1);
    }
    if (out.endsWith('.')) out = out.substring(0, out.length - 1);
  }
  return out;
}

/// Compact one-side stimulation parameter entry: Frequency, Amplitude and
/// Pulse width as numeric fields validated against [StimLimits].
///
/// The parent owns the three [TextEditingController]s and reads the values
/// from them; a blank field leaves its TSV column empty.
class StimParamsForm extends StatelessWidget {
  const StimParamsForm({
    super.key,
    required this.limits,
    required this.frequency,
    required this.amplitude,
    required this.pulseWidth,
  });

  final StimLimits limits;
  final TextEditingController frequency;
  final TextEditingController amplitude;
  final TextEditingController pulseWidth;

  /// Adjust [controller] by [step] in [direction] (-1/+1), clamped to
  /// [range]. A blank or non-numeric field starts at the range minimum,
  /// like the desktop spin boxes.
  static void stepField({
    required TextEditingController controller,
    required LimitRange range,
    required double step,
    required int decimals,
    required int direction,
  }) {
    final current = double.tryParse(controller.text.trim());
    final next = current == null
        ? range.min
        : (current + direction * step).clamp(range.min, range.max).toDouble();
    controller.text = steppedLabel(next, decimals);
  }

  /// One tiny arrow button, styled like the desktop spin arrows.
  Widget _arrowButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 16,
        child: SizedBox(width: 22, height: 15, child: Icon(icon, size: 16)),
      ),
    );
  }

  /// A stacked up/down arrow column, coarse (`step1`) or fine (`step2`).
  Widget _arrowColumn({
    required TextEditingController controller,
    required LimitRange range,
    required double step,
    required int decimals,
    required String label,
    required bool coarse,
  }) {
    // The fine column's tooltips are marked so both columns are addressable.
    final suffix = coarse ? '' : ' (fine)';
    void bump(int direction) => stepField(
      controller: controller,
      range: range,
      step: step,
      decimals: decimals,
      direction: direction,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _arrowButton(
          coarse ? Icons.keyboard_double_arrow_up : Icons.keyboard_arrow_up,
          'Increase $label$suffix',
          () => bump(1),
        ),
        _arrowButton(
          coarse ? Icons.keyboard_double_arrow_down : Icons.keyboard_arrow_down,
          'Decrease $label$suffix',
          () => bump(-1),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String unit,
    required LimitRange range,
    required double step,
    required double fineStep,
    required int decimals,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (text) => rangeError(text ?? '', range),
            decoration: InputDecoration(
              labelText: label,
              suffixText: unit,
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'Clear $label',
                visualDensity: VisualDensity.compact,
                onPressed: controller.clear,
              ),
              helperText: '${_fmt(range.min)}-${_fmt(range.max)}',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Fine then coarse, matching the desktop IncrementWidget's order.
        _arrowColumn(
          controller: controller,
          range: range,
          step: fineStep,
          decimals: decimals,
          label: label,
          coarse: false,
        ),
        _arrowColumn(
          controller: controller,
          range: range,
          step: step,
          decimals: decimals,
          label: label,
          coarse: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _field(
            controller: frequency,
            label: 'Frequency',
            unit: 'Hz',
            range: limits.frequency,
            step: limits.frequencyStep,
            fineStep: limits.frequencyFineStep,
            decimals: 0,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _field(
            controller: amplitude,
            label: 'Amplitude',
            unit: 'mA',
            range: limits.amplitude,
            step: limits.amplitudeStep,
            fineStep: limits.amplitudeFineStep,
            decimals: limits.amplitudeDecimals,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _field(
            controller: pulseWidth,
            label: 'Pulse width',
            unit: 'µs',
            range: limits.pulseWidth,
            step: limits.pulseWidthStep,
            fineStep: limits.pulseWidthFineStep,
            decimals: 0,
          ),
        ),
      ],
    );
  }
}
