/// One programming session as the BIDS tables it is stored in: its `beh/`
/// file (one row per configuration), its row in `scans.tsv` (the run's initial
/// assessment), its visit's row in `sessions.tsv` (target, leads, IPGs) and its
/// row in `participants.tsv`.
library;

import '../schema_columns.dart';
import '../tsv.dart';
import 'session_file.dart';
import 'session_row.dart';

/// The tables of one session, with each scale column's original name.
typedef SessionTables = ({
  List<String> behColumns,
  List<Map<String, String>> behRows,
  Map<String, String> visit,
  Map<String, String> initial,
  List<String> initialScales,
  Map<String, String> participant,
  Map<String, String> scaleNames,
});

/// Split long-form [rows] into the BIDS tables. [sessionId] and
/// [participantId] are the `ses-` and `sub-` labels with their prefixes.
SessionTables splitSession(
  List<SessionRow> rows, {
  required String sessionId,
  required String participantId,
}) {
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

  final blocks = <String, List<SessionRow>>{};
  for (final row in rows) {
    (blocks[row.blockId] ??= []).add(row);
  }
  final initialId = [
    for (final e in blocks.entries)
      if (isInitialValue(e.value.first.isInitial)) e.key,
  ].firstOrNull;

  Map<String, String> scalesOf(List<SessionRow> block) => {
    for (final r in block)
      if (r.scaleName.trim().isNotEmpty)
        column(r.scaleName.trim()): r.scaleValue,
  };
  Map<String, String> stimOf(SessionRow r) {
    final m = r.toMap();
    return {for (final c in stimColumns) c: m[c] ?? ''};
  }

  final initial = initialId == null ? null : blocks[initialId]!;
  final initialScales = initial == null
      ? <String, String>{}
      : scalesOf(initial);
  final behScaleCols = <String>[];
  final behRows = <Map<String, String>>[];
  for (final e in blocks.entries) {
    if (e.key == initialId) continue;
    final first = e.value.first;
    final scales = scalesOf(e.value);
    for (final c in scales.keys) {
      if (!behScaleCols.contains(c)) behScaleCols.add(c);
    }
    behRows.add({
      'acq_time': first.acqTime,
      'is_final': first.isFinal,
      'is_starred': first.isStarred,
      'program_id': first.programId,
      ...stimOf(first),
      'notes': first.notes,
      ...scales,
    });
  }

  String fixed(String Function(SessionRow) field) =>
      sessionValueIn(rows, field);
  final i0 = initial?.first;
  final visit = <String, String>{
    'session_id': sessionId,
    'acq_time': i0?.acqTime ?? rows.firstOrNull?.acqTime ?? '',
    'target': fixed((r) => r.target),
    'left_electrode_model': fixed((r) => r.leftElectrodeModel),
    'right_electrode_model': fixed((r) => r.rightElectrodeModel),
    'left_ipg_model': fixed((r) => r.leftIpgModel),
    'left_ipg_position': fixed((r) => r.leftIpgPosition),
    'right_ipg_model': fixed((r) => r.rightIpgModel),
    'right_ipg_position': fixed((r) => r.rightIpgPosition),
  };
  final initialRow = <String, String>{
    'medications': i0?.medications ?? fixed((r) => r.medications),
    'program_id': i0?.programId ?? '',
    if (i0 != null) ...stimOf(i0),
    'notes': i0?.notes ?? '',
    ...initialScales,
  };

  List<String> withScales(List<String> fixedColumns, Iterable<String> scales) =>
      [
        ...fixedColumns.take(fixedColumns.length - 1),
        ...scales,
        fixedColumns.last,
      ];

  return (
    behColumns: withScales(sessionColumns, behScaleCols),
    behRows: behRows,
    visit: visit,
    initial: initialRow,
    initialScales: initialScales.keys.toList(),
    participant: {
      'participant_id': participantId,
      'dbs_indication': fixed((r) => r.pathology),
    },
    scaleNames: scaleNames,
  );
}

/// The `beh/` file of [tables] as a TSV document.
String behTsv(SessionTables tables) =>
    writeTsvRecords(tables.behColumns, tables.behRows);

/// Join the BIDS tables of one session back into long-form rows: the run's
/// initial assessment as block 0 when it holds anything, then one block per
/// `beh/` row. [initial] is the run's `scans.tsv` row; a file written before
/// runs had their own row keeps its initial assessment in [visit] instead.
/// [scaleNames] maps a scale column to its name, from the sidecars; a column
/// it does not list is named after its slug.
List<SessionRow> joinSession({
  required List<Map<String, String>> behRows,
  Map<String, String> visit = const {},
  Map<String, String> initial = const {},
  Map<String, String> participant = const {},
  Map<String, String> scaleNames = const {},
}) {
  String nameOf(String column) =>
      scaleNames[column] ?? column.substring(scalePrefix.length);
  final fixed = <String, String>{
    'dbs_indication': readColumn(participant, 'dbs_indication'),
    for (final c in [
      'target',
      'left_electrode_model',
      'right_electrode_model',
      'left_ipg_model',
      'left_ipg_position',
      'right_ipg_model',
      'right_ipg_position',
    ])
      c: visit[c] ?? '',
  };

  final out = <SessionRow>[];
  var blockId = 0;
  void addBlock(
    Map<String, String> cells, {
    required bool initial,
    required Map<String, String> source,
  }) {
    final scales = [
      for (final e in source.entries)
        if (e.key.startsWith(scalePrefix)) (nameOf(e.key), e.value),
    ];
    final base = <String, String>{
      ...fixed,
      ...cells,
      'block_id': '$blockId',
      'is_initial': initialCell(initial),
    };
    if (scales.isEmpty) {
      out.add(SessionRow.fromMap(base));
    } else {
      for (final (name, value) in scales) {
        out.add(
          SessionRow.fromMap({
            ...base,
            'scale_name': name,
            'scale_value': value,
          }),
        );
      }
    }
    blockId++;
  }

  bool holdsAssessment(Map<String, String> row) =>
      [
        'medications',
        'program_id',
        'notes',
        ...stimColumns,
      ].any((c) => (row[c] ?? '').isNotEmpty) ||
      row.keys.any((c) => c.startsWith(scalePrefix));
  final assessment = holdsAssessment(initial)
      ? initial
      : holdsAssessment(visit)
      ? visit
      : null;
  if (assessment != null) {
    addBlock(
      {
        'acq_time': assessment['acq_time'] ?? visit['acq_time'] ?? '',
        'append_id': '1',
        'is_final': '0',
        'is_starred': '0',
        'medications': assessment['medications'] ?? '',
        'program_id': assessment['program_id'] ?? '',
        for (final c in stimColumns) c: assessment[c] ?? '',
        'notes': assessment['notes'] ?? '',
      },
      initial: true,
      source: assessment,
    );
  }
  for (final row in behRows) {
    addBlock(
      {for (final c in sessionColumns) c: row[c] ?? ''},
      initial: false,
      source: row,
    );
  }
  return out;
}

/// Parse a session file in either form: a `beh/` file of the BIDS tables, read
/// on its own, or the long form.
List<SessionRow> parseAnySessionTsv(String content) {
  final rows = parseTsv(content);
  if (rows.isNotEmpty && isBehHeader(rows.first.map((c) => c.trim()))) {
    return joinSession(behRows: parseTsvRecords(content));
  }
  return parseSessionTsv(content);
}

/// Whether a TSV [header] is a session's `beh/` file in the BIDS tables.
bool isBehHeader(Iterable<String> header) {
  final h = header.toSet();
  return h.contains('is_final') &&
      h.contains('program_id') &&
      !h.contains('scale_name');
}
