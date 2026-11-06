// Regenerate the synthetic example session used by the tests and the docs.
//
//   dart run tool/generate_fixtures.dart
//
// Every rating, stimulation parameter and timestamp below is invented; no
// recorded patient data goes into these fixtures. Generating rather than
// hand-editing keeps the header, column order, `n/a` sentinel, line endings
// and largest-remainder amplitude encoding identical to what the app writes,
// since the file goes through `buildInsertRows` + `serializeSessionTsv`.
//
// `test/ranking_values_test.dart` and `test/report_graphics_test.dart` assert
// properties of this data, so preserve all of the following or re-derive the
// expected values:
//
//  * 1 baseline block (`is_initial=1`, clinical scales) + 7 recording blocks
//    × 5 session scales = 35 rated rows.
//  * Blocks 6 and 7 are a replicate pair: byte-identical across all ten
//    stimulation columns, rated 9 seconds apart. They are the session's own
//    measure of re-rating noise.
//  * Blocks 3 and 4 carry the same five ratings under different stimulation,
//    so the record cannot tell a re-rating from values carried forward.
//  * Replicate spread must exceed between-setting separation: 0.070 (blocks
//    6 to 7) against 0.010 (blocks 2 vs 3). A test asserts that inequality
//    directly, because it is what makes the report's own warning true.
//  * 6 distinct stimulation settings across the 7 recording blocks.
//  * At least one current-split block, so percentage rendering is covered
//    (block 4 splits three ways, exercising the 33/33/34 remainder case).
//
// Every scale is targeted `min` over 0 to 10, so a block's aggregate index is
// the mean of `1 - value/10` over its five ratings. The designed ranking is
// 7, 6, 2, 3, 4, 1, 5: the best setting is blocks 6+7 and block 1 is rank 6.
// `main` prints the indices themselves.

import 'dart:io';

import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/core/timestamps.dart';
import 'package:dbs_annotator/core/tsv.dart';

/// A fictional instant. UTC on purpose: a non-zero offset would invite a
/// reader to infer a recording site that does not exist.
final DateTime _start = DateTime.utc(2026, 2, 3, 9);

const String _model = 'Medtronic SenSight B33005';
const String _program = 'B';
const String _freq = '130';
const String _pulseWidth = '60';

/// One recording block: when it was rated, its stimulation, and its ratings.
typedef _Block = ({
  int seconds, // offset from _start
  String leftCathode,
  String leftAmplitude,
  String rightCathode,
  String rightAmplitude,
  List<double> ratings, // Obsessions, Compulsions, Anxiety, Mood, Energy
  String notes,
});

const List<String> _sessionScales = [
  'Obsessions',
  'Compulsions',
  'Anxiety',
  'Mood',
  'Energy',
];

const List<_Block> _blocks = [
  (
    seconds: 200,
    leftCathode: 'E1b_E1c',
    leftAmplitude: '3.0_2.0',
    rightCathode: 'E3',
    rightAmplitude: '4.0',
    ratings: [8.00, 7.50, 5.00, 6.50, 4.00],
    notes: 'starting configuration carried over from the last visit',
  ),
  (
    seconds: 305,
    leftCathode: 'E1b_E1c',
    leftAmplitude: '3.0_2.0',
    rightCathode: 'E3',
    rightAmplitude: '5.0',
    ratings: [6.50, 6.00, 4.50, 6.00, 4.00],
    notes: '',
  ),
  (
    seconds: 460,
    leftCathode: 'E1b_E1c',
    leftAmplitude: '3.0_2.0',
    rightCathode: 'E3',
    rightAmplitude: '6.0',
    ratings: [6.25, 6.25, 4.75, 5.75, 4.50],
    notes: '',
  ),
  (
    seconds: 555,
    leftCathode: 'E1b_E1c',
    leftAmplitude: '3.0_2.0',
    rightCathode: 'E2a_E2b_E2c',
    rightAmplitude: '2.0_2.0_2.0',
    ratings: [6.25, 6.25, 4.75, 5.75, 4.50],
    notes: 'transient warmth on the right, settled within a minute',
  ),
  (
    seconds: 710,
    leftCathode: 'E1b_E1c',
    leftAmplitude: '3.0_2.0',
    rightCathode: 'E2a_E2b_E2c',
    rightAmplitude: '2.5_2.5_2.5',
    ratings: [7.00, 7.25, 8.00, 6.75, 7.50],
    notes: 'reported feeling anxious and low; amplitude reduced',
  ),
  (
    seconds: 870,
    leftCathode: 'E1c',
    leftAmplitude: '4.0',
    rightCathode: 'E3',
    rightAmplitude: '5.0',
    ratings: [4.00, 3.75, 4.25, 5.50, 3.50],
    notes: 'settled, obsessions much reduced',
  ),
  // Nine seconds after block 6, on identical stimulation: too short to be a
  // plausible re-administration, which makes this pair the noise floor.
  (
    seconds: 879,
    leftCathode: 'E1c',
    leftAmplitude: '4.0',
    rightCathode: 'E3',
    rightAmplitude: '5.0',
    ratings: [2.75, 3.00, 4.00, 4.75, 3.00],
    notes: 're-rated on the same setting',
  ),
];

/// The baseline assessment: clinical instruments, before any change. `Y-BOCS`
/// is the sum of its obsession and compulsion subscales.
const List<ScaleEntry> _clinicalScales = [
  (name: 'Y-BOCS', value: '28'),
  (name: 'Y-BOCS-o', value: '15'),
  (name: 'Y-BOCS-c', value: '13'),
  (name: 'MADRS', value: '24'),
];

String _fmt(double v) => v.toStringAsFixed(2);

List<SessionRow> _rows() => [
  ...buildInsertRows(
    blockId: 0,
    appendId: 1,
    isInitial: true,
    scales: _clinicalScales,
    programId: _program,
    leftElectrodeModel: _model,
    rightElectrodeModel: _model,
    notes: 'baseline assessment before any change this visit',
    leftStimFreq: _freq,
    leftAnode: 'case',
    leftCathode: _blocks.first.leftCathode,
    leftAmplitude: _blocks.first.leftAmplitude,
    leftPulseWidth: _pulseWidth,
    rightStimFreq: _freq,
    rightAnode: 'case',
    rightCathode: _blocks.first.rightCathode,
    rightAmplitude: _blocks.first.rightAmplitude,
    rightPulseWidth: _pulseWidth,
    at: _start,
  ),
  for (var i = 0; i < _blocks.length; i++)
    ...buildInsertRows(
      blockId: i + 1,
      appendId: 1,
      scales: [
        for (var s = 0; s < _sessionScales.length; s++)
          (name: _sessionScales[s], value: _fmt(_blocks[i].ratings[s])),
      ],
      programId: _program,
      leftElectrodeModel: _model,
      rightElectrodeModel: _model,
      notes: _blocks[i].notes,
      leftStimFreq: _freq,
      leftAnode: 'case',
      leftCathode: _blocks[i].leftCathode,
      leftAmplitude: _blocks[i].leftAmplitude,
      leftPulseWidth: _pulseWidth,
      rightStimFreq: _freq,
      rightAnode: 'case',
      rightCathode: _blocks[i].rightCathode,
      rightAmplitude: _blocks[i].rightAmplitude,
      rightPulseWidth: _pulseWidth,
      at: _start.add(Duration(seconds: _blocks[i].seconds)),
    ),
];

/// The pre-0.5.0 spelling of the same data, so the `legacyColumnAliases` read
/// path keeps a real file to exercise. 21 columns, `block_ID`/`session_ID`/
/// `program_ID`, no `acq_time`, and `NaN` where 0.5.0 writes `n/a`.
String _legacyDocument(List<SessionRow> rows) {
  const legacyColumns = [
    'date',
    'time',
    'timezone',
    'block_ID',
    'session_ID',
    'is_initial',
    'scale_name',
    'scale_value',
    'electrode_model',
    'program_ID',
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
    'notes',
  ];
  const rename = {
    'block_id': 'block_ID',
    'append_id': 'session_ID',
    'program_id': 'program_ID',
    // Older files have one model column for both leads.
    'left_electrode_model': 'electrode_model',
  };
  // A 0.4.x file has no `acq_time`: it stored the instant as `date` + `time`
  // plus a free-text `timezone`, so those three cells are rebuilt here. This
  // is the regression test for `backfillAcqTime`, which must reconstruct the
  // same instant, offset included, from nothing but them. The harder Windows
  // zone spelling (`W. Europe Daylight Time +0200`) is left to unit tests.
  final records = <Map<String, String>>[];
  for (final row in rows) {
    final at = DateTime.parse(row.acqTime);
    final mapped = <String, String>{
      'date': dateCell(at),
      'time': timeCell(at),
      'timezone': 'UTC ${offsetString(at)}',
    };
    for (final entry in row.toMap().entries) {
      if (entry.key == 'acq_time') continue;
      mapped[rename[entry.key] ?? entry.key] = entry.value;
    }
    records.add(mapped);
  }
  return writeTsvRecords(legacyColumns, records);
}

void main() {
  // The clinician marks the last block as the one the patient leaves on, as
  // the visit's notes say, so the reports show a marked final configuration.
  final authoring = SessionAuthoring()..rows.addAll(_rows());
  authoring.markFinalBlock('${_blocks.length}');
  final rows = authoring.rows;
  const dir = 'test/fixtures';
  const stem = 'sub-01_ses-20260203_task-programming_run-01';

  File('$dir/${stem}_beh.tsv').writeAsStringSync(serializeSessionTsv(rows));
  File('$dir/legacy_0.4_${stem}_events.tsv')
      .writeAsStringSync(_legacyDocument(rows).replaceAll('\tn/a', '\tNaN'));

  // Print the arithmetic the tests pin, so a change here shows its effect
  // immediately rather than as a context-free test failure.
  stdout.writeln('${rows.length} rows, ${sessionColumns.length} columns');
  final byBlock = <String, List<double>>{};
  for (final r in rows.where((r) => r.isInitial.trim() != '1')) {
    (byBlock[r.blockId] ??= []).add(double.parse(r.scaleValue));
  }
  for (final block in byBlock.keys) {
    final v = byBlock[block]!;
    final index = 1 - (v.reduce((a, b) => a + b) / v.length) / 10;
    stdout.writeln('  block $block  index ${index.toStringAsFixed(3)}');
  }
}
