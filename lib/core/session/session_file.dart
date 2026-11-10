/// Programming-session TSV parsing, appending, and serialization, mirroring
/// dbs_annotator/models/session_data.py.
///
/// The desktop app holds an open append handle; on the tablet there is none,
/// so callers read the whole TSV, append rows in memory and rewrite it.
/// Compatibility runs one way: this app reads what the desktop wrote.
library;

import '../schema_columns.dart';
import '../timestamps.dart';
import '../tsv.dart';
import 'session_row.dart';

/// A (name, value) session-scale reading entered in Step 3.
typedef ScaleEntry = ({String name, String value});

/// Parse a programming-session TSV document into [SessionRow]s.
List<SessionRow> parseSessionTsv(String content) =>
    parseTsvRecords(content).map(SessionRow.fromMap).toList();

/// Serialize rows to a full TSV document with the canonical column header.
String serializeSessionTsv(List<SessionRow> rows) =>
    writeTsvRecords(workingColumns, rows.map((r) => r.toMap()).toList());

/// A TSV integer cell as Python's `int(float(val))`; null when unparsable.
int? _asInt(String raw) {
  final v = double.tryParse(raw.trim());
  if (v == null || !v.isFinite) return null;
  return v.truncate();
}

/// Next block ID for an append: max(block_id) + 1, or 0 for a new file.
int nextBlockId(List<SessionRow> existing) {
  var maxBlock = -1;
  for (final row in existing) {
    final v = _asInt(row.blockId);
    if (v != null && v > maxBlock) maxBlock = v;
  }
  return maxBlock + 1;
}

/// Next append ID: max(append_id) + 1, or 1 for a new file. It counts
/// data-entry episodes within one file, so it is file-scoped by design and
/// equal values in two files are unrelated.
int nextAppendId(List<SessionRow> existing) {
  var maxAppend = 0;
  for (final row in existing) {
    final v = _asInt(row.appendId);
    if (v != null && v > maxAppend) maxAppend = v;
  }
  return maxAppend + 1;
}

/// Build the new rows for one insert: one per scale that survives the filter,
/// or a single scale-less row when none does, all sharing the same block and
/// append IDs, timestamp and stimulation columns. [isInitial] marks a Step-1
/// baseline, which additionally requires a non-blank scale name. The caller
/// recomputes the next block ID with [nextBlockId] after appending.
List<SessionRow> buildInsertRows({
  required int blockId,
  required int appendId,
  bool isInitial = false,
  List<ScaleEntry> scales = const [],
  String programId = '',
  String leftElectrodeModel = '',
  String rightElectrodeModel = '',
  String pathology = '',
  String target = '',
  String leftIpgModel = '',
  String rightIpgModel = '',
  String medications = '',
  bool starred = false,
  String notes = '',
  String leftStimFreq = '',
  String leftAnode = '',
  String leftCathode = '',
  String leftAmplitude = '',
  String leftPulseWidth = '',
  String rightStimFreq = '',
  String rightAnode = '',
  String rightCathode = '',
  String rightAmplitude = '',
  String rightPulseWidth = '',
  DateTime? at,
}) {
  final acqTime = acqTimeCell(at ?? DateTime.now());

  SessionRow row({String scaleName = '', String scaleValue = ''}) => SessionRow(
    acqTime: acqTime,
    blockId: '$blockId',
    appendId: '$appendId',
    // Via `initialCell` so the "exactly 0 or 1, never 0.0" rule has one owner.
    isInitial: initialCell(isInitial),
    // Marked afterwards, by the clinician, with [markFinalBlock].
    isFinal: '0',
    isStarred: initialCell(starred),
    scaleName: scaleName,
    scaleValue: scaleValue,
    leftElectrodeModel: leftElectrodeModel,
    rightElectrodeModel: rightElectrodeModel,
    pathology: pathology,
    target: target,
    leftIpgModel: leftIpgModel,
    rightIpgModel: rightIpgModel,
    programId: programId,
    leftStimFreq: leftStimFreq,
    leftAnode: leftAnode,
    leftCathode: leftCathode,
    leftAmplitude: leftAmplitude,
    leftPulseWidth: leftPulseWidth,
    rightStimFreq: rightStimFreq,
    rightAnode: rightAnode,
    rightCathode: rightCathode,
    rightAmplitude: rightAmplitude,
    rightPulseWidth: rightPulseWidth,
    medications: medications,
    notes: notes,
  );

  final valid = scales
      .where(
        (s) =>
            s.value.trim().isNotEmpty &&
            (!isInitial || s.name.trim().isNotEmpty),
      )
      .toList();
  if (valid.isEmpty) return [row()];
  return [for (final s in valid) row(scaleName: s.name, scaleValue: s.value)];
}
