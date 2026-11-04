/// Scale presets from the generated contract `schema/scale_presets.json`,
/// whose source of truth is the Python desktop app's config.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// One session-scale preset row, as the contract's strings. [mode] (`min`,
/// `max`, `custom`, `ignore`) is the direction the report's block ranking
/// optimises the scale in, and is absent from older 3-cell rows.
typedef SessionScaleRow = ({String name, String min, String max, String mode});

/// Fallback for a preset row with no mode cell.
const String defaultScaleOptimizationMode = 'min';

/// The modes the contract may carry; anything else decodes to the default.
const List<String> scaleOptimizationModes = ['min', 'max', 'custom', 'ignore'];

/// A clinical scale's declared score range, as the contract's strings; either
/// may be empty when the range is not known.
typedef ScaleRange = ({String min, String max});

class ScalePresets {
  const ScalePresets({
    required this.buttons,
    required this.clinical,
    required this.session,
    this.clinicalRanges = const {},
  });

  factory ScalePresets.fromJson(Map<String, dynamic> json) {
    final buttons = (json['buttons'] as List)
        .map((e) => e as String)
        .toList(growable: false);

    final clinicalJson = json['clinical'] as Map<String, dynamic>;
    final clinical = <String, List<String>>{
      for (final entry in clinicalJson.entries)
        entry.key: (entry.value as List)
            .map((e) => e as String)
            .toList(growable: false),
    };

    final sessionJson = json['session'] as Map<String, dynamic>;
    final session = <String, List<SessionScaleRow>>{
      for (final entry in sessionJson.entries)
        entry.key: (entry.value as List)
            .map((row) {
              final cells = (row as List).map((e) => '$e').toList();
              // The 4th cell is absent in older contracts.
              final mode = cells.length > 3
                  ? cells[3].trim().toLowerCase()
                  : defaultScaleOptimizationMode;
              return (
                name: cells[0],
                min: cells[1],
                max: cells[2],
                mode: scaleOptimizationModes.contains(mode)
                    ? mode
                    : defaultScaleOptimizationMode,
              );
            })
            .toList(growable: false),
    };

    // Absent from older contracts.
    final rangesJson = json['clinical_ranges'] as Map<String, dynamic>? ?? {};
    final clinicalRanges = <String, ScaleRange>{
      for (final e in rangesJson.entries)
        e.key: (
          min: '${(e.value as List).first}',
          max: '${(e.value as List).last}',
        ),
    };

    return ScalePresets(
      buttons: buttons,
      clinical: clinical,
      session: session,
      clinicalRanges: clinicalRanges,
    );
  }

  /// Ordered preset names for the button bar (OCD, MDD, PD, ET, ...).
  final List<String> buttons;

  /// Preset -> clinical scale names (baseline / is_initial rows).
  final Map<String, List<String>> clinical;

  final Map<String, List<SessionScaleRow>> session;

  /// Clinical scale name -> declared range. Keyed by scale rather than preset,
  /// since a scale such as Y-BOCS has one range in every group it appears in.
  /// Used only to set the clinical figure's y axis.
  final Map<String, ScaleRange> clinicalRanges;
}

/// [ranges] as numbers, leaving out any that do not parse or are empty.
Map<String, (double, double)> numericRanges(Map<String, ScaleRange> ranges) => {
  for (final e in ranges.entries)
    if ((double.tryParse(e.value.min), double.tryParse(e.value.max))
        case (final lo?, final hi?) when lo < hi)
      e.key: (lo, hi),
};

/// Clinical scale names for [preset]; empty for unknown presets.
List<String> clinicalRows(ScalePresets p, String preset) =>
    p.clinical[preset] ?? const [];

/// Session scale rows for [preset]; empty for unknown presets.
List<SessionScaleRow> sessionRows(ScalePresets p, String preset) =>
    p.session[preset] ?? const [];

/// Loads the bundled scale-presets contract; tests read `schema/` via `dart:io`.
Future<ScalePresets> loadScalePresets() async {
  final raw = await rootBundle.loadString('schema/scale_presets.json');
  return ScalePresets.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
