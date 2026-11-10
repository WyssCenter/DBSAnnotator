/// Combine several session TSVs into one long table, for pooled analysis.
///
/// `participant_id`, `session_id`, `run_id` and `source_file` are prepended to
/// the session columns, which carry through unchanged; `participant_id` keeps
/// the BIDS spelling so the table joins onto `participants.tsv` untransformed.
/// `source_file` is a key column, not a convenience: `run` defaults to `01`
/// and does not auto-increment, so two visits on one day can share all three
/// entities. The table belongs under `derivatives/`, never the raw tree.
library;

import '../bids.dart';
import '../schema_columns.dart';
import '../tsv.dart';
import 'session_file.dart';
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
});

/// The identity columns prepended to every row, in order.
const List<String> aggregateKeyColumns = <String>[
  'participant_id',
  'session_id',
  'run_id',
  'source_file',
];

/// The full header: the four keys, then the session columns unchanged.
List<String> aggregateColumns() => <String>[
  ...aggregateKeyColumns,
  ...sessionColumns,
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
  // Index-tagged because Dart's List.sort is not stable, and rows within a
  // block must keep their written order for the output to be reproducible.
  final keyed = <({List<String> key, int seq, Map<String, String> record})>[];
  var fileCount = 0;

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

    for (final row in source.rows) {
      keyed.add((
        key: [participant, started, session, run],
        seq: keyed.length,
        record: <String, String>{
          'participant_id': participant,
          'session_id': session,
          'run_id': run,
          'source_file': source.filename,
          ...row.toMap(),
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
    final byBlock = _asInt(a.record['block_id'] ?? '')
        .compareTo(_asInt(b.record['block_id'] ?? ''));
    if (byBlock != 0) return byBlock;
    return a.seq.compareTo(b.seq);
  });

  final records = [for (final k in keyed) k.record];
  return (
    tsv: records.isEmpty ? '' : writeTsvRecords(aggregateColumns(), records),
    skipped: skipped,
    rowCount: records.length,
    subjects: subjects.toList()..sort(),
    fileCount: fileCount,
  );
}

/// `block_id` as an int for ordering; unparsable cells sort first. Tolerant
/// like [nextBlockId], because older files write block indices as `3` or `3.0`.
int _asInt(String raw) {
  final v = double.tryParse(raw.trim());
  return (v == null || !v.isFinite) ? -1 : v.truncate();
}
