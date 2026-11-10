/// The `_beh.json` sidecar that documents a TSV's columns.
///
/// Of a programming-session file's columns only `notes` resembles anything
/// BIDS defines, and the spec's answer is the sidecar: "any additional columns
/// in a TSV file SHOULD be documented in an accompanying JSON sidecar file".
/// Descriptions come from `schema/tsv_schema.json`, which also feeds the docs.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../app_info.dart' show appName;

/// Loads the bundled TSV contract; tests read `schema/` via `dart:io`.
Future<Map<String, dynamic>> loadTsvContract() async {
  final raw = await rootBundle.loadString('schema/tsv_schema.json');
  return jsonDecode(raw) as Map<String, dynamic>;
}

Map<String, String> _entry(Map<String, dynamic> column) {
  final description = (column['description'] as String? ?? '')
      // Strip the reStructuredText inline literals the docs render.
      .replaceAll('``', '');
  final out = <String, String>{
    'LongName': _longName(column['name'] as String),
    'Description': description,
  };
  final units = column['units'] as String?;
  if (units != null) out['Units'] = units;
  return out;
}

/// `left_stim_freq` -> `Left stim freq`, so `LongName` needs no second table.
String _longName(String column) {
  final words = column.split('_');
  if (words.isEmpty) return column;
  final first = words.first;
  return [
    first.isEmpty ? first : first[0].toUpperCase() + first.substring(1),
    ...words.skip(1),
  ].join(' ');
}

/// The `task-` label each contract section describes, and what that task is.
///
/// BIDS asks a task file's sidecar for both. The label is already in the
/// filename, but a sidecar that repeats it still describes the file when it is
/// read on its own, and the description is the only place a reuser learns what
/// the rows represent. The combined table declares neither: it spans sessions
/// and carries no `task-` entity.
const _tasks = <String, ({String name, String description})>{
  'session_tsv': (
    name: 'programming',
    description:
        'Deep brain stimulation programming. Stimulation configurations are '
        'set, tried and rated during a clinical visit, one row per '
        'configuration tried.',
  ),
  'annotation_tsv': (
    name: 'notes',
    description:
        'Timestamped free-text clinical notes taken during a visit, one row '
        'per note.',
  ),
};

/// Build the sidecar for one [kind] of TSV: `session_tsv` or `annotation_tsv`.
///
/// [task] is the `task-` label of the file when the user renamed it; BIDS
/// derives that label from `TaskName`, so the two must match.
///
/// [scaleColumns] maps each `scale_<name>` column the file holds to its
/// scale's name, documented from the section's `scale_columns` entry.
Map<String, dynamic> buildSidecar(
  Map<String, dynamic> contract,
  String kind, {
  required String appVersion,
  String? task,
  Map<String, String> scaleColumns = const {},
}) {
  final section = contract[kind] as Map<String, dynamic>;
  final columns = (section['columns'] as List).cast<Map<String, dynamic>>();
  final scales = section['scale_columns'] as Map<String, dynamic>?;
  final bids = contract['bids'] as Map<String, dynamic>? ?? const {};
  return <String, dynamic>{
    if (_tasks[kind] != null)
      'TaskName': (task == null || task.isEmpty) ? _tasks[kind]!.name : task,
    if (_tasks[kind] != null) 'TaskDescription': _tasks[kind]!.description,
    'GeneratedBy': [
      {'Name': appName, 'Version': appVersion},
    ],
    'SchemaVersion': contract['schema_version'],
    if (bids['na'] != null) 'MissingValueCode': bids['na'],
    for (final column in columns) column['name'] as String: _entry(column),
    if (scales != null)
      for (final e in scaleColumns.entries)
        e.key: {
          'LongName': e.value,
          'Description': (scales['description'] as String).replaceAll('``', ''),
        },
  };
}

/// The scale names a sidecar documents, by column.
Map<String, String> scaleNamesIn(Map<String, dynamic> sidecar) => {
  for (final e in sidecar.entries)
    if (e.key.startsWith('scale_') && e.value is Map)
      e.key: '${(e.value as Map)['LongName'] ?? e.key.substring(6)}',
};

/// The sidecar for the combined table, pretty-printed, in header key order.
///
/// Composed from the contract's sections, since `aggregate_tsv` declares only
/// its identity columns; the others come from the participant, visit and
/// session tables, with [scaleColumns] for the table's scales.
/// [computedAcqTime] notes on `acq_time` that a row from a legacy file had its
/// timestamp derived rather than recorded.
String aggregateSidecarJson(
  Map<String, dynamic> contract, {
  required String appVersion,
  bool computedAcqTime = true,
  Map<String, String> scaleColumns = const {},
}) {
  final keys = buildSidecar(contract, 'aggregate_tsv', appVersion: appVersion);
  final person = buildSidecar(
    contract,
    'participants_tsv',
    appVersion: appVersion,
  );
  final visit = buildSidecar(contract, 'sessions_tsv', appVersion: appVersion);
  final session = buildSidecar(
    contract,
    'session_tsv',
    appVersion: appVersion,
    scaleColumns: scaleColumns,
  );
  // Document-level fields first, then the two column sets in header order.
  const documentLevel = {
    'TaskName',
    'TaskDescription',
    'GeneratedBy',
    'SchemaVersion',
    'MissingValueCode',
  };
  final merged = <String, dynamic>{
    for (final field in documentLevel)
      if (keys.containsKey(field)) field: keys[field],
    for (final entry in keys.entries)
      if (!documentLevel.contains(entry.key)) entry.key: entry.value,
    for (final entry in [...person.entries, ...visit.entries])
      if (!documentLevel.contains(entry.key) && !keys.containsKey(entry.key))
        entry.key: entry.value,
    for (final entry in session.entries)
      if (!documentLevel.contains(entry.key)) entry.key: entry.value,
  };
  if (computedAcqTime && merged['acq_time'] is Map) {
    final acq = Map<String, dynamic>.from(merged['acq_time'] as Map);
    acq['Description'] =
        '${acq['Description']} In this combined table the value may be '
        'COMPUTED rather than recorded: a row from a file written before '
        'v0.5.0 had no acq_time column, and it was composed from that file\'s '
        'date, time and timezone cells when the file was read.';
    merged['acq_time'] = acq;
  }
  return _encode(merged);
}

String _encode(Object? value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

/// The columns [kind] declares, in order, as the contract states them.
List<String> contractColumns(Map<String, dynamic> contract, String kind) =>
    ((contract[kind] as Map<String, dynamic>)['columns'] as List)
        .cast<Map<String, dynamic>>()
        .map((c) => c['name'] as String)
        .toList();
