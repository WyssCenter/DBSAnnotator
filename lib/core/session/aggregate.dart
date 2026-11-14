/// Combine several sessions into one table, for pooled analysis: one row per
/// configuration and one per visit for its initial assessment, with the union
/// of every file's `scale_<name>` columns.
///
/// `participant_id`, `session_id`, `run_id` and `source_file` lead each row;
/// `participant_id` keeps the BIDS spelling so the table joins onto
/// `participants.tsv` untransformed.
/// `source_file` is a key column, not a convenience: `run` defaults to `01`
/// and does not auto-increment, so two visits on one day can share all three
/// entities. The table belongs under `derivatives/`, never the raw tree.
library;

import '../bids.dart';
import '../schema_columns.dart';
import '../tsv.dart';
import 'session_row.dart';

typedef AggregateSource = ({String filename, List<SessionRow> rows});

typedef AggregateSkip = ({String filename, String reason});

typedef AggregateResult = ({
  /// The TSV document, or '' when nothing was includable.
  String tsv,
  List<AggregateSkip> skipped,
  int rowCount,

  /// Distinct `participant_id` values, sorted.
  List<String> subjects,
  int fileCount,

  /// Each `scale_<name>` column of the table, to its scale's name.
  Map<String, String> scaleNames,
});

/// The columns the combined table adds to the session tables, in order.
const List<String> aggregateKeyColumns = <String>[
  'participant_id',
  'session_id',
  'run_id',
  'source_file',
  'is_initial',
];

/// The visit and participant cells repeated on every row of a session.
const List<String> _visitCells = <String>[
  'dbs_indication',
  'target',
  'left_electrode_model',
  'right_electrode_model',
  'left_ipg_model',
  'left_ipg_position',
  'right_ipg_model',
  'right_ipg_position',
  'medications',
];

/// The full header, with [scales] columns before `notes`.
List<String> aggregateColumns([Iterable<String> scales = const []]) => <String>[
  ...aggregateKeyColumns,
  ..._visitCells,
  ...sessionColumns.take(sessionColumns.length - 1),
  ...scales,
  sessionColumns.last,
];

/// What [out] holds, in words: rows, files and subjects.
String describeAggregate(AggregateResult out) {
  String n(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';
  return '${n(out.rowCount, 'row')} from ${n(out.fileCount, 'file')}, '
      '${n(out.subjects.length, 'subject')}';
}

/// Fold [sources] into one table.
///
/// A file is skipped, and named in [AggregateResult.skipped], when its name
/// carries no `sub-` or `ses-` entity (guessing would put a wrong subject
/// label on clinical data) or when it repeats a filename already folded in
/// (duplicate rows double every count derived from the table).
AggregateResult buildAggregate(List<AggregateSource> sources) {
  final skipped = <AggregateSkip>[];
  final seen = <String>{};
  final subjects = <String>{};
  // Index-tagged because Dart's List.sort is not stable, and rows must keep
  // their written order for the output to be reproducible.
  final keyed =
      <({List<String> key, int seq, int block, Map<String, String> record})>[];
  var fileCount = 0;
  final scaleNames = <String, String>{};
  final columnOf = <String, String>{};
  String column(String name) => columnOf.putIfAbsent(name, () {
    final base = scaleColumnSlug(name);
    var candidate = base;
    for (var n = 2; scaleNames.containsKey(candidate); n++) {
      candidate = '${base}_$n';
    }
    scaleNames[candidate] = name;
    return candidate;
  });

  for (final source in sources) {
    final name = BidsName.parse(source.filename);
    if (name == null || BidsName.label(name.session).isEmpty) {
      skipped.add((
        filename: source.filename,
        reason: 'no sub- or ses- entity in the filename',
      ));
      continue;
    }
    if (!seen.add(source.filename)) {
      skipped.add((
        filename: source.filename,
        reason: 'a file with this name is already included',
      ));
      continue;
    }

    // When the visit happened, not what it was labelled: `ses-preop` and
    // `ses-3mo` sort alphabetically the wrong way round. UTC, so the string
    // order is the time order.
    DateTime? first;
    for (final row in source.rows) {
      final at = row.timestamp;
      if (at != null && (first == null || at.isBefore(first))) first = at;
    }
    final started = first?.toUtc().toIso8601String() ?? '';
    final participant = 'sub-${BidsName.label(name.subject)}';
    final session = 'ses-${BidsName.label(name.session)}';
    final run = BidsName.index(name.run);
    subjects.add(participant);
    fileCount++;

    final fixed = {
      for (final c in _visitCells)
        c: sessionValueIn(source.rows, (r) => r.toMap()[c] ?? ''),
    };
    final blocks = <String, List<SessionRow>>{};
    for (final row in source.rows) {
      (blocks[row.blockId] ??= []).add(row);
    }
    for (final block in blocks.values) {
      final first = block.first.toMap();
      keyed.add((
        key: [participant, started, session, run],
        seq: keyed.length,
        block: _asInt(block.first.blockId),
        record: <String, String>{
          'participant_id': participant,
          'session_id': session,
          'run_id': run,
          'source_file': source.filename,
          'is_initial': initialCell(isInitialValue(block.first.isInitial)),
          ...fixed,
          for (final c in sessionColumns) c: first[c] ?? '',
          for (final r in block)
            if (r.scaleName.trim().isNotEmpty)
              column(r.scaleName.trim()): r.scaleValue,
        },
      ));
    }
  }

  // Patient, then the visit's first recorded time, so the table reads from
  // the earliest visit to the most recent; and the same inputs in any order
  // give byte-identical output.
  keyed.sort((a, b) {
    for (var i = 0; i < a.key.length; i++) {
      final c = a.key[i].compareTo(b.key[i]);
      if (c != 0) return c;
    }
    final byFile = a.record['source_file']!.compareTo(b.record['source_file']!);
    if (byFile != 0) return byFile;
    final byBlock = a.block.compareTo(b.block);
    if (byBlock != 0) return byBlock;
    return a.seq.compareTo(b.seq);
  });

  final records = [for (final k in keyed) k.record];
  return (
    tsv: records.isEmpty
        ? ''
        : writeTsvRecords(aggregateColumns(scaleNames.keys), records),
    skipped: skipped,
    rowCount: records.length,
    subjects: subjects.toList()..sort(),
    fileCount: fileCount,
    scaleNames: scaleNames,
  );
}

/// `block_id` as an int for ordering; unparsable cells sort first. Tolerant
/// like [nextBlockId], because older files write block indices as `3` or `3.0`.
int _asInt(String raw) {
  final v = double.tryParse(raw.trim());
  return (v == null || !v.isFinite) ? -1 : v.truncate();
}
