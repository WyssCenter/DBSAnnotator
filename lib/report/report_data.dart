/// Pure computation shared by the session report builders (PDF and Word).
///
/// Both formats render the sections computed here, so they stay consistent with
/// each other and with the desktop's `session_exporter.py`. No widgets, no
/// platform channels: fully headless-testable.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../core/annotation.dart';
import '../core/brand_palette.dart' show kBestFill, kSecondFill;
import '../core/session/longitudinal.dart'
    show isScaleValueOmitted, scaleTimeline, splitScalePairs;
import '../core/session/scale_scoring.dart';
import '../core/session/session_row.dart';
import '../core/timestamps.dart';

typedef ScalePair = ({String name, String value});

/// Anode / cathode token strings for both leads of one configuration.
///
/// The amplitudes travel with the tokens because a contact list without its
/// current is not a configuration: `2b 2c` does not say whether the steering
/// was 3.3/2.2 or the reverse, and the two behave nothing alike.
typedef LateralTokens = ({
  String leftAnode,
  String leftCathode,
  String leftAmplitude,
  String rightAnode,
  String rightCathode,
  String rightAmplitude,
});

/// Coerce a TSV cell to an int the way `pd.to_numeric(errors="coerce")
/// .fillna(0)` does: unparsable cells become 0.
int coerceInt(String raw) {
  final v = double.tryParse(raw.trim());
  if (v == null || !v.isFinite) return 0;
  return v.truncate();
}

/// Desktop-identical number trimming: f"{x:.2f}".rstrip("0").rstrip(".").
///
/// Two decimals, not `toString()`, which prints float artifacts into a clinical
/// table: a Y-BOCS falling 28.0 to 24.4 rendered its change as
/// "3.6000000000000014". The scales step in 0.25, so two decimals also avoid
/// claiming precision the instrument has not got.
String trimZeros(double v) {
  var out = v.toStringAsFixed(2);
  while (out.endsWith('0')) {
    out = out.substring(0, out.length - 1);
  }
  if (out.endsWith('.')) out = out.substring(0, out.length - 1);
  return out;
}

/// The row with the highest append_id, then the highest block_id, last on ties.
SessionRow? _latestRow(List<SessionRow> rows) {
  if (rows.isEmpty) return null;
  var best = rows.first;
  for (final row in rows.skip(1)) {
    final s = coerceInt(row.appendId).compareTo(coerceInt(best.appendId));
    if (s > 0 ||
        (s == 0 && coerceInt(row.blockId) >= coerceInt(best.blockId))) {
      best = row;
    }
  }
  return best;
}

/// Separator no TSV cell can contain (tab is the field delimiter), so the
/// dedup key keeps "AB"+"C" distinct from "A"+"BC".
final String _sep = String.fromCharCode(31);

/// Deduplicated (name, value) scale pairs over [rows], skipping blank names and
/// omitted values.
List<ScalePair> _collectScalePairs(Iterable<SessionRow> rows) {
  final seen = <String>{};
  final pairs = <ScalePair>[];
  for (final row in rows) {
    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      if (pair.name.isEmpty || isScaleValueOmitted(pair.value)) continue;
      if (seen.add('${pair.name}$_sep${pair.value}')) pairs.add(pair);
    }
  }
  return pairs;
}

/// Min/max over a parameter column. Blank cells are skipped; with [splitSum] a
/// split amplitude like "1.5_1" counts as its SUM (2.5), otherwise the first
/// numeric token wins, which tolerates units ("60 µs" -> 60).
(double, double)? _paramRange(Iterable<String> raws, {bool splitSum = false}) {
  final numToken = RegExp(r'[-+]?\d*\.?\d+');
  final vals = <double>[];
  for (final raw in raws) {
    final text = raw.trim();
    if (text.isEmpty) continue;
    if (splitSum && text.contains('_')) {
      final parts = text
          .split('_')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .map(double.tryParse)
          .toList();
      if (parts.isNotEmpty && !parts.contains(null)) {
        vals.add(parts.fold(0.0, (a, b) => a + b!));
        continue;
      }
    }
    final m = numToken.firstMatch(text);
    if (m == null) continue;
    final v = double.tryParse(m.group(0)!);
    if (v != null) vals.add(v);
  }
  if (vals.isEmpty) return null;
  vals.sort();
  return (vals.first, vals.last);
}

/// Consecutive integers collapsed: [1,2,3,5] -> "1-3, 5".
String _blockRuns(List<int> blocks) {
  if (blocks.isEmpty) return '';
  final sorted = blocks.toList()..sort();
  final runs = <String>[];
  var start = sorted.first;
  var prev = sorted.first;
  for (final b in sorted.skip(1)) {
    if (b == prev + 1) {
      prev = b;
      continue;
    }
    runs.add(start == prev ? '$start' : '$start-$prev');
    start = b;
    prev = b;
  }
  runs.add(start == prev ? '$start' : '$start-$prev');
  return runs.join(', ');
}

/// The distinct values a parameter took, with the blocks that carried each:
/// `5.5 mA (blocks 1-5), 4.5 mA (blocks 6-7)`, or `125 Hz (unchanged)`.
///
/// Not the desktop's min-max "range": that implied a titration that never
/// happened, and it equated a monopolar 7.0 mA with 7.0 mA split three ways
/// (radically different volumes of tissue activated).
String _valuesText(
  Map<int, List<SessionRow>> blocks,
  String Function(SessionRow) pick,
  String unit,
  int digits, {
  bool splitSum = false,
}) {
  final byValue = <String, List<int>>{};
  for (final entry in blocks.entries) {
    final r = _paramRange([pick(entry.value.first)], splitSum: splitSum);
    if (r == null) continue;
    final key = r.$1.toStringAsFixed(digits);
    (byValue[key] ??= []).add(entry.key);
  }
  if (byValue.isEmpty) return 'N/A';
  if (byValue.length == 1) return '${byValue.keys.first} $unit (unchanged)';
  return byValue.entries
      .map(
        (e) =>
            '${e.key} $unit (configuration${e.value.length == 1 ? '' : 's'} '
            '${_blockRuns(e.value)})',
      )
      .join(', ');
}

/// Whether [acqTime] is dated after [sessionDate].
bool _onLaterDay(String acqTime, String sessionDate) =>
    recordedDate(acqTime).isNotEmpty &&
    recordedDate(acqTime).compareTo(sessionDate) > 0;

/// A row's clock time for display, `HH:MM:SS`, or '' when it has no instant.
String _clock(SessionRow row) => recordedTime(row.acqTime);

/// The UTC offset the rows were recorded at, e.g. "+02:00", or ''.
///
/// A clinical timestamp with no zone is ambiguous by up to a day either side of
/// midnight, and across a DST boundary two sessions cannot be ordered, so
/// `acq_time` carries its offset and the report prints it.
String _utcOffset(Iterable<SessionRow> rows) {
  for (final row in rows) {
    // `acq_time` is ISO-8601 and carries its own offset. A pre-0.5.0 file's
    // free-text `timezone` cell has already been folded into it by
    // `SessionRow.fromMap`.
    final offset = offsetFromTimezoneCell(row.acqTime);
    if (offset.isNotEmpty) return offset;
  }
  return '';
}

/// Every parseable date+time stamp in [rows], ascending.
List<DateTime> _stamps(Iterable<SessionRow> rows) {
  final out = <DateTime>[];
  for (final row in rows) {
    final dt = row.timestamp;
    if (dt != null) out.add(dt);
  }
  out.sort();
  return out;
}

/// The `acq_time` cells of [rows] that carry an instant, in chronological
/// order.
///
/// The instant only orders them; the string is what display reads, so a report
/// prints the clock the visit was recorded at rather than the clock of whatever
/// machine exported it. Rendering the instant instead would make one file print
/// two different session times in two clinics, and a different date either side
/// of midnight.
List<String> _recordedInOrder(Iterable<SessionRow> rows) {
  final dated = <({DateTime at, String cell})>[];
  for (final row in rows) {
    final at = row.timestamp;
    if (at != null) dated.add((at: at, cell: row.acqTime));
  }
  dated.sort((a, b) => a.at.compareTo(b.at));
  return [for (final d in dated) d.cell];
}

/// A recorded cell's wall clock trimmed to `HH:MM`, for the report header.
String _hourMinute(String acqTime) {
  final t = recordedTime(acqTime);
  return t.length >= 5 ? t.substring(0, 5) : t;
}

/// Span from the first to the last entry, "Xh Ymin" / "X min" / "N/A".
///
/// Not the session's clinical duration, and the label says so: the
/// first-to-last annotation interval is all the data supports.
String _spanText(List<SessionRow> rows) {
  final stamps = _stamps(rows);
  if (stamps.length < 2) return 'N/A';
  final totalMins = stamps.last.difference(stamps.first).inMinutes;
  if (totalMins >= 60) return '${totalMins ~/ 60}h ${totalMins % 60}min';
  return '$totalMins min';
}

/// The gap between two blocks: "+35 s", "+2 min", or ''.
///
/// A rating taken seconds after a parameter change measures an acute response
/// only; printing the interval is what lets a reader see that.
String _gapText(DateTime? previous, DateTime? current) {
  if (previous == null || current == null) return '';
  final secs = current.difference(previous).inSeconds;
  if (secs <= 0) return '';
  if (secs < 90) return '+$secs s';
  return '+${(secs / 60).round()} min';
}

/// The stimulation columns that define a configuration. Two blocks with the
/// same tuple were the same setting, however many times they were rated.
List<String> _paramKey(SessionRow r) => [
  r.leftStimFreq.trim(),
  r.leftAmplitude.trim(),
  r.leftPulseWidth.trim(),
  r.leftAnode.trim(),
  r.leftCathode.trim(),
  r.rightStimFreq.trim(),
  r.rightAmplitude.trim(),
  r.rightPulseWidth.trim(),
  r.rightAnode.trim(),
  r.rightCathode.trim(),
];

/// Table cell for an amplitude: the TOTAL delivered current, rounded to the
/// device's own resolution of 0.1 mA.
///
/// The share-out lives in the contact column as percentages, so only one number
/// belongs here. Rounding matters: files written before [encodeAmplitude] was
/// fixed hold independently-rounded parts, so a 5.0 mA setting is stored as
/// `1.67_1.67_1.67` and sums to 5.01, a precision no IPG has.
String amplitudeCell(String raw) {
  final text = raw.trim();
  if (!text.contains('_')) return text;
  final parts = _amplitudeParts(text);
  if (parts == null) return text;
  return parts.fold(0.0, (a, b) => a + b).toStringAsFixed(1);
}

/// Frequency / pulse-width cell: integer-valued numbers lose the ".0",
/// everything else (including unit-bearing text) is verbatim.
String numCell(String raw) {
  final text = raw.trim();
  final v = double.tryParse(text);
  if (v != null && v == v.roundToDouble()) return '${v.toInt()}';
  return text;
}

/// Vendor-style contact list: `2b(60%) 2c(40%)` for a steered configuration,
/// or plain `case` / `2b` when there is nothing to share out.
///
/// Three internal conventions are dropped as misreading hazards in a printed
/// clinical document: the `E` prefix (vendors write `2b`), the `_` join
/// (`3.3_2.2` under an "Amp (mA)" heading reads as one number), and the
/// per-contact milliamps. The last because the split widget captures a
/// PERCENTAGE, and the stored milliamps are that percentage multiplied out and
/// rounded, so printing them shows derived numbers in place of what was set.
String contactsWithCurrent(String tokens, String amplitude) {
  final contacts = tokens
      .split('_')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .map(
        (t) => t.toLowerCase() == 'case'
            ? 'case'
            : (t.startsWith('E') || t.startsWith('e') ? t.substring(1) : t),
      )
      .toList();
  if (contacts.isEmpty) return '';
  if (contacts.length == 1) return contacts.first;

  final split = _amplitudeParts(amplitude);
  // Only share out when the counts agree: a mismatch means we cannot know which
  // share went to which contact, and guessing is worse than the contacts alone.
  if (split == null || split.length != contacts.length) {
    return contacts.join(' ');
  }
  final total = split.fold(0.0, (a, b) => a + b);
  if (total <= 0) return contacts.join(' ');
  final pct = _percentagesTo100(split, total);
  return [
    for (var i = 0; i < contacts.length; i++) '${contacts[i]}(${pct[i]}%)',
  ].join(' ');
}

/// Whole percentages of [total] that sum to exactly 100.
///
/// Rounding each share independently gives 33/33/33 for three equal contacts,
/// and a printed 99 % reads as a missing share. Largest remainder first, the
/// same rule `encodeAmplitude` uses to make the milliamps sum to the dose.
List<int> _percentagesTo100(List<double> split, double total) {
  final exact = split.map((v) => v / total * 100).toList();
  final out = exact.map((v) => v.floor()).toList();
  var residual = 100 - out.fold<int>(0, (a, b) => a + b);
  final order = List<int>.generate(exact.length, (i) => i)
    ..sort((a, b) {
      final cmp = (exact[b] - out[b]).compareTo(exact[a] - out[a]);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
  for (var k = 0; residual > 0 && k < order.length; k++, residual--) {
    out[order[k]] += 1;
  }
  return out;
}

/// The `_`-joined per-contact amplitudes as numbers, or null when any part is
/// not numeric. Twin of `parseAmplitude`, duplicated to keep this file free of
/// the electrode layer's imports.
List<double>? _amplitudeParts(String amplitude) {
  final parts = amplitude
      .split('_')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .map(double.tryParse)
      .toList();
  if (parts.isEmpty || parts.contains(null)) return null;
  return parts.cast<double>();
}

/// One lead of a configuration as text: "2b(3.3) 2c(2.2)- / case+".
///
/// Shared by both builders so a lead is described one way throughout.
String lateralText(LateralTokens tokens, {required bool left}) {
  final anodes = contactsWithCurrent(
    left ? tokens.leftAnode : tokens.rightAnode,
    '',
  );
  final cathodes = contactsWithCurrent(
    left ? tokens.leftCathode : tokens.rightCathode,
    left ? tokens.leftAmplitude : tokens.rightAmplitude,
  );
  if (anodes.isEmpty && cathodes.isEmpty) return 'not recorded';
  return [
    if (cathodes.isNotEmpty) '$cathodes-',
    if (anodes.isNotEmpty) '$anodes+',
  ].join(' / ');
}

String _scalesCell(Iterable<SessionRow> rows) =>
    _collectScalePairs(rows).map((p) => '${p.name}: ${p.value}').join('\n');

/// Column headers for the lateral session-data table (shared by both reports).
const sessionTableHeaders = [
  '#',
  // Without the clock the dose-response reading of this table is
  // unfalsifiable: two "different" configurations 9 s apart on identical
  // settings are invisible until the time is printed.
  'Time',
  'Side',
  'Group',
  'Freq (Hz)',
  '+',
  '-',
  'Amp (mA)',
  'PW (µs)',
  'Scales',
  // The index the green shading is computed from, and its rank: shading by a
  // number the table never showed made the ranking impossible to reproduce.
  'Index',
  'Notes',
];

/// Relative column widths for [sessionTableHeaders], summing to 100, shared by
/// both report formats.
///
/// Word needs explicit hints: left to auto-fit on content alone, and with most
/// cells holding one to four characters, its ten columns collapsed to a
/// fraction of the page. Widths are sized to the HEADER rather than the data,
/// because at 5 units (26 pt of a 523 pt content area) both formats broke the
/// headings mid-word into "Blo ck", "Sid e", "Gro up".
const sessionTableColumnWeights = <double>[
  7, // Block (an 8 pt bold heading needs ~33 pt with padding; 6 gives 31)
  10, // Time: "09:03:20" at 8 pt needs ~36 pt inside the padding; 8 broke it
  6, // Side
  7, // Group
  6, // Freq (Hz), wraps to two lines by design
  8, // + (anodes)
  11, // - (cathodes with their share, e.g. "2b(60%) 2c(40%)")
  6, // Amp (mA)
  5, // PW (us)
  15, // Scales
  8, // Index ("0.430" over "(rank 6)")
  11, // Notes, where the slack comes from: wrapping prose is normal
];

/// A signed change: "-5", "+0.25", or "0" for none, never "+0".
String _signed(double d) => d == 0 ? '0' : '${d > 0 ? '+' : ''}${_num(d)}';

/// The final configuration's heading when the clinician marked it.
const kLeftOnTitle = 'Left on (marked by the clinician)';

/// The final configuration's heading otherwise: the last block in the file,
/// which a setting tried and rejected would occupy just the same.
const kLastRecordedTitle = 'Last recorded configuration';

/// Two decimals, as every rating in the reports is printed.
String _num(double v) => v.toStringAsFixed(2);

/// The Index column as printed in a session report: the rank's scope is in the
/// header, because the longitudinal report ranks the same block across visits.
const kSessionIndexHeader = 'Index (rank in this session)';

/// The same column in the longitudinal per-visit tables.
const kVisitsIndexHeader = 'Index (rank across all visits)';

/// Columns printed right-aligned, so their digits line up down the column.
const kNumericTableHeaders = {
  'Freq (Hz)',
  'Amp (mA)',
  'PW (\u00B5s)',
  kSessionIndexHeader,
  kVisitsIndexHeader,
};

final int _indexColumn = sessionTableHeaders.indexOf('Index');

/// A built report, plus whether any character had to be replaced to render it.
///
/// [lostCharacters] lets the UI say so. The PDF's Latin-1 fallback turns an
/// unsupported glyph into `?`, which leaves a note that lost characters
/// indistinguishable from one that never had them.
typedef ReportBytes = ({Uint8List bytes, bool lostCharacters});

/// Printed in place of the targets line when nobody set any.
///
/// The alternative, inventing `min` over 0..10 for every scale, asserts a
/// clinical intent no one expressed: on scales that measure the magnitude of
/// the named thing it scores falling mood and falling energy as improvement.
const kNoTargetsText =
    'Scale targets: none set, so no ranking was applied. Open this session in '
    'the app and set a target per scale to rank the configurations.';

/// Legend for the mark on starred blocks in the session-data table.
const kStarredLegend =
    '* Starred by the clinician during the visit as a particularly good '
    'configuration. A clinical impression, not part of the ranking.';

/// Clinical-liability statement printed under the session-data table, verbatim
/// from the desktop (`report_common.add_table_legend`). Deliberately not
/// paraphrased, and shared so both formats carry it identically.
const kRankingDisclaimer =
    'Note: The highlighted rows are derived exclusively from the annotated '
    'symptom and side effect ratings and represent a computational ranking '
    'intended '
    'solely as a reference. This color-coded indication does not constitute '
    'clinical guidance. The ranking does not account for side effects, '
    'tolerability, or the observations in the Notes column, and is not a '
    'recommendation to program these settings.';

/// Everything needed to draw the scales-timeline chart, so the PDF and Word
/// renderers share one source of truth. Mirrors the desktop
/// `build_scales_chart` inputs (`report_chart_utils.py:216`).
class ScalesChartSpec {
  const ScalesChartSpec({
    required this.series,
    required this.xs,
    required this.yMin,
    required this.yMax,
    required this.amplitude,
    this.frequency = const {},
    this.pulseWidth = const {},
    required this.aggregateIndex,
    required this.bestXs,
    required this.secondXs,
    required this.title,
    required this.xLabel,
    required this.yLabel,
    this.xTickLabels = const {},
    this.xGroups = const [],
    this.rankScope = '',
  });

  /// One entry per scale, in encounter order: name -> {x -> value}. Missing x
  /// values are absent, which the painter renders as a break in the line.
  final Map<String, Map<int, double>> series;

  /// Sorted x positions (block IDs) present in any series.
  final List<int> xs;

  /// Left-axis bounds. Clamped to the union of declared scale ranges when the
  /// prefs supply one, else auto-fitted to the data.
  final double yMin, yMax;

  /// Total delivered current per side, per x, in mA. Drawn as its own strip
  /// under the index: without the dose, the x axis is an ordinal with no
  /// clinical meaning and the figure cannot be read as dose-response.
  final Map<String, Map<int, double>> amplitude;

  /// Frequency (Hz) and pulse width (µs) per side, per x, under the dose, as
  /// the live view in the app draws them.
  final Map<String, Map<int, double>> frequency, pulseWidth;

  /// Aggregate index per x, on its own fixed 0..1 panel. Empty when no targets.
  final Map<int, double> aggregateIndex;

  /// x positions to band green: EVERY block of the best-scoring setting, and
  /// every block of the second. Empty when there is no index to rank by.
  ///
  /// Lists, not single blocks: the unit ranked is a stimulation setting, and
  /// banding only one of two identical blocks presents a repeat rating as a
  /// rival configuration.
  final List<int> bestXs, secondXs;

  int? get bestX => bestXs.isEmpty ? null : bestXs.first;
  int? get secondX => secondXs.isEmpty ? null : secondXs.first;

  final String title, xLabel, yLabel;

  /// Text for each x tick, when the position itself is not the label.
  ///
  /// The session figure's x IS the block number, so it needs none. The
  /// longitudinal figures index visits, where the position is internal and the
  /// label is `20260626_01`; printing the index would assert that "3" means
  /// something.
  final Map<int, String> xTickLabels;

  /// A second row of x labels, each centred under the x positions [from] to
  /// [to] with a separator after it: the visit date under its blocks.
  final List<({int from, int to, String label})> xGroups;

  /// Where the rank bands rank, appended to "Rank 1" in the legend, so a reader
  /// holding two reports sees why the same block ranks differently in each.
  final String rankScope;

  bool get isEmpty => series.isEmpty || xs.isEmpty;
}

/// Everything the report builders need, computed once from the raw rows.
class SessionReportData {
  const SessionReportData({
    required this.sessionDate,
    required this.generatedOn,
    required this.startTime,
    required this.endTime,
    required this.endDate,
    required this.utcOffset,
    required this.sourceFile,
    required this.rowCount,
    required this.lastConfig,
    required this.firstConfig,
    required this.configChanges,
    required this.replicateSpread,
    required this.numDistinctConfigs,
    required this.hasInitial,
    required this.initScales,
    required this.initNotes,
    this.medications = '',
    this.sessionDetails = '',
    this.hasStars = false,
    required this.tableData,
    required this.electrodeModel,
    this.leftOnMarked = false,
    required this.hasElectrodeConfig,
    required this.initialTokens,
    required this.finalTokens,
    required this.hasRows,
    required this.span,
    required this.numConfigs,
    required this.ampL,
    required this.ampR,
    required this.freqL,
    required this.freqR,
    required this.pwL,
    required this.pwR,
    required this.chart,
    required this.bestBlocks,
    required this.secondBlocks,
    required this.targetsText,
    required this.hasTargets,
    required this.blockIndex,
    required this.response,
    required this.scalesRated,
    required this.initialRow,
    required this.finalRow,
  });

  /// The date the session was RECORDED, "yyyy-MM-dd", from the rows' own
  /// timestamps, or [generatedOn] when no row carries a parseable one.
  ///
  /// Distinct from [generatedOn]: taking both from the export clock made a
  /// report produced a fortnight later claim the session happened that day.
  final String sessionDate;

  final String generatedOn;

  /// Clock time of the first and last entry, "HH:mm", or '' when unknown.
  final String startTime, endTime;

  /// Date of the last entry, "yyyy-MM-dd", or '' when unknown.
  final String endDate;

  /// UTC offset of those times, e.g. "+02:00", or '' when the rows carry none.
  final String utcOffset;

  /// Provenance: without these the report cannot be tied back to one file among
  /// several runs of the same session.
  final String sourceFile;
  final int rowCount;

  /// Whether any baseline (is_initial == 1) row exists.
  final bool hasInitial;

  /// Deduplicated baseline scales, from the latest initial session only.
  final List<ScalePair> initScales;

  final String initNotes;

  /// Medications from the latest initial assessment, or ''.
  final String medications;

  /// Pathology, target and IPG as one printable line, or '' when none.
  final String sessionDetails;

  /// Whether any block is starred, so the table legend explains the mark.
  final bool hasStars;

  /// Lateral table rows, two per recording block (L then R), keyed by
  /// [sessionTableHeaders]. Cells may contain '\n' for stacked values.
  final List<List<String>> tableData;

  /// Electrode model label (first non-empty of initial/final): one name when
  /// both leads are the same model, else each side's. May be empty.
  final String electrodeModel;

  /// Whether the clinician marked the block the patient was left on, which is
  /// then the final configuration instead of the last one recorded.
  final bool leftOnMarked;

  /// The heading over the final configuration: only a marked block is called
  /// the one the patient was left on.
  String get finalConfigTitle =>
      leftOnMarked ? kLeftOnTitle : kLastRecordedTitle;

  final bool hasElectrodeConfig;

  /// Anode-cathode tokens for the text fallback, null when absent.
  final LateralTokens? initialTokens;
  final LateralTokens? finalTokens;

  final bool hasRows;

  /// The first-to-last annotation interval, named for what it measures rather
  /// than "session duration", which it is not.
  final String span;

  /// Recording blocks, baseline excluded. Counting the baseline too blended the
  /// pre-session settings into the "tested" parameter ranges, so 7.0 mA could
  /// not be told apart from where the patient started.
  final int numConfigs;

  /// Distinct stimulation settings among those blocks. Lower than [numConfigs]
  /// whenever a setting was rated more than once.
  final int numDistinctConfigs;
  final String ampL, ampR, freqL, freqR, pwL, pwR;

  final ScalesChartSpec chart;

  /// Block IDs to shade green in the session-data table: the SAME blocks the
  /// chart bands mark. The desktop ranks the table and the chart by two
  /// different algorithms that can disagree, and two green markers pointing at
  /// different blocks in one clinical document is indefensible.
  final List<int> bestBlocks, secondBlocks;

  /// The largest index spread between repeat ratings of one setting, or null
  /// when nothing was rated twice. See [rankingResolutionNote].
  final double? replicateSpread;

  /// What the ranking's numbers are worth, in the session's own terms: without
  /// it a third-decimal difference reads as a finding.
  String? get rankingResolutionNote {
    final spread = replicateSpread;
    if (spread == null) return null;
    return 'Repeat ratings of an unchanged setting differ by up to '
        '${spread.toStringAsFixed(3)} on this index in this session, so two '
        'settings closer together than that are not distinguishable by these '
        'ratings.';
  }

  /// Named when several blocks tie for the highest index, since the figure
  /// bands all of them and a reader would otherwise look for one winner.
  String get bestSettingText => bestBlocks.length <= 1
      ? ''
      : 'Configurations ${bestBlocks.join(', ')} share the highest index.';

  /// The configuration in force at the START of the session, same shape as
  /// [lastConfig]. From the baseline row: the state the patient arrived in.
  final Map<String, String> firstConfig;

  /// What changed between [firstConfig] and [lastConfig], one line per side
  /// that moved, plus an explicit line for anything that did not. Answers
  /// "what did you change?" without diffing a fourteen-row table by eye.
  final List<String> configChanges;

  /// The last recorded configuration, as a printable summary: side -> lines.
  /// Nothing in the TSV records that a clinician *chose* it, so "final
  /// settings" would assert a decision the data does not contain.
  final Map<String, String> lastConfig;

  /// Per scale: its first and last recorded value and the delta. Without it the
  /// clinical bottom line of the encounter appears nowhere in three pages.
  final List<({String name, double first, double last})> response;

  /// Block -> how many scales were rated there. The index averages only the
  /// scales present at that block, so blocks with different rated sets are not
  /// comparable: one where only a low Anxiety was rated can outrank a
  /// fully-rated block.
  final Map<int, int> scalesRated;

  /// Caption for the session-scales figure. The chart is one click out of a
  /// .docx, so it has to carry its own n and explain its green bands.
  String get figureCaption =>
      'Figure 1. Symptom and side effect ratings by rated configuration. '
      '${hasTargets ? 'Middle panel: aggregate index (0-1; 1 = best); green '
                'bands mark the highest and second-highest.' : 'No scale '
                'targets were set, so no ranking is shown.'}'
      '${chart.amplitude.values.any((m) => m.isNotEmpty) ? ' Below: amplitude, '
                'frequency and pulse width per side.' : ''}';

  /// The response as a grid, one column per scale: short enough to sit on
  /// page one next to what was tried, and read down a column per scale.
  List<List<String>> get responseGrid => response.isEmpty
      ? const []
      : [
          ['', for (final r in response) r.name],
          ['First', for (final r in response) _num(r.first)],
          ['Last', for (final r in response) _num(r.last)],
          ['Change', for (final r in response) _signed(r.last - r.first)],
        ];

  /// The parameters tried, one side per column.
  List<List<String>> get parameterRows => [
    ['Amplitude', ampL, ampR],
    ['Frequency', freqL, freqR],
    ['Pulse width', pwL, pwR],
  ];

  /// The size of the session, as label and value.
  List<List<String>> get extentRows => [
    ['Annotation span (first to last configuration)', span],
    ['Configurations tested', configCountText(this)],
  ];

  /// How the index is computed, for the legend. Printing the modes alone left
  /// the equal weighting invisible, and equal weighting is a clinical
  /// judgement: in OCD, Mood and Energy are side-effect monitors, not outcomes.
  String get indexMethod =>
      'Aggregate index: unweighted mean over the scales rated at that '
      'configuration of '
      'each value normalised into its declared range and oriented by its '
      'target, clipped to 0-1; 1 = best.';

  /// "Scale targets: name: min; other: max" for the table legend block, or ''
  /// when no scale has an active optimisation mode.
  final String targetsText;

  /// False for a TSV opened from elsewhere, where the builders print
  /// [kNoTargetsText] rather than rank against invented targets.
  final bool hasTargets;

  /// Block -> aggregate index. The document shades rows by this number, so it
  /// has to be printable: a ranking a reader cannot reproduce is not auditable.
  final Map<int, double> blockIndex;

  /// The rows the electrode configuration was taken from, so the caller can
  /// render images of exactly the configurations the text describes.
  final SessionRow? initialRow, finalRow;

  bool get hasRecording => tableData.isNotEmpty;

  /// Data-row index to the fill of its ranked setting, for every format and
  /// every report that prints this table.
  Map<int, int> get rowFills => {
    for (final (i, row) in tableData.indexed)
      if (int.tryParse(row.first) case final block?)
        if (bestBlocks.contains(block))
          i: kBestFill
        else if (secondBlocks.contains(block))
          i: kSecondFill,
  };

  /// The table as printed: with no targets nothing is ranked, so the Index
  /// column would be blank and read as missing data. Its width goes to Notes.
  List<String> get tableHeaders => hasTargets
      ? [
          for (final h in sessionTableHeaders)
            h == 'Index' ? kSessionIndexHeader : h,
        ]
      : [
          for (final h in sessionTableHeaders)
            if (h != 'Index') h,
        ];

  List<double> get tableWeights {
    if (hasTargets) return sessionTableColumnWeights;
    final w = List<double>.of(sessionTableColumnWeights);
    w.last += w.removeAt(_indexColumn);
    return w;
  }

  List<List<String>> get tableRows => hasTargets
      ? tableData
      : [for (final r in tableData) List.of(r)..removeAt(_indexColumn)];

  /// The encounter, for the header/footer: "2026-06-26, 09:12-11:40", or
  /// "2026-06-26 22:10 to 2026-06-27 08:30" when it ends on a later day. ASCII on
  /// purpose: with no Unicode TTF bundled the PDF falls back to Helvetica,
  /// which cannot draw an en dash, and the sanitiser only runs over user text.
  String get sessionStamp {
    if (startTime.isEmpty) return sessionDate;
    final span = endDate.isEmpty || endDate == sessionDate
        ? '$sessionDate, $startTime-$endTime'
        : '$sessionDate $startTime to $endDate $endTime';
    return '$span${utcOffset.isEmpty ? '' : ' (UTC$utcOffset)'}';
  }
}

/// Build the scales-chart spec, applying the same target/index/ranking rules as
/// the desktop chart (`report_chart_utils.build_scales_chart`).
ScalesChartSpec buildScalesChartSpec({
  required Map<String, Map<int, double>> timeline,
  required List<ScalePref> prefs,

  /// Block -> a key identifying its stimulation setting. Blocks sharing a key
  /// are the SAME configuration rated more than once, so they rank together.
  /// Omit to fall back to ranking each block on its own.
  Map<int, String> settingOf = const {},
  Map<String, Map<int, double>> amplitude = const {},
  Map<String, Map<int, double>> frequency = const {},
  Map<String, Map<int, double>> pulseWidth = const {},
  String xLabel = 'Configuration',
  String yLabel = 'Scale Value',
}) {
  final xs = <int>{};
  var dataMin = double.infinity;
  var dataMax = double.negativeInfinity;
  for (final byX in timeline.values) {
    for (final e in byX.entries) {
      xs.add(e.key);
      if (e.value < dataMin) dataMin = e.value;
      if (e.value > dataMax) dataMax = e.value;
    }
  }
  final sortedXs = xs.toList()..sort();

  final targets = parseScaleTargets(prefs);

  // Prefer the union of declared ranges, else fit the data, widening a flat
  // series so the axis always has height.
  var yMin = dataMin;
  var yMax = dataMax;
  final declared = declaredScaleRange(targets);
  if (declared != null) {
    yMin = math.min(dataMin, declared.$1);
    yMax = math.max(dataMax, declared.$2);
  } else if (!dataMin.isFinite || dataMin == dataMax) {
    yMin = dataMin.isFinite ? dataMin - 1 : 0;
    yMax = dataMax.isFinite ? dataMax + 1 : 1;
  }

  // No targets means no index at all: with an empty target map every scale
  // scores a neutral 0.5 at half weight, so every block ties and the ranking
  // falls out in iteration order. Unlike the desktop there is no minimum scale
  // count, since one scale against its own target ranks the blocks fine.
  final index = targets.isEmpty
      ? const <int, double>{}
      : computeAggregateIndex(timeline, sortedXs, targets);
  final ranks = rankBlocks(index);

  return ScalesChartSpec(
    series: timeline,
    amplitude: amplitude,
    frequency: frequency,
    pulseWidth: pulseWidth,
    xs: sortedXs,
    yMin: yMin,
    yMax: yMax,
    aggregateIndex: index,
    bestXs: blocksAtRank(ranks, 1),
    secondXs: blocksAtRank(ranks, 2),
    // No title: the report's section heading and caption already name it.
    title: '',
    xLabel: xLabel,
    yLabel: yLabel,
    rankScope: 'in this session',
  );
}

/// The spread between repeat ratings of one setting: how much the ranking's
/// numbers move when nothing changes. Null when no setting was rated twice.
/// Two settings closer together than this are not distinguishable.
double? replicateSpread(Map<int, double> index, Map<int, String> settingOf) {
  final byKey = <String, List<double>>{};
  for (final e in index.entries) {
    final key = settingOf[e.key];
    if (key == null) continue;
    (byKey[key] ??= []).add(e.value);
  }
  double? worst;
  for (final vals in byKey.values) {
    if (vals.length < 2) continue;
    final spread =
        vals.reduce((a, b) => a > b ? a : b) -
        vals.reduce((a, b) => a < b ? a : b);
    if (worst == null || spread > worst) worst = spread;
  }
  return worst;
}

/// "name: min; other: max; third: 4.5" for the table legend, or '' when every
/// scale is ignored. Mirrors `report_common.add_table_legend`.
String _targetsText(List<ScalePref> prefs) {
  final parts = <String>[];
  for (final p in prefs) {
    switch (p.mode) {
      // The bounds travel with the mode: the index normalises into them, so a
      // reader cannot reproduce the score without knowing what they were.
      case ScaleMode.min:
        parts.add('${p.name}: min of ${trimZeros(p.min)}-${trimZeros(p.max)}');
      case ScaleMode.max:
        parts.add('${p.name}: max of ${trimZeros(p.min)}-${trimZeros(p.max)}');
      case ScaleMode.custom:
        parts.add(
          '${p.name}: ${trimZeros(p.custom ?? 0)} '
          'of ${trimZeros(p.min)}-${trimZeros(p.max)}',
        );
      case ScaleMode.ignore:
        break;
    }
  }
  return parts.join('; ');
}

LateralTokens? tokensOf(SessionRow? r) => r == null
    ? null
    : (
        leftAnode: r.leftAnode,
        leftCathode: r.leftCathode,
        leftAmplitude: r.leftAmplitude,
        rightAnode: r.rightAnode,
        rightCathode: r.rightCathode,
        rightAmplitude: r.rightAmplitude,
      );

/// One line per side that changed between [from] and [to], and one saying so
/// when a parameter held steady on both sides. Compares the printable per-side
/// summaries, not raw columns, so it speaks the same language as the box above.
/// Each line carries its own label, because a caller that prefixed them all
/// would print "Changed: Unchanged: ...".
List<String> _configChanges(SessionRow? from, SessionRow? to) {
  if (from == null || to == null) return const [];
  final out = <String>[];
  // Contacts and total amplitude separately: the contact notation carries each
  // contact's share of the current, not the dose, so a dose change on the same
  // contacts would otherwise go unreported.
  String dose(SessionRow r, bool left) =>
      amplitudeCell(left ? r.leftAmplitude : r.rightAmplitude);
  for (final left in [true, false]) {
    final side = left ? 'Left' : 'Right';
    final before = lateralText(tokensOf(from)!, left: left);
    final after = lateralText(tokensOf(to)!, left: left);
    if (before != after) out.add('$side contacts: $before -> $after');
    final (was, now) = (dose(from, left), dose(to, left));
    if (was != now && was.isNotEmpty && now.isNotEmpty) {
      out.add('$side amplitude: $was -> $now mA');
    }
  }
  // What held steady, so the reader does not have to check.
  bool same(String Function(SessionRow) pick) =>
      pick(from).trim() == pick(to).trim();
  final steady = <String>[
    if (dose(from, true) == dose(to, true) &&
        dose(from, false) == dose(to, false))
      'amplitude',
    if (same((r) => r.leftStimFreq) && same((r) => r.rightStimFreq))
      'frequency',
    if (same((r) => r.leftPulseWidth) && same((r) => r.rightPulseWidth))
      'pulse width',
  ];
  if (steady.isNotEmpty) {
    final list = steady.length == 1
        ? steady.single
        : '${steady.sublist(0, steady.length - 1).join(', ')} and ${steady.last}';
    out.add('Unchanged: $list.');
  }
  if (out.isEmpty) out.add('No change from the pre-session configuration.');
  return out;
}

/// "7" or, when a setting was rated more than once, "7 (6 distinct settings)".
///
/// The block count alone overstates how much was explored: blocks that are
/// byte-identical in every stimulation column were one setting rated twice.
String configCountText(SessionReportData data) =>
    data.numDistinctConfigs > 0 && data.numDistinctConfigs != data.numConfigs
    ? '${data.numConfigs} (${data.numDistinctConfigs} distinct settings)'
    : '${data.numConfigs}';

/// One printable line per side for the last recorded configuration, plus the
/// programme, for the page-1 summary box. The strongest claim about what was
/// decided that the data actually supports.
Map<String, String> _lastConfigLines(SessionRow? r) {
  if (r == null) return const {};
  String side(
    String anode,
    String cathode,
    String amp,
    String freq,
    String pw,
  ) {
    final cathodes = contactsWithCurrent(cathode, amp);
    final anodes = contactsWithCurrent(anode, '');
    final total = _paramRange([amp], splitSum: true);
    final totalText = total == null
        ? ''
        : amp.contains('_')
        ? amplitudeCell(amp)
        : trimZeros(total.$2);
    final f = freq.trim().isEmpty ? '' : ', ${numCell(freq)} Hz';
    final p = pw.trim().isEmpty ? '' : ', ${numCell(pw)} \u00B5s';
    // Parameters without contacts are still printed: a side's dose is not
    // dropped because its contacts were not recorded.
    if (cathodes.isEmpty && anodes.isEmpty) {
      final params = [
        if (total != null) '$totalText mA',
        if (f.isNotEmpty) f.substring(2),
        if (p.isNotEmpty) p.substring(2),
      ];
      return params.join(', ');
    }
    final dose = total == null ? '' : ' = $totalText mA';
    return '$cathodes-'
        '${anodes.isEmpty ? '' : ' / $anodes+'}$dose$f$p';
  }

  final out = <String, String>{};
  final left = side(
    r.leftAnode,
    r.leftCathode,
    r.leftAmplitude,
    r.leftStimFreq,
    r.leftPulseWidth,
  );
  final right = side(
    r.rightAnode,
    r.rightCathode,
    r.rightAmplitude,
    r.rightStimFreq,
    r.rightPulseWidth,
  );
  if (left.isNotEmpty) out['Left'] = left;
  if (right.isNotEmpty) out['Right'] = right;
  if (r.programId.trim().isNotEmpty) out['Group'] = r.programId.trim();
  return out;
}

/// Compute all report sections from the session [rows].
///
/// [scalePrefs] carries the per-scale optimisation modes and bounds that drive
/// the chart's aggregate index, its green bands and the table's row shading.
/// Omitted means no targets, hence no ranking at all.
/// A note shown with its full date, outside the session it was not part of.
typedef DatedNote = ({String date, String time, String text});

/// [notes] as dated rows, oldest first, skipping any with no time or text.
List<DatedNote> datedNotes(Iterable<Annotation> notes) => [
  for (final n
      in notes.toList()..sort((a, b) => a.acqTime.compareTo(b.acqTime)))
    if (recordedTime(n.acqTime).isNotEmpty && n.notes.trim().isNotEmpty)
      (
        date: recordedDate(n.acqTime),
        time: recordedTime(n.acqTime),
        text: n.notes,
      ),
];

SessionReportData buildSessionReportData({
  required List<SessionRow> rows,
  DateTime? generatedAt,
  List<ScalePref>? scalePrefs,
  String sourceFile = '',

  /// Notes recorded alongside this session, from a `task-notes` file. Each
  /// becomes its own row in the data table, placed by its own clock time, with
  /// only the Time and Notes cells filled: a note carries no configuration, so
  /// filling the stimulation cells would assert it was recorded against one.
  List<Annotation> notes = const [],
}) {
  final dt = generatedAt ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  String ymd(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
  final generatedOn = ymd(dt);

  final recorded = _recordedInOrder(rows);
  final sessionDate = recorded.isEmpty
      ? generatedOn
      : recordedDate(recorded.first);
  final startTime = recorded.isEmpty ? '' : _hourMinute(recorded.first);
  final endTime = recorded.isEmpty ? '' : _hourMinute(recorded.last);
  final endDate = recorded.isEmpty ? '' : recordedDate(recorded.last);

  // Split like the desktop: is_initial coerced == 1 -> baseline (Step 1),
  // everything else -> recording blocks (the session-data table).
  final initialRows = rows.where((r) => coerceInt(r.isInitial) == 1).toList();
  final recordingRows = rows.where((r) => coerceInt(r.isInitial) != 1).toList();

  // Initial clinical notes come from the LATEST initial session only.
  final latestInit = _latestRow(initialRows);
  final initSessionRows = latestInit == null
      ? const <SessionRow>[]
      : initialRows
            .where(
              (r) => coerceInt(r.appendId) == coerceInt(latestInit.appendId),
            )
            .toList();
  final initScales = _collectScalePairs(initSessionRows);
  final initNotes = latestInit?.notes.trim() ?? '';
  final starred = starredBlocksIn(rows);
  final leftIpg = sessionValueIn(rows, (r) => r.leftIpgModel);
  final rightIpg = sessionValueIn(rows, (r) => r.rightIpgModel);
  final sessionDetails = [
    for (final (label, value) in [
      ('DBS indication', sessionValueIn(rows, (r) => r.pathology)),
      ('Target', sessionValueIn(rows, (r) => r.target)),
      (
        'IPG',
        rightIpg.isEmpty || rightIpg == leftIpg
            ? leftIpg
            : 'left $leftIpg, right $rightIpg',
      ),
    ])
      if (value.isNotEmpty) '$label: $value',
  ].join('    ');

  final blocks = <int, List<SessionRow>>{};
  for (final row in recordingRows) {
    (blocks[coerceInt(row.blockId)] ??= []).add(row);
  }

  // Summary over the RECORDING rows only: the baseline block is the state the
  // patient arrived in, and including it widened every "tested" range.
  final span = _spanText(rows);
  final numConfigs = recordingRows
      .map((r) => coerceInt(r.blockId))
      .toSet()
      .length;
  final numDistinctConfigs = recordingRows
      .map((r) => _paramKey(r).join(_sep))
      .toSet()
      .length;
  final ampL = _valuesText(
    blocks,
    (r) => r.leftAmplitude,
    'mA',
    1,
    splitSum: true,
  );
  final ampR = _valuesText(
    blocks,
    (r) => r.rightAmplitude,
    'mA',
    1,
    splitSum: true,
  );
  final freqL = _valuesText(blocks, (r) => r.leftStimFreq, 'Hz', 0);
  final freqR = _valuesText(blocks, (r) => r.rightStimFreq, 'Hz', 0);
  final pwL = _valuesText(blocks, (r) => r.leftPulseWidth, 'µs', 0);
  final pwR = _valuesText(blocks, (r) => r.rightPulseWidth, 'µs', 0);

  // Electrode configuration: latest baseline row = initial settings, latest
  // recording row = final settings.
  // The block the clinician marked as the one the patient was left on wins
  // over the last one recorded, which may be a setting tried and rejected.
  final marked = finalBlockIn(recordingRows);
  final leftOn = marked == null
      ? null
      : _latestRow([
          for (final r in recordingRows)
            if (r.blockId == marked) r,
        ]);
  final latestFinal = leftOn ?? _latestRow(recordingRows);
  String modelOf(String Function(SessionRow) side) => [
    for (final r in [latestInit, latestFinal])
      if (r != null) side(r).trim(),
  ].firstWhere((m) => m.isNotEmpty, orElse: () => '');
  final leftModel = modelOf((r) => r.leftElectrodeModel);
  final rightModel = modelOf((r) => r.rightElectrodeModel);
  final electrodeModel = rightModel.isEmpty || rightModel == leftModel
      ? leftModel
      : 'left $leftModel, right $rightModel';

  // Deliberately no fallback to `defaultScalePrefsFor`: fabricating `min` over
  // 0..10 for a file nobody configured produced a ranking, two green bands and
  // a printed "Scale targets" line that all asserted a clinical intent no one
  // expressed.
  final prefs = scalePrefs ?? const <ScalePref>[];
  final hasTargets = parseScaleTargets(prefs).isNotEmpty;
  final timeline = scaleTimeline(rows);

  // Which blocks were the same setting. The ranking groups on this, so a
  // configuration rated twice scores once and is banded once.
  final settingOf = <int, String>{
    for (final entry in blocks.entries)
      entry.key: _paramKey(entry.value.first).join(_sep),
  };
  final amplitudeSeries = <String, Map<int, double>>{};
  for (final entry in blocks.entries) {
    void put(String side, String raw) {
      final r = _paramRange([raw], splitSum: true);
      // Rounded to a tenth, matching the table cell: an IPG steps in 0.1 mA,
      // and files written before encodeAmplitude was fixed hold sums like 5.01.
      if (r != null) {
        (amplitudeSeries[side] ??= <int, double>{})[entry.key] =
            (r.$1 * 10).round() / 10;
      }
    }

    put('Left', entry.value.first.leftAmplitude);
    put('Right', entry.value.first.rightAmplitude);
  }
  final frequencySeries = <String, Map<int, double>>{};
  final pulseWidthSeries = <String, Map<int, double>>{};
  for (final entry in blocks.entries) {
    final r = entry.value.first;
    for (final (series, side, raw) in [
      (frequencySeries, 'Left', r.leftStimFreq),
      (frequencySeries, 'Right', r.rightStimFreq),
      (pulseWidthSeries, 'Left', r.leftPulseWidth),
      (pulseWidthSeries, 'Right', r.rightPulseWidth),
    ]) {
      final v = double.tryParse(raw.trim());
      if (v != null) (series[side] ??= <int, double>{})[entry.key] = v;
    }
  }

  final chart = buildScalesChartSpec(
    timeline: timeline,
    prefs: prefs,
    settingOf: settingOf,
    amplitude: amplitudeSeries,
    frequency: frequencySeries,
    pulseWidth: pulseWidthSeries,
  );

  // Table shading and chart bands from ONE ranking, so they cannot disagree.
  final bestBlocks = chart.bestXs;
  final secondBlocks = chart.secondXs;
  final spread = replicateSpread(chart.aggregateIndex, settingOf);

  // The same ranking the figure bands and the table shades by, so the printed
  // rank, the green and the index always agree. Colour alone is not enough:
  // #96D2A0 and #C8EBCD are luminance 0.78 and 0.88, so photocopied they are
  // indistinguishable from white and from each other.
  final rankOf = rankBlocks(chart.aggregateIndex);

  final scalesRated = <int, int>{
    for (final entry in blocks.entries)
      entry.key: _collectScalePairs(entry.value).length,
  };

  // First-to-last delta per session scale, the response half of a dose-response
  // record.
  final response = <({String name, double first, double last})>[];
  {
    final firstSeen = <String, double>{};
    final lastSeen = <String, double>{};
    for (final row in recordingRows) {
      for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
        if (pair.name.isEmpty || isScaleValueOmitted(pair.value)) continue;
        final v = double.tryParse(pair.value.trim());
        if (v == null || !v.isFinite) continue;
        firstSeen.putIfAbsent(pair.name, () => v);
        lastSeen[pair.name] = v;
      }
    }
    for (final name in firstSeen.keys) {
      response.add((
        name: name,
        first: firstSeen[name]!,
        last: lastSeen[name]!,
      ));
    }
  }

  DateTime? previousBlockTime;

  // Two rows (L / R) per block. Scales and notes belong to the BLOCK, so they
  // go on the L row only: the Word builder vertically merges the pair and the
  // PDF reads as merged. Printed on both, a duplicated note reads as two
  // separate observations.
  final tableData = <List<String>>[];
  final blockKeys = <String>[];
  for (final entry in blocks.entries) {
    final first = entry.value.first;
    final scales = _scalesCell(entry.value);
    final stamps = _stamps(entry.value);
    final when = stamps.isEmpty ? null : stamps.first;
    final gap = _gapText(previousBlockTime, when);
    previousBlockTime = when ?? previousBlockTime;

    final idx = chart.aggregateIndex[entry.key];
    final indexCell = idx == null
        ? ''
        : '${idx.toStringAsFixed(indexDecimals)}\n(rank ${rankOf[entry.key]})';
    List<String> side(bool left) => [
      starred.contains('${entry.key}') ? '${entry.key} *' : '${entry.key}',
      left
          ? [
              if (_onLaterDay(first.acqTime, sessionDate))
                recordedDate(first.acqTime),
              _clock(first),
              if (gap.isNotEmpty) '($gap)',
            ].join('\n')
          : '',
      left ? 'L' : 'R',
      first.programId,
      numCell(left ? first.leftStimFreq : first.rightStimFreq),
      contactsWithCurrent(left ? first.leftAnode : first.rightAnode, ''),
      contactsWithCurrent(
        left ? first.leftCathode : first.rightCathode,
        left ? first.leftAmplitude : first.rightAmplitude,
      ),
      amplitudeCell(left ? first.leftAmplitude : first.rightAmplitude),
      numCell(left ? first.leftPulseWidth : first.rightPulseWidth),
      left ? scales : '',
      left ? indexCell : '',
      left ? first.notes : '',
    ];
    tableData.add(side(true));
    tableData.add(side(false));
    blockKeys.add(
      _clock(first).isEmpty
          ? ''
          : '${recordedDate(first.acqTime)} ${_clock(first)}',
    );
  }

  // Notes from an accompanying file, interleaved by their own clock time.
  //
  // Sorted as GROUPS, not rows: a block contributes an L row and an R row that
  // the Word builder merges vertically, so anything that could place a note
  // between them would break the merge. Each block is one group with one time,
  // each note a group of one.
  final lastDate = endDate.isEmpty ? sessionDate : endDate;
  final inSession = [
    for (final n in notes)
      if (recordedDate(n.acqTime).compareTo(sessionDate) >= 0 &&
          recordedDate(n.acqTime).compareTo(lastDate) <= 0)
        n,
  ];
  if (inSession.isNotEmpty) {
    final groups = <(String, List<List<String>>)>[];
    for (var i = 0; i + 1 < tableData.length; i += 2) {
      groups.add((blockKeys[i ~/ 2], [tableData[i], tableData[i + 1]]));
    }
    final blank = List<String>.filled(sessionTableHeaders.length, '');
    for (final note in inSession) {
      final at = recordedTime(note.acqTime);
      if (at.isEmpty || note.notes.trim().isEmpty) continue;
      groups.add((
        '${recordedDate(note.acqTime)} $at',
        [
          List<String>.of(blank)
            ..[1] = _onLaterDay(note.acqTime, sessionDate)
                ? '${recordedDate(note.acqTime)}\n$at'
                : at
            ..[sessionTableHeaders.length - 1] = note.notes,
        ],
      ));
    }
    // Stable, and a group with no readable time keeps its position rather than
    // sorting to the top as an empty string.
    final keyed = [for (final (i, g) in groups.indexed) (i, g)]
      ..sort((a, b) {
        final x = a.$2.$1;
        final y = b.$2.$1;
        if (x.isEmpty || y.isEmpty) return a.$1.compareTo(b.$1);
        final c = x.compareTo(y);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    tableData
      ..clear()
      ..addAll([for (final e in keyed) ...e.$2.$2]);
  }

  return SessionReportData(
    sessionDate: sessionDate,
    generatedOn: generatedOn,
    startTime: startTime,
    endTime: endTime,
    endDate: endDate,
    utcOffset: _utcOffset(rows),
    sourceFile: sourceFile,
    rowCount: rows.length,
    lastConfig: _lastConfigLines(latestFinal),
    firstConfig: _lastConfigLines(latestInit),
    configChanges: _configChanges(latestInit, latestFinal),
    response: response,
    scalesRated: scalesRated,
    numDistinctConfigs: numDistinctConfigs,
    chart: chart,
    bestBlocks: bestBlocks,
    secondBlocks: secondBlocks,
    replicateSpread: spread,
    targetsText: hasTargets ? _targetsText(prefs) : kNoTargetsText,
    hasTargets: hasTargets,
    blockIndex: chart.aggregateIndex,
    initialRow: latestInit,
    finalRow: latestFinal,
    hasInitial: latestInit != null,
    initScales: initScales,
    initNotes: initNotes,
    medications: latestInit?.medications.trim() ?? '',
    sessionDetails: sessionDetails,
    hasStars: starred.isNotEmpty,
    tableData: tableData,
    electrodeModel: electrodeModel,
    leftOnMarked: leftOn != null,
    hasElectrodeConfig: latestInit != null || latestFinal != null,
    initialTokens: tokensOf(latestInit),
    finalTokens: tokensOf(latestFinal),
    hasRows: rows.isNotEmpty,
    span: span,
    numConfigs: numConfigs,
    ampL: ampL,
    ampR: ampR,
    freqL: freqL,
    freqR: freqR,
    pwL: pwL,
    pwR: pwR,
  );
}
