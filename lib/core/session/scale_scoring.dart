/// Scale-optimisation targets and the block ranking behind the reports' green
/// best and second-best markers, ported from
/// `dbs_annotator/utils/report_chart_utils.py`.
///
/// One ranking, deliberately: the desktop ranks the table's row shading with a
/// second algorithm (signed raw sums) that can disagree with the chart's
/// bands, so one report could band one block and shade another. That twin is
/// not ported; [computeAggregateIndex] and [findBestAndSecond] drive both.
library;

import 'longitudinal.dart' show isScaleValueOmitted, splitScalePairs;
import 'session_row.dart';

/// How a scale should be optimised; the desktop's `mode` string.
enum ScaleMode {
  min,
  max,

  /// Closer to [ScalePref.custom] is better.
  custom,

  /// Excluded from both rankings entirely.
  ignore,
}

typedef ScalePref = ({
  String name,
  double min,
  double max,
  ScaleMode mode,
  double? custom,
});

/// A resolved optimisation target for one scale.
typedef ScaleTarget = ({
  ScaleMode type,
  double value,
  double lower,
  double upper,
});

double _clip01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);

/// Parse a mode string, including the `low`/`high` aliases accepted alongside
/// `min`/`max`. An unrecognised string becomes [ScaleMode.ignore], which is
/// what the desktop does in effect by writing no target entry for it.
ScaleMode scaleModeFromString(String raw) => switch (raw.trim().toLowerCase()) {
  'low' || 'min' => ScaleMode.min,
  'high' || 'max' => ScaleMode.max,
  'custom' => ScaleMode.custom,
  _ => ScaleMode.ignore,
};

/// Build a [ScalePref] from raw strings, coercing an unparsable bound or
/// custom value to `0.0` as the desktop does.
ScalePref scalePrefFromStrings({
  required String name,
  required String min,
  required String max,
  required String mode,
  String custom = '',
}) => (
  name: name,
  min: double.tryParse(min.trim()) ?? 0.0,
  max: double.tryParse(max.trim()) ?? 0.0,
  mode: scaleModeFromString(mode),
  custom: double.tryParse(custom.trim()) ?? 0.0,
);

/// Resolve [prefs] into per-scale targets keyed by scale name.
///
/// Bounds are swapped when `min > max`; [ScaleMode.min] targets the lower
/// bound, [ScaleMode.max] the upper, [ScaleMode.custom] the custom value.
/// [ScaleMode.ignore] yields no entry, which is what makes an ignored scale
/// fall through to the unknown-scale branch of [computeAggregateIndex].
Map<String, ScaleTarget> parseScaleTargets(List<ScalePref> prefs) {
  final targets = <String, ScaleTarget>{};
  for (final pref in prefs) {
    var lower = pref.min;
    var upper = pref.max;
    if (lower > upper) {
      final swap = lower;
      lower = upper;
      upper = swap;
    }
    switch (pref.mode) {
      case ScaleMode.min:
        targets[pref.name] = (
          type: ScaleMode.min,
          value: lower,
          lower: lower,
          upper: upper,
        );
      case ScaleMode.max:
        targets[pref.name] = (
          type: ScaleMode.max,
          value: upper,
          lower: lower,
          upper: upper,
        );
      case ScaleMode.custom:
        targets[pref.name] = (
          type: ScaleMode.custom,
          value: pref.custom ?? 0.0,
          lower: lower,
          upper: upper,
        );
      case ScaleMode.ignore:
        break;
    }
  }
  return targets;
}

/// Aggregate index per x-point: the mean score of the ranked scales, 1.0 best
/// and 0.0 worst.
///
/// A ranked scale is one with a target and a value at some point. A point
/// missing any ranked scale gets no index, so a configuration rated on part of
/// the visit's ratings is never ranked; scales without a target never count.
/// Each value is normalised into `[lower, upper]` and scored `1 - z` (min), `z`
/// (max) or `1 - |v - target| / maxDistance` (custom), flat 0.5 if the span is
/// non-positive or a custom target sits equidistant from both bounds.
///
/// [allPoints] must be sorted: the returned map preserves that order.
Map<int, double> computeAggregateIndex(
  Map<String, Map<int, double>> scaleData,
  List<int> allPoints,
  Map<String, ScaleTarget> targets,
) {
  final ranked = {
    for (final MapEntry(:key, :value) in scaleData.entries)
      if (targets[key] case final target? when value.isNotEmpty) key: target,
  };
  if (ranked.isEmpty) return const {};
  final indexVals = <int, double>{};
  for (final pt in allPoints) {
    var sum = 0.0;
    var complete = true;
    for (final MapEntry(key: name, value: target) in ranked.entries) {
      final value = scaleData[name]![pt];
      if (value == null) {
        complete = false;
        break;
      }
      sum += _score(value, target);
    }
    if (complete) indexVals[pt] = sum / ranked.length;
  }
  return indexVals;
}

double _score(double value, ScaleTarget target) {
  final denom = target.upper - target.lower;
  if (denom <= 0) return 0.5;
  final z = _clip01((value - target.lower) / denom);
  return switch (target.type) {
    ScaleMode.min => 1.0 - z,
    ScaleMode.max => z,
    ScaleMode.custom => () {
      final maxDistance = [
        (target.value - target.lower).abs(),
        (target.upper - target.value).abs(),
      ].reduce((a, b) => a > b ? a : b);
      if (maxDistance <= 0) return 0.5;
      return 1.0 - _clip01((value - target.value).abs() / maxDistance);
    }(),
    ScaleMode.ignore => 0.5,
  };
}

/// Overall `(min, max)` across every declared per-scale range, or null when
/// nothing is declared or the span collapses; clamps the chart's left y-axis.
(double, double)? declaredScaleRange(Map<String, ScaleTarget> targets) {
  if (targets.isEmpty) return null;
  var overallMin = double.infinity;
  var overallMax = double.negativeInfinity;
  for (final t in targets.values) {
    var lower = t.lower;
    var upper = t.upper;
    if (upper < lower) {
      final swap = lower;
      lower = upper;
      upper = swap;
    }
    if (lower < overallMin) overallMin = lower;
    if (upper > overallMax) overallMax = upper;
  }
  if (overallMax <= overallMin) return null;
  return (overallMin, overallMax);
}

/// Decimals the aggregate index prints to, wherever it appears.
///
/// [rankBlocks] ties on the value as PRINTED, so a reader can never see two
/// identical numbers carrying different ranks or different colours.
const int indexDecimals = 2;

/// Blocks ranked by aggregate index, 1 = best, with equal indices sharing a
/// rank.
///
/// One ordering drives the figure's green bands, the table's row shading and
/// the rank printed beside each index, on screen and in both report formats,
/// so they cannot contradict each other. Ties are dense because a rank is a
/// claim about the number, and two blocks printing 0.450 are not ordered by
/// it. The original key order breaks exact ties, since `List.sort` is not
/// stable and a report must be reproducible.
Map<int, int> rankBlocks(Map<int, double> index) {
  final keys = index.keys.toList();
  final order = List<int>.generate(keys.length, (i) => i)
    ..sort((a, b) {
      final cmp = index[keys[b]]!.compareTo(index[keys[a]]!);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
  String printed(int i) =>
      index[keys[order[i]]]!.toStringAsFixed(indexDecimals);
  final out = <int, int>{};
  var rank = 0;
  for (var i = 0; i < order.length; i++) {
    if (i == 0 || printed(i) != printed(i - 1)) rank += 1;
    out[keys[order[i]]] = rank;
  }
  return out;
}

/// The blocks [rankBlocks] put at [rank], ascending.
List<int> blocksAtRank(Map<int, int> ranks, int rank) => [
  for (final e in ranks.entries)
    if (e.value == rank) e.key,
]..sort();

/// Default preferences for every scale present in [rows]: the [known] target
/// and range of a scale listed there, else [ScaleMode.min] over [fallback].
List<ScalePref> defaultScalePrefsFor(
  Iterable<SessionRow> rows, {
  Map<String, ScalePref> known = const {},
  (double, double) fallback = (0.0, 10.0),
}) {
  final names = <String>[];
  final seen = <String>{};
  for (final row in rows) {
    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      if (pair.name.isEmpty || isScaleValueOmitted(pair.value)) continue;
      if (seen.add(pair.name)) names.add(pair.name);
    }
  }
  return [
    for (final name in names)
      known[name] ??
          (
            name: name,
            min: fallback.$1,
            max: fallback.$2,
            mode: ScaleMode.min,
            custom: null,
          ),
  ];
}
