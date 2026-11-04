/// Pure computation behind the longitudinal report: one entry per visit, and
/// the two figures the desktop draws.
///
/// Clinical scales are plotted against the visit (one assessment per visit),
/// session scales against visit + block (several configurations per visit).
/// Neither carries the aggregate index or its bands: the index is normalised
/// within a session, so ranking across visits would compare numbers that were
/// never on the same scale. A block index concatenated across files would
/// assert the same false comparability.
library;

import 'dart:math' as math;

import '../core/annotation.dart';
import '../core/brand_palette.dart' show kBestFill, kSecondFill;
import '../core/session/longitudinal.dart'
    show extractPatientId, isScaleValueOmitted, splitScalePairs;
import '../core/session/session_row.dart';
import '../core/timestamps.dart';
import '../core/session/scale_scoring.dart';
import 'report_data.dart'
    show
        DatedNote,
        ScalesChartSpec,
        SessionReportData,
        buildSessionReportData,
        kSessionIndexHeader,
        kVisitsIndexHeader,
        datedNotes,
        coerceInt,
        kLeftOnTitle,
        sessionTableHeaders,
        trimZeros;

/// One imported file: a visit.
typedef LongitudinalVisit = ({
  String filename,

  /// From the rows themselves, "yyyy-MM-dd", or '' when none parse.
  String date,

  /// The BIDS `run-` entity, or ''.
  String run,

  /// "20260626_01", the desktop's `{date}_{run}` tick label.
  String label,

  /// Baseline (`is_initial == 1`) scale scores: the clinical assessment.
  Map<String, double> clinicalScales,

  /// Recording block IDs, ascending.
  List<int> blocks,

  /// Session scale -> block -> value, over the recording blocks.
  Map<String, Map<int, double>> sessionScales,

  /// The last recording row, i.e. the configuration in force at visit end.
  SessionRow? finalRow,

  /// This visit built as if it were its own session report, which is where the
  /// combined table, the electrode diagrams and the programming summary come
  /// from: every field they need is already computed there.
  SessionReportData session,
});

/// A day with notes and no session: its date and its notes as session-data
/// rows, filled only in Time and Notes.
typedef NoteDay = ({String date, List<List<String>> rows});

/// Everything the longitudinal builders render.
class LongitudinalReportData {
  const LongitudinalReportData({
    required this.patientId,
    required this.generatedOn,
    required this.visits,
    required this.clinicalChart,
    required this.sessionChart,
    required this.visitTable,
    required this.mismatchedPatients,
    this.rankedBlocks = const {},
    this.overallRanks = const {},
    this.notesWithoutVisit = const [],
    this.timeline = const [],
    this.noteFiles = const [],
  });

  /// Notes recorded on a day with no session, oldest first. Notes on a visit
  /// day are interleaved in that visit's session table instead.
  final List<DatedNote> notesWithoutVisit;

  /// Visits and notes-only days in date order, exactly one of the two set in
  /// each entry: the order of the Visits table and of the session data.
  final List<({LongitudinalVisit? visit, NoteDay? noteDay})> timeline;

  /// The uploaded notes files, for the source list.
  final List<String> noteFiles;

  final String patientId;
  final String generatedOn;

  /// Visits in date order, oldest first.
  final List<LongitudinalVisit> visits;

  /// Clinical scales against the visit. No index, no bands; see above.
  final ScalesChartSpec clinicalChart;

  /// Session scales against visit + block.
  final ScalesChartSpec sessionChart;

  /// The per-visit summary: date, programme at visit end, primary scale, delta.
  final List<List<String>> visitTable;

  /// Patient IDs found beyond [patientId]. Non-empty means the import mixed
  /// people, which is a safety issue, not a formatting one.
  final List<String> mismatchedPatients;

  /// Visit filename to block to fill: the highest and second-highest
  /// aggregate index across every visit together, so the whole report marks
  /// two configurations rather than two per visit.
  final Map<String, Map<int, int>> rankedBlocks;

  /// Visit filename to block to its rank across every visit, which is what
  /// the tables print: a per-visit rank beside cross-visit shading would say
  /// two different things about one row.
  final Map<String, Map<int, int>> overallRanks;

  /// [visit]'s session table with the Index cell carrying the overall rank.
  List<List<String>> tableRowsFor(LongitudinalVisit visit) {
    final col = visit.session.tableHeaders.indexOf(kSessionIndexHeader);
    final ranks = overallRanks[visit.filename] ?? const {};
    if (col < 0) return visit.session.tableRows;
    return [
      for (final row in visit.session.tableRows)
        if (ranks[int.tryParse(row.first)] case final rank?
            when row[col].isNotEmpty)
          [...row]..[col] = '${row[col].split('\n').first}\n(rank $rank)'
        else
          row,
    ];
  }

  /// [visit]'s session table headers, the Index naming the cross-visit rank
  /// [tableRowsFor] prints.
  List<String> tableHeadersFor(LongitudinalVisit visit) => [
    for (final h in visit.session.tableHeaders)
      h == kSessionIndexHeader ? kVisitsIndexHeader : h,
  ];

  /// Data-row index of [visit]'s session table to its fill.
  Map<int, int> rowFillsFor(LongitudinalVisit visit) {
    final fills = rankedBlocks[visit.filename] ?? const {};
    return {
      for (final (i, row) in visit.session.tableData.indexed)
        i: ?fills[int.tryParse(row.first)],
    };
  }

  bool get isEmpty => visits.isEmpty;

  /// "Scale targets: ..." the bands and shading were ranked against, or ''
  /// when nothing is ranked. Printed because the Reports screen ranks with
  /// default targets when none were set, and a reader must see which.
  String get rankingTargets => rankedBlocks.isEmpty
      ? ''
      : 'Scale targets: ${visits.first.session.targetsText}';
}

/// The latest visit's programme cell, which the page-1 summary states.
const kSeeSummary = 'As in the summary above';

/// The page-1 summary: the latest visit and the programme last recorded there,
/// one line per side and the group.
({String heading, List<String> lines})? latestVisitSummary(
  LongitudinalReportData data,
) {
  if (data.visits.isEmpty) return null;
  final last = data.visits.last;
  final config = last.session.lastConfig;
  return (
    heading:
        'Latest visit, ${last.date.isEmpty ? 'date unknown' : last.date}: '
        '${last.session.leftOnMarked ? 'left on, as marked by the clinician' : 'last recorded programme'}',
    lines: config.isEmpty
        ? const ['No programme was recorded.']
        : [for (final e in config.entries) '${e.key}: ${e.value}'],
  );
}

/// Printed under the per-visit session tables when any row is shaded.
const kVisitRankingLegend =
    'Shaded rows, marked on their left edge: the highest (darker) and '
    'second-highest aggregate index '
    'across all visits, against the same scale targets.';

/// Column headers for [LongitudinalReportData.visitTable].
const longitudinalTableHeaders = [
  'Visit',
  'Date',
  'Programme at visit end',
  'Blocks',
  'Clinical scales',
];

/// The `run-` entity of a BIDS filename, or ''.
String _runOf(String filename) =>
    RegExp(r'run-([A-Za-z0-9]+)').firstMatch(filename)?.group(1) ?? '';

/// [notes] by the session file of their day. With several sessions that day a
/// note goes to the last one started at or before it, else the first; a note
/// on a day with no session is in none of the lists.
Map<String, List<Annotation>> _notesByFile(
  Map<String, List<SessionRow>> files,
  List<Annotation> notes,
) {
  String startOf(List<SessionRow> rows) =>
      (rows
              .map((r) => r.acqTime)
              .where((a) => recordedDate(a).isNotEmpty)
              .toList()
            ..sort())
          .firstOrNull ??
      '';
  final starts = {for (final e in files.entries) e.key: startOf(e.value)};
  final out = <String, List<Annotation>>{};
  for (final note in notes) {
    final day = recordedDate(note.acqTime);
    final sameDay =
        starts.entries
            .where((e) => day.isNotEmpty && recordedDate(e.value) == day)
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));
    if (sameDay.isEmpty) continue;
    final before = sameDay.where((e) => e.value.compareTo(note.acqTime) <= 0);
    final file = (before.isEmpty ? sameDay.first : before.last).key;
    (out[file] ??= []).add(note);
  }
  return out;
}

/// Build one visit from a file's rows.
LongitudinalVisit _visitOf(
  String filename,
  List<SessionRow> rows,
  List<ScalePref> scalePrefs, {
  List<Annotation> notes = const [],
}) {
  final initial = rows.where((r) => coerceInt(r.isInitial) == 1).toList();
  final recording = rows.where((r) => coerceInt(r.isInitial) != 1).toList();

  // The visit's date is the earliest `acq_time` instant in the file; rows
  // whose instant will not parse are skipped, not sorted as empty strings.
  final dates =
      rows
          .map((r) => recordedDate(r.acqTime))
          .where((d) => d.isNotEmpty)
          .toList()
        ..sort();
  final date = dates.isEmpty ? '' : dates.first;

  double? value(String raw) {
    if (isScaleValueOmitted(raw)) return null;
    final v = double.tryParse(raw.trim());
    return (v == null || !v.isFinite) ? null : v;
  }

  // Clinical scores come from the baseline rows; where a scale appears more
  // than once the LAST wins, so a re-entered score supersedes its predecessor.
  final clinical = <String, double>{};
  for (final row in initial) {
    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      final v = value(pair.value);
      if (pair.name.isEmpty || v == null) continue;
      clinical[pair.name] = v;
    }
  }

  final blocks = <int>[];
  final session = <String, Map<int, double>>{};
  for (final row in recording) {
    final block = coerceInt(row.blockId);
    if (!blocks.contains(block)) blocks.add(block);
    for (final pair in splitScalePairs(row.scaleName, row.scaleValue)) {
      final v = value(pair.value);
      if (pair.name.isEmpty || v == null) continue;
      (session[pair.name] ??= <int, double>{})[block] = v;
    }
  }
  blocks.sort();

  final run = _runOf(filename);
  return (
    filename: filename,
    date: date,
    run: run,
    label: [date.replaceAll('-', ''), if (run.isNotEmpty) run].join('_'),
    clinicalScales: clinical,
    blocks: blocks,
    sessionScales: session,
    finalRow: recording.isEmpty ? null : recording.last,
    session: buildSessionReportData(
      rows: rows,
      scalePrefs: scalePrefs.isEmpty ? null : scalePrefs,
      sourceFile: filename,
      notes: notes,
    ),
  );
}

/// Build the whole report from the imported files. [files] is filename ->
/// rows in import order; visits are sorted by date here so the figures read
/// left to right in time.
LongitudinalReportData buildLongitudinalReportData({
  required Map<String, List<SessionRow>> files,
  DateTime? generatedAt,

  /// Targets for the per-visit ranking, which the desktop asks for before this
  /// report is built. A TSV records no memory of the targets used when its own
  /// report was made, so they have to be supplied again here.
  List<ScalePref> scalePrefs = const [],

  /// Notes from uploaded notes files. Each goes to the visit of its own day,
  /// so it is never shown inside a visit it did not happen in.
  List<Annotation> notes = const [],

  /// The notes files' names, so their patient is named and checked too.
  List<String> noteFilenames = const [],

  /// Declared range per clinical scale, from the user's clinical presets. Only
  /// the clinical figure's y axis uses them; they are never printed.
  Map<String, (double, double)> clinicalRanges = const {},
}) {
  final dt = generatedAt ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final generatedOn = '${dt.year}-${two(dt.month)}-${two(dt.day)}';

  final byFile = _notesByFile(files, notes);
  final visits = [
    for (final e in files.entries)
      _visitOf(e.key, e.value, scalePrefs, notes: byFile[e.key] ?? const []),
  ]..sort((a, b) => a.date.compareTo(b.date));
  final placed = {for (final list in byFile.values) ...list};

  // Patient identity. Mixing two people into one longitudinal report is a
  // safety problem, so it is surfaced rather than silently merged.
  final ids = [
    ...files.keys,
    ...noteFilenames,
  ].map(extractPatientId).where((id) => id.isNotEmpty).toSet().toList()..sort();
  final patientId = ids.isEmpty ? 'unknown' : ids.first;

  // Figure 1: clinical scales, one point per visit.
  final clinicalSeries = <String, Map<int, double>>{};
  final clinicalLabels = <int, String>{};
  final dates = [for (final v in visits) v.date];
  // The date alone; the run only when two visits share a day.
  String visitLabel(LongitudinalVisit visit) =>
      dates.where((d) => d == visit.date).length > 1
      ? '${visit.date} run ${visit.run}'
      : visit.date;
  for (final (i, visit) in visits.indexed) {
    clinicalLabels[i] = visitLabel(visit);
    visit.clinicalScales.forEach((name, v) {
      (clinicalSeries[name] ??= <int, double>{})[i] = v;
    });
  }

  // Figure 2: session scales, one point per (visit, block).
  //
  // The bands mark the two best configurations across all visits. Every
  // visit's index is normalised into the same declared scale ranges and
  // oriented by the same targets, so the values are on one scale.
  final sessionSeries = <String, Map<int, double>>{};
  final sessionLabels = <int, String>{};
  final sessionGroups = <({int from, int to, String label})>[];
  final globalIndex = <int, double>{};
  final visitBlockAt = <int, (String, int)>{};
  var x = 0;
  for (final visit in visits) {
    if (visit.blocks.isNotEmpty) {
      // The block number on each tick and the visit's date once under its
      // blocks, so nothing has to be rotated to fit.
      sessionGroups.add((
        from: x,
        to: x + visit.blocks.length - 1,
        label: visitLabel(visit),
      ));
    }
    for (final block in visit.blocks) {
      sessionLabels[x] = '$block';
      if (visit.session.chart.aggregateIndex[block] case final v?) {
        globalIndex[x] = v;
        visitBlockAt[x] = (visit.filename, block);
      }
      visit.sessionScales.forEach((name, byBlock) {
        final v = byBlock[block];
        if (v != null) (sessionSeries[name] ??= <int, double>{})[x] = v;
      });
      x++;
    }
  }

  final globalRanks = rankBlocks(globalIndex);
  final bestXs = blocksAtRank(globalRanks, 1);
  final secondXs = blocksAtRank(globalRanks, 2);
  final rankedBlocks = <String, Map<int, int>>{};
  final overallRanks = <String, Map<int, int>>{};
  globalRanks.forEach((at, rank) {
    final (file, block) = visitBlockAt[at]!;
    (overallRanks[file] ??= {})[block] = rank;
  });
  for (final (xs, fill) in [(bestXs, kBestFill), (secondXs, kSecondFill)]) {
    for (final at in xs) {
      final (file, block) = visitBlockAt[at]!;
      (rankedBlocks[file] ??= {})[block] = fill;
    }
  }

  // Declared bounds when targets were given, so a scale sits on the same axis
  // at every visit and a drop between visits is a drop rather than a rescale.
  final declared = declaredScaleRange(parseScaleTargets(scalePrefs));

  ScalesChartSpec spec(
    Map<String, Map<int, double>> series,
    Map<int, String> labels,
    String title,
    String xLabel, {
    List<int> best = const [],
    List<int> second = const [],
    bool declaredBounds = false,
    bool zeroBased = false,
    List<({int from, int to, String label})> groups = const [],
    String rankScope = '',
    Map<String, (double, double)> ranges = const {},
  }) {
    final xs = <int>{for (final m in series.values) ...m.keys}.toList()..sort();
    var lo = double.infinity;
    var hi = double.negativeInfinity;
    for (final m in series.values) {
      for (final v in m.values) {
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    final dataLo = lo;
    final dataHi = hi;
    if (!lo.isFinite) {
      lo = 0;
      hi = 1;
    } else if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    // A clinical total is a magnitude: an axis starting at 13 puts the lowest
    // score on the axis line and exaggerates every change.
    if (zeroBased && lo > 0) lo = 0;
    // The targets describe the session scales only; a clinical total such as
    // Y-BOCS 28 would fall off a 0-10 axis.
    if (declaredBounds && declared != null) {
      lo = math.min(dataLo, declared.$1);
      hi = math.max(dataHi, declared.$2);
    }
    // A plotted scale with a declared range widens the axis to it, so a score
    // reads against its scale rather than against the other values drawn.
    for (final name in series.keys) {
      if (ranges[name] case (final min, final max)) {
        if (min < lo) lo = min;
        if (max > hi) hi = max;
      }
    }
    return ScalesChartSpec(
      series: series,
      amplitude: const {},
      xs: xs,
      yMin: lo,
      yMax: hi,
      // No index series on either figure, as the desktop passes
      // `show_general_index=False`; the bands carry the ranking, two
      // configurations across all visits.
      aggregateIndex: const {},
      bestXs: best,
      secondXs: second,
      title: title,
      xLabel: xLabel,
      yLabel: 'Scale value',
      xTickLabels: labels,
      xGroups: groups,
      rankScope: rankScope,
    );
  }

  // A day with notes and no session, in the session-data columns so its table
  // reads like the visits' tables around it.
  final unplaced = datedNotes(notes.where((n) => !placed.contains(n)));
  final headers = visits.isEmpty
      ? sessionTableHeaders
      : visits.first.session.tableHeaders;
  final noteDays = <NoteDay>[];
  for (final n in unplaced) {
    if (noteDays.isEmpty || noteDays.last.date != n.date) {
      noteDays.add((date: n.date, rows: []));
    }
    noteDays.last.rows.add(
      List<String>.filled(headers.length, '')
        ..[headers.indexOf('Time')] = n.time
        ..[headers.length - 1] = n.text,
    );
  }

  // Visits and notes-only days merged by date. Both lists are already sorted;
  // on a tie the visit comes first.
  final timeline = <({LongitudinalVisit? visit, NoteDay? noteDay})>[];
  var vi = 0;
  var ni = 0;
  while (vi < visits.length || ni < noteDays.length) {
    final takeVisit =
        ni == noteDays.length ||
        (vi < visits.length &&
            visits[vi].date.compareTo(noteDays[ni].date) <= 0);
    timeline.add(
      takeVisit
          ? (visit: visits[vi++], noteDay: null)
          : (visit: null, noteDay: noteDays[ni++]),
    );
  }

  // The per-visit table: every clinical scale recorded at the visit, one per
  // line. The latest visit's programme is in the summary panel above it. A
  // notes-only day is numbered with the visits and fills only its date.
  final table = <List<String>>[];
  for (final (i, entry) in timeline.indexed) {
    final visit = entry.visit;
    if (visit == null) {
      table.add(['${i + 1}', entry.noteDay!.date, '', '', '']);
      continue;
    }
    final latest = visit.filename == visits.last.filename && visits.length > 1;
    final scores = visit.clinicalScales;
    table.add([
      '${i + 1}',
      visit.date.isEmpty ? 'unknown' : visit.date,
      latest ? kSeeSummary : _programmeText(visit.session),
      '${visit.blocks.length}',
      scores.isEmpty
          ? '-'
          : [
              for (final e in scores.entries) '${e.key}: ${trimZeros(e.value)}',
            ].join('\n'),
    ]);
  }

  return LongitudinalReportData(
    patientId: patientId,
    generatedOn: generatedOn,
    visits: visits,
    clinicalChart: spec(
      clinicalSeries,
      clinicalLabels,
      // No title in the figure: the section heading above it already says it.
      '',
      'Visit (date)',
      zeroBased: true,
      ranges: clinicalRanges,
    ),
    sessionChart: spec(
      sessionSeries,
      sessionLabels,
      '',
      'Block, by visit',
      best: bestXs,
      second: secondXs,
      declaredBounds: true,
      groups: sessionGroups,
      rankScope: 'across all visits',
    ),
    visitTable: table,
    notesWithoutVisit: unplaced,
    timeline: timeline,
    noteFiles: noteFilenames,
    mismatchedPatients: ids.length <= 1 ? const [] : ids.skip(1).toList(),
    rankedBlocks: rankedBlocks,
    overallRanks: overallRanks,
  );
}

/// The configuration in force at the end of a visit, one line per side and
/// the group: the same lines as the session report's page-1 summary, contacts
/// and current share included, under "Left on" when the clinician marked it.
String _programmeText(SessionReportData visit) => visit.lastConfig.isEmpty
    ? '-'
    : [
        if (visit.leftOnMarked) '$kLeftOnTitle:',
        for (final e in visit.lastConfig.entries) '${e.key}: ${e.value}',
      ].join('\n');
