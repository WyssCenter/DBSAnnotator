/// One row of a programming-session (`task-programming`) TSV.
library;

import '../schema_columns.dart';
import '../timestamps.dart';

/// One row of a programming-session (`task-programming`) TSV.
///
/// Every field stays the raw TSV string so a parse/serialize round trip is
/// lossless: the desktop writes block IDs as "3" or "3.0", amplitudes as
/// split strings like "1.5_1", and scale cells with embedded newlines.
class SessionRow {
  const SessionRow({
    this.acqTime = '',
    this.blockId = '',
    this.appendId = '',
    this.isInitial = '',
    this.isFinal = '',
    this.isStarred = '',
    this.scaleName = '',
    this.scaleValue = '',
    this.pathology = '',
    this.target = '',
    this.leftElectrodeModel = '',
    this.rightElectrodeModel = '',
    this.ipgModel = '',
    this.programId = '',
    this.leftStimFreq = '',
    this.leftAnode = '',
    this.leftCathode = '',
    this.leftAmplitude = '',
    this.leftPulseWidth = '',
    this.rightStimFreq = '',
    this.rightAnode = '',
    this.rightCathode = '',
    this.rightAmplitude = '',
    this.rightPulseWidth = '',
    this.medications = '',
    this.notes = '',
  });

  /// The whole instant as one ISO-8601 string and the only timestamp a row
  /// carries; empty only when the source had nothing parseable.
  final String acqTime;
  final String blockId;

  /// Data-entry episode within one file, incremented each time that file is
  /// reopened: file-scoped, so equal values in two files are unrelated.
  final String appendId;
  final String isInitial;

  /// `1` on the rows of the block the patient was left on, `0` elsewhere, and
  /// empty in files written before the column existed.
  final String isFinal;

  /// `1` on the rows of a block the clinician starred, `0` elsewhere.
  final String isStarred;
  final String scaleName;
  final String scaleValue;

  /// The condition and the leads' anatomical target, the same on every row.
  final String pathology;
  final String target;

  /// The lead model per side, as named in `schema/electrode_models.json`.
  final String leftElectrodeModel;
  final String rightElectrodeModel;
  final String ipgModel;
  final String programId;
  final String leftStimFreq;
  final String leftAnode;
  final String leftCathode;
  final String leftAmplitude;
  final String leftPulseWidth;
  final String rightStimFreq;
  final String rightAnode;
  final String rightCathode;
  final String rightAmplitude;
  final String rightPulseWidth;

  /// Free text from the initial assessment, empty on recording rows.
  final String medications;
  final String notes;

  /// Build from a TSV record keyed by `sessionColumns`; missing columns become
  /// ''. Reads through [readColumn], so superseded spellings open without a
  /// conversion step, and this is where a legacy row gains its instant: doing
  /// the [backfillAcqTime] composition at the single parse boundary means no
  /// report, aggregate or export has to know the source was older.
  factory SessionRow.fromMap(Map<String, String> m) => SessionRow(
    acqTime: _acqTimeOf(m),
    blockId: readColumn(m, 'block_id'),
    appendId: readColumn(m, 'append_id'),
    isInitial: readColumn(m, 'is_initial'),
    isFinal: readColumn(m, 'is_final'),
    isStarred: readColumn(m, 'is_starred'),
    scaleName: readColumn(m, 'scale_name'),
    scaleValue: readColumn(m, 'scale_value'),
    pathology: readColumn(m, 'pathology'),
    target: readColumn(m, 'target'),
    leftElectrodeModel: readColumn(m, 'left_electrode_model'),
    rightElectrodeModel: readColumn(m, 'right_electrode_model'),
    ipgModel: readColumn(m, 'ipg_model'),
    programId: readColumn(m, 'program_id'),
    leftStimFreq: readColumn(m, 'left_stim_freq'),
    leftAnode: readColumn(m, 'left_anode'),
    leftCathode: readColumn(m, 'left_cathode'),
    leftAmplitude: readColumn(m, 'left_amplitude'),
    leftPulseWidth: readColumn(m, 'left_pulse_width'),
    rightStimFreq: readColumn(m, 'right_stim_freq'),
    rightAnode: readColumn(m, 'right_anode'),
    rightCathode: readColumn(m, 'right_cathode'),
    rightAmplitude: readColumn(m, 'right_amplitude'),
    rightPulseWidth: readColumn(m, 'right_pulse_width'),
    medications: readColumn(m, 'medications'),
    notes: readColumn(m, 'notes'),
  );

  /// The row's instant as a local [DateTime], or null when [acqTime] is empty
  /// or unparsable: an external TSV can carry anything, and callers skip rows
  /// they cannot place in time. `.toLocal()` makes rows recorded in different
  /// offsets comparable.
  DateTime? get timestamp {
    final parsed = DateTime.tryParse(acqTime.trim());
    return parsed?.toLocal();
  }

  /// [acqTime] as written, or composed from a legacy row's `date`/`time`.
  static String _acqTimeOf(Map<String, String> m) {
    final iso = readColumn(m, 'acq_time').trim();
    if (iso.isNotEmpty) return iso;
    return backfillAcqTime(
      date: readColumn(m, 'date'),
      time: readColumn(m, 'time'),
      timezone: readColumn(m, 'timezone'),
    );
  }

  /// Convert to a TSV record keyed by the exact column names.
  Map<String, String> toMap() => {
    'acq_time': acqTime,
    'block_id': blockId,
    'append_id': appendId,
    'is_initial': isInitial,
    'is_final': isFinal,
    'is_starred': isStarred,
    'scale_name': scaleName,
    'scale_value': scaleValue,
    'pathology': pathology,
    'target': target,
    'left_electrode_model': leftElectrodeModel,
    'right_electrode_model': rightElectrodeModel,
    'ipg_model': ipgModel,
    'program_id': programId,
    'left_stim_freq': leftStimFreq,
    'left_anode': leftAnode,
    'left_cathode': leftCathode,
    'left_amplitude': leftAmplitude,
    'left_pulse_width': leftPulseWidth,
    'right_stim_freq': rightStimFreq,
    'right_anode': rightAnode,
    'right_cathode': rightCathode,
    'right_amplitude': rightAmplitude,
    'right_pulse_width': rightPulseWidth,
    'medications': medications,
    'notes': notes,
  };
}

/// The electrode model [rows] name for one side, the left unless [right], or
/// '' when none of them say. The name keys `ElectrodeCatalog.models`, and a
/// file opened against the wrong model labels one lead's contacts with another
/// lead's geometry.
String electrodeModelIn(Iterable<SessionRow> rows, {bool right = false}) {
  for (final row in rows) {
    final name = (right ? row.rightElectrodeModel : row.leftElectrodeModel)
        .trim();
    if (name.isNotEmpty) return name;
  }
  return '';
}

/// The first non-empty value [field] takes in [rows], or ''.
String sessionValueIn(
  Iterable<SessionRow> rows,
  String Function(SessionRow) field,
) {
  for (final row in rows) {
    final value = field(row).trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

/// The blocks [rows] mark as starred.
Set<String> starredBlocksIn(Iterable<SessionRow> rows) => {
  for (final row in rows)
    if (isInitialValue(row.isStarred)) row.blockId,
};

/// The block [rows] mark as the one the patient was left on, or null.
String? finalBlockIn(Iterable<SessionRow> rows) {
  for (final row in rows) {
    if (isInitialValue(row.isFinal)) return row.blockId;
  }
  return null;
}
