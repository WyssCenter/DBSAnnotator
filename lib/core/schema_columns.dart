/// Canonical TSV column orders. These lists and `schema/tsv_schema.json` are
/// one contract and test/schema_columns_test.dart fails if they disagree.
library;

const List<String> annotationColumns = <String>['acq_time', 'notes'];

const List<String> sessionColumns = <String>[
  'acq_time',
  'block_id',
  'append_id',
  'is_initial',
  'is_final',
  'is_starred',
  'scale_name',
  'scale_value',
  'pathology',
  'target',
  'left_electrode_model',
  'right_electrode_model',
  'ipg_model',
  'program_id',
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
  'medications',
  'notes',
];

/// Superseded spellings, newest first, keyed by their current name; readers
/// consult them so an older file opens without conversion, nothing writes them.
const Map<String, List<String>> legacyColumnAliases = <String, List<String>>{
  'block_id': <String>['block_ID'],
  'append_id': <String>['session_id', 'session_ID'],
  'program_id': <String>['program_ID'],
  // One model for both leads, before each side had its own.
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

/// `0` or `1` for the `is_initial` cell, never `0.0`: `astype(bool)` reads the
/// string `"0.0"` as True, moving a baseline row into the tested set.
String initialCell(bool isInitial) => isInitial ? '1' : '0';

/// Whether an `is_initial` cell means "baseline", tolerating `1`, `1.0`, ` 1 `.
bool isInitialValue(String cell) {
  final v = double.tryParse(cell.trim());
  return v != null && v.round() == 1;
}
