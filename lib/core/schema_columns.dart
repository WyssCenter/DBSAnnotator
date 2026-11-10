/// Canonical TSV column orders. The contract lists and `schema/tsv_schema.json`
/// are one contract and test/schema_columns_test.dart fails if they disagree.
library;

import 'session/tsv_kind.dart';
import 'timestamps.dart';
import 'tsv.dart';

const List<String> annotationColumns = <String>['acq_time', 'notes'];

/// The stimulation cells of one configuration, left lead then right.
const List<String> stimColumns = <String>[
  'left_stim_freq',
  'left_anode',
  'left_cathode',
  'left_amplitude',
  'left_pulse_width',
  'right_stim_freq',
  'right_anode',
  'right_cathode',
  'right_amplitude',
  'right_pulse_width',
];

/// The fixed columns of a session's `beh/` file; `scale_<name>` columns go
/// before `notes`.
const List<String> sessionColumns = <String>[
  'acq_time',
  'append_id',
  'is_final',
  'is_starred',
  'program_id',
  ...stimColumns,
  'notes',
];

/// The fixed columns of `sub-<label>_sessions.tsv`, one row per visit;
/// `scale_<name>` columns go before `notes`.
const List<String> visitColumns = <String>[
  'session_id',
  'acq_time',
  'target',
  'left_electrode_model',
  'right_electrode_model',
  'left_ipg_model',
  'right_ipg_model',
  'medications',
  'program_id',
  ...stimColumns,
  'notes',
];

/// The columns this app writes to `participants.tsv`.
const List<String> participantColumns = <String>[
  'participant_id',
  'dbs_indication',
];

/// The long form, one row per block and scale: the app's own working copy, and
/// the session files of versions before the BIDS tables.
const List<String> workingColumns = <String>[
  'acq_time',
  'block_id',
  'append_id',
  'is_initial',
  'is_final',
  'is_starred',
  'scale_name',
  'scale_value',
  'dbs_indication',
  'target',
  'left_electrode_model',
  'right_electrode_model',
  'left_ipg_model',
  'right_ipg_model',
  'program_id',
  ...stimColumns,
  'medications',
  'notes',
];

/// The prefix of every scale column.
const String scalePrefix = 'scale_';

/// `scale_` plus [name] in lower case, each run of other characters as `_`.
String scaleColumnSlug(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return '$scalePrefix${slug.isEmpty ? 'unnamed' : slug}';
}

/// Superseded spellings, newest first, keyed by their current name; readers
/// consult them so an older file opens without conversion, nothing writes them.
const Map<String, List<String>> legacyColumnAliases = <String, List<String>>{
  'block_id': <String>['block_ID'],
  'append_id': <String>['session_id', 'session_ID'],
  'program_id': <String>['program_ID'],
  'dbs_indication': <String>['pathology'],
  'left_electrode_model': <String>['electrode_model'],
  'right_electrode_model': <String>['electrode_model'],
};

/// Read [column] from a TSV record, falling back to its superseded spellings.
String readColumn(Map<String, String> record, String column) {
  final current = record[column];
  if (current != null) return current;
  for (final alias in legacyColumnAliases[column] ?? const <String>[]) {
    final value = record[alias];
    if (value != null) return value;
  }
  return '';
}

/// The columns an old file carries instead of `acq_time`; readers backfill it
/// from them.
const Map<String, List<String>> legacyTimeColumns = <String, List<String>>{
  'acq_time': <String>['date', 'time', 'timezone'],
};

/// Stands in for a cell that has no header name in [unkeptColumns].
const String unnamedColumn = 'unnamed column';

/// The header columns of [content] that the reader of a [kind] file does not
/// keep, so that writing the file back would drop them. A superseded spelling
/// counts as kept only when the current column it stands in for is absent and
/// it is the one [readColumn] reads. The legacy date, time and timezone count
/// as kept only when every row's values survive [backfillAcqTime]. A repeated
/// name, a value under an empty header name and a value beyond the header are
/// reported too.
List<String> unkeptColumns(String content, TsvKind kind) {
  final text = content.startsWith('\uFEFF') ? content.substring(1) : content;
  final rows = parseTsv(text);
  if (rows.isEmpty) return const [];
  final header = [for (final c in rows.first) c.trim()];
  final current = kind == TsvKind.programming
      ? [...workingColumns, ...sessionColumns]
      : annotationColumns;
  final kept = {...current};
  for (final entry in legacyColumnAliases.entries) {
    if (!current.contains(entry.key) || header.contains(entry.key)) continue;
    final read = entry.value.where(header.contains).firstOrNull;
    if (read != null) kept.add(read);
  }
  for (final entry in legacyTimeColumns.entries) {
    if (!current.contains(entry.key) || header.contains(entry.key)) continue;
    kept.addAll(entry.value);
    kept.removeAll(_legacyTimeColumnsLost(header, rows.skip(1)));
  }
  final unkept = <String>[];
  final seen = <String>{};
  for (final name in header) {
    if (name.isEmpty) continue;
    final repeated = !seen.add(name);
    final scale = kind == TsvKind.programming && name.startsWith(scalePrefix);
    if ((repeated || !(kept.contains(name) || scale)) &&
        !unkept.contains(name)) {
      unkept.add(name);
    }
  }
  for (final row in rows.skip(1)) {
    for (var i = 0; i < row.length; i++) {
      final unnamed = i >= header.length || header[i].isEmpty;
      if (unnamed && _readValue(row[i]).isNotEmpty) {
        if (!unkept.contains(unnamedColumn)) unkept.add(unnamedColumn);
        break;
      }
    }
  }
  return unkept;
}

/// A cell as [parseTsvRecords] reads it: trimmed, with [naCell] as empty.
String _readValue(String cell) {
  final value = cell.trim();
  return value == naCell ? '' : value;
}

/// The legacy date, time and timezone columns holding a value in some row that
/// [backfillAcqTime] does not carry into `acq_time`.
Set<String> _legacyTimeColumnsLost(
  List<String> header,
  Iterable<List<String>> rows,
) {
  String cell(List<String> row, String name) {
    final i = header.indexOf(name);
    return i < 0 || i >= row.length ? '' : _readValue(row[i]);
  }

  final lost = <String>{};
  for (final row in rows) {
    final date = cell(row, 'date');
    final time = cell(row, 'time');
    final timezone = cell(row, 'timezone');
    final acqTime = backfillAcqTime(date: date, time: time, timezone: timezone);
    if (date.isNotEmpty && acqTime.isEmpty) lost.add('date');
    if (time.isNotEmpty && acqTime.isEmpty) lost.add('time');
    if (timezone.isNotEmpty &&
        (acqTime.isEmpty || offsetFromTimezoneCell(timezone).isEmpty)) {
      lost.add('timezone');
    }
  }
  return lost;
}

/// `0` or `1` for the `is_initial` cell, never `0.0`: `astype(bool)` reads the
/// string `"0.0"` as True, moving a baseline row into the tested set.
String initialCell(bool isInitial) => isInitial ? '1' : '0';

/// Whether an `is_initial` cell means "baseline", tolerating `1`, `1.0`, ` 1 `.
bool isInitialValue(String cell) {
  final v = double.tryParse(cell.trim());
  return v != null && v.round() == 1;
}
