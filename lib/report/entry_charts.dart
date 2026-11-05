/// Turns inserted session rows into the four stacked panels of the
/// entry-review figure: session scales, amplitude, pulse width and frequency.
///
/// Pure Dart (no Flutter), so the shape of the figure is unit-testable without
/// pumping a widget.
///
/// The x positions are configurations (blocks) in time order, evenly spaced,
/// each tick labelled with that block's clock time. Plotting against real
/// elapsed time would bunch a rapid titration into a few pixels, stretch a
/// break across the panel, and leave "the last 10 configurations" undefined.
library;

import '../core/electrode/amplitude.dart';
import '../core/session/longitudinal.dart'
    show isScaleValueOmitted, splitScalePairs;
import '../core/session/scale_scoring.dart';
import '../core/session/session_row.dart';
import '../core/timestamps.dart' show recordedTime;
import 'report_data.dart' show coerceInt;

/// One stacked panel: a title, its series, and the y range to draw. [id] is
/// stable across rebuilds and app runs, so the user's panel order can be
/// persisted by id rather than by position.
typedef ParamPanel = ({
  String id,
  String title,
  Map<String, Map<int, double>> series,
  double yMin,
  double yMax,

  /// Set when every series in the panel held one value throughout, e.g.
  /// "90 µs, unchanged". The view then draws a single labelled line instead of
  /// a plot: padding a constant range puts 90 dead centre of an 89-91 axis,
  /// which reads as a measured mid-range value.
  String? constantLabel,

  /// Series numerically identical to another in the same panel (Left exactly
  /// under Right), so the reader can tell both sides are plotted.
  List<String> coincident,
});

/// Everything the four-panel figure needs, sharing one x domain so the panels
/// line up vertically.
typedef EntryChartData = ({
  /// Block IDs in time order: the x positions, evenly spaced.
  List<int> xs,

  /// Block ID -> "HH:MM" for the axis ticks.
  Map<int, String> xLabels,
  List<ParamPanel> panels,

  /// Blocks with the best and second-best aggregate index against the scale
  /// targets, for the green bands. Empty when nothing was rated; a tie puts
  /// several blocks at the same rank, and every one of them is banded.
  List<int> bestXs,
  List<int> secondXs,
});

/// Canonical panel ids, also the default top-to-bottom order.
const List<String> kEntryPanelIds = [
  'scales',
  'amplitude',
  'pulseWidth',
  'freq',
];

/// Human titles per panel id, for a persisted order that no longer matches the
/// default list.
const Map<String, String> kEntryPanelTitles = {
  'scales': 'Session scales',
  'amplitude': 'Amplitude (mA)',
  'pulseWidth': 'Pulse width (µs)',
  'freq': 'Frequency (Hz)',
};

/// Trim a trailing ".0" so "90.0 us" reads as "90 us".
String _trim(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Sum a possibly-split amplitude cell ("1.5_1" -> 2.5). Null when unparsable.
double? _amplitudeTotal(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  try {
    final parsed = parseAmplitude(text);
    return parsed.total;
  } on FormatException {
    return null;
  }
}

/// First numeric token, tolerating a unit suffix ("60 µs" -> 60).
double? _numeric(String raw) {
  final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(raw.trim());
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// Pad a y range so markers do not sit exactly on the frame. [zeroBased]
/// anchors the bottom at 0, right for a magnitude: an amplitude axis starting
/// at 4.4 makes a 5.5 -> 4.5 mA step occupy a third of the panel.
(double, double) _padRange(double lo, double hi, {bool zeroBased = false}) {
  if (!lo.isFinite || !hi.isFinite) return (0, 1);
  if (lo == hi) return zeroBased ? (0, hi + 1) : (lo - 1, hi + 1);
  final margin = (hi - lo) * 0.12;
  return (zeroBased ? 0 : lo - margin, hi + margin);
}

/// The single value every series in [maps] holds, or null when anything varies
/// or nothing was recorded.
double? _constantOf(Iterable<Map<int, double>> maps) {
  double? only;
  for (final m in maps) {
    for (final v in m.values) {
      if (only == null) {
        only = v;
      } else if ((v - only).abs() > 1e-9) {
        return null;
      }
    }
  }
  return only;
}

/// Names in [series] whose values duplicate an earlier series exactly.
List<String> _coincidentSeries(Map<String, Map<int, double>> series) {
  final out = <String>[];
  final seen = <String, String>{};
  for (final e in series.entries) {
    final key =
        (e.value.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
            .map((p) => '${p.key}:${p.value}')
            .join(',');
    if (key.isEmpty) continue;
    final first = seen[key];
    if (first != null) {
      out.add(e.key);
    } else {
      seen[key] = e.key;
    }
  }
  return out;
}

/// Build the four panels from [rows]. Only recording rows are plotted
/// (`is_initial != 1`): the baseline block is the pre-session state, not a
/// tested configuration.
///
/// [scalePrefs] carries the scale bounds and the optimisation mode per scale,
/// driving both the scales panel's y axis (the declared bounds, widened to any
/// value outside them) and the aggregate index behind the best/second bands.
/// When it is empty the axis auto-fits and no block is banded.
EntryChartData buildEntryChartData(
  List<SessionRow> rows, {
  List<ScalePref> scalePrefs = const [],
}) {
  final targets = parseScaleTargets(scalePrefs);
  // Blocks in first-seen order, with the earliest timestamp for each.
  final blockOrder = <int>[];
  final seenBlocks = <int>{};
  final blockTime = <int, DateTime>{};
  final blockClock = <int, String>{};
  final scales = <String, Map<int, double>>{};
  final ampL = <int, double>{};
  final ampR = <int, double>{};
  final pwL = <int, double>{};
  final pwR = <int, double>{};
  final freqL = <int, double>{};
  final freqR = <int, double>{};

  for (final row in rows) {
    if (coerceInt(row.isInitial) == 1) continue;
    final block = coerceInt(row.blockId);
    if (seenBlocks.add(block)) blockOrder.add(block);
    final ts = row.timestamp;
    if (ts != null) {
      final existing = blockTime[block];
      if (existing == null || ts.isBefore(existing)) {
        blockTime[block] = ts;
        blockClock[block] = row.acqTime;
      }
    }

    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      if (pair.name.isEmpty || isScaleValueOmitted(pair.value)) continue;
      final v = double.tryParse(pair.value.trim());
      if (v == null || !v.isFinite) continue;
      (scales[pair.name] ??= <int, double>{})[block] = v;
    }

    void put(Map<int, double> into, double? v) {
      if (v != null && v.isFinite) into[block] = v;
    }

    put(ampL, _amplitudeTotal(row.leftAmplitude));
    put(ampR, _amplitudeTotal(row.rightAmplitude));
    put(pwL, _numeric(row.leftPulseWidth));
    put(pwR, _numeric(row.rightPulseWidth));
    put(freqL, _numeric(row.leftStimFreq));
    put(freqR, _numeric(row.rightStimFreq));
  }

  // Time order, falling back to block id for rows with no parseable stamp so
  // the axis is always deterministic.
  blockOrder.sort((a, b) {
    final ta = blockTime[a];
    final tb = blockTime[b];
    if (ta != null && tb != null) {
      final c = ta.compareTo(tb);
      if (c != 0) return c;
    } else if (ta != null) {
      return -1;
    } else if (tb != null) {
      return 1;
    }
    return a.compareTo(b);
  });

  // The wall clock recorded in `acq_time`, never the instant: `timestamp` is
  // local to this machine, so a block recorded at 09:03 in Geneva would be
  // labelled 10:03 in Berlin, disagreeing with the table beside it and with
  // the report. Sorting above still uses the instant, where only order counts.
  final xLabels = <int, String>{
    for (final b in blockOrder)
      if (recordedTime(blockClock[b] ?? '').isNotEmpty)
        b: recordedTime(blockClock[b]!).substring(0, 5),
  };

  /// y range over every series in a panel.
  (double, double) rangeOf(
    Iterable<Map<int, double>> maps, {
    bool zeroBased = false,
  }) {
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final m in maps) {
      for (final v in m.values) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    return _padRange(lo, hi, zeroBased: zeroBased);
  }

  // Session scales: the declared bounds of every scale, widened to any value
  // outside them (an older file), so no point is drawn off the panel.
  var scalesRange = rangeOf(scales.values);
  final declared = declaredScaleRange(targets);
  if (declared != null) {
    var lo = declared.$1;
    var hi = declared.$2;
    for (final m in scales.values) {
      for (final v in m.values) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    scalesRange = (lo, hi);
  }

  ParamPanel panel(
    String id,
    Map<String, Map<int, double>> series,
    (double, double) range, {
    String unit = '',
  }) {
    // Drop empty series so an unused side does not claim a legend slot.
    final used = <String, Map<int, double>>{
      for (final e in series.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
    final constant = _constantOf(used.values);
    return (
      id: id,
      title: kEntryPanelTitles[id]!,
      series: used,
      yMin: range.$1,
      yMax: range.$2,
      constantLabel: constant == null || used.isEmpty
          ? null
          : '${_trim(constant)}${unit.isEmpty ? '' : ' $unit'}, unchanged'
                '${used.length > 1 ? ' (both sides)' : ''}',
      coincident: _coincidentSeries(used),
    );
  }

  final ranks = targets.isEmpty
      ? const <int, int>{}
      : rankBlocks(computeAggregateIndex(scales, blockOrder, targets));

  return (
    xs: blockOrder,
    xLabels: xLabels,
    bestXs: blocksAtRank(ranks, 1),
    secondXs: blocksAtRank(ranks, 2),
    panels: [
      panel('scales', scales, scalesRange),
      // Dose is a magnitude, so its axis starts at zero: an amplitude panel
      // spanning 4.4-7.4 makes 5.5 -> 4.5 mA look like a collapse.
      panel(
        'amplitude',
        {'Left': ampL, 'Right': ampR},
        rangeOf([ampL, ampR], zeroBased: true),
        unit: 'mA',
      ),
      panel(
        'pulseWidth',
        {'Left': pwL, 'Right': pwR},
        rangeOf([pwL, pwR]),
        unit: 'µs',
      ),
      panel(
        'freq',
        {'Left': freqL, 'Right': freqR},
        rangeOf([freqL, freqR]),
        unit: 'Hz',
      ),
    ],
  );
}

/// Reorder [panels] to match a persisted list of ids. Unknown ids are ignored
/// and missing ones appended in default order, so a stale preference degrades
/// to a sensible order instead of losing a panel.
List<ParamPanel> orderPanels(List<ParamPanel> panels, List<String>? order) {
  if (order == null || order.isEmpty) return panels;
  final byId = {for (final p in panels) p.id: p};
  final out = <ParamPanel>[];
  for (final id in order) {
    final p = byId.remove(id);
    if (p != null) out.add(p);
  }
  out.addAll(panels.where((p) => byId.containsKey(p.id)));
  return out;
}
