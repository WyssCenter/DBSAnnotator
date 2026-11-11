/// Flutter-free controller for the Complete-Workflow authoring screen, holding
/// the working rows of one programming-session TSV and its block/append
/// counters.
library;

import '../schema_columns.dart';
import 'session_file.dart';
import 'session_row.dart';

class SessionAuthoring {
  /// Existing and newly inserted rows, oldest first.
  final List<SessionRow> rows = [];

  int _blockId = 0;
  int _appendId = 1;

  /// Block ID the NEXT insert will use.
  int get blockId => _blockId;

  /// Append ID every insert of this app session uses; see [nextAppendId].
  int get appendId => _appendId;

  /// Load an existing session's rows and continue its numbering.
  void loadExisting(List<SessionRow> existing) {
    rows
      ..clear()
      ..addAll(existing);
    _blockId = nextBlockId(rows);
    _appendId = nextAppendId(rows);
  }

  /// Append one block and return its rows, or rewrite block [replacing] in
  /// place. [stim] maps the stimulation column names to their cells.
  List<SessionRow> addInsert({
    required bool isInitial,
    required Map<String, String> stim,
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
    DateTime? at,
    int? replacing,
  }) {
    final inserted = buildInsertRows(
      blockId: replacing ?? _blockId,
      appendId: _appendId,
      isInitial: isInitial,
      scales: scales,
      programId: programId,
      leftElectrodeModel: leftElectrodeModel,
      rightElectrodeModel: rightElectrodeModel,
      pathology: pathology,
      target: target,
      leftIpgModel: leftIpgModel,
      rightIpgModel: rightIpgModel,
      medications: medications,
      starred: starred,
      notes: notes,
      leftStimFreq: stim['left_stim_freq'] ?? '',
      leftAnode: stim['left_anode'] ?? '',
      leftCathode: stim['left_cathode'] ?? '',
      leftAmplitude: stim['left_amplitude'] ?? '',
      leftPulseWidth: stim['left_pulse_width'] ?? '',
      rightStimFreq: stim['right_stim_freq'] ?? '',
      rightAnode: stim['right_anode'] ?? '',
      rightCathode: stim['right_cathode'] ?? '',
      rightAmplitude: stim['right_amplitude'] ?? '',
      rightPulseWidth: stim['right_pulse_width'] ?? '',
      at: at,
    );
    if (replacing == null) {
      rows.addAll(inserted);
      _blockId += 1;
      return inserted;
    }
    final at0 = rows.indexWhere((r) => r.blockId == '$replacing');
    rows.removeWhere((r) => r.blockId == '$replacing');
    rows.insertAll(at0 < 0 ? rows.length : at0, inserted);
    return inserted;
  }

  /// Mark [blockId] as the block the patient was left on, clearing any other
  /// mark; null clears them all. Rows are rewritten rather than appended, so
  /// the file still has one row per scale per block.
  void markFinalBlock(String? blockId) {
    for (var i = 0; i < rows.length; i++) {
      final mark = blockId != null && rows[i].blockId == blockId ? '1' : '0';
      if (rows[i].isFinal == mark) continue;
      rows[i] = SessionRow.fromMap({...rows[i].toMap(), 'is_final': mark});
    }
  }

  /// Star or unstar every row of [blockId].
  void setStarred(String blockId, bool starred) {
    final mark = initialCell(starred);
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].blockId != blockId || rows[i].isStarred == mark) continue;
      rows[i] = SessionRow.fromMap({...rows[i].toMap(), 'is_starred': mark});
    }
  }

  /// Remove every row of [blockId].
  void removeBlock(String blockId) =>
      rows.removeWhere((r) => r.blockId == blockId);

  /// Write [cells] into every row of [blockId].
  void setOnBlock(String blockId, Map<String, String> cells) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].blockId != blockId) continue;
      rows[i] = SessionRow.fromMap({...rows[i].toMap(), ...cells});
    }
  }

  /// Write [cells] into every row, such as a corrected lead or indication.
  void setOnEveryRow(Map<String, String> cells) {
    for (var i = 0; i < rows.length; i++) {
      rows[i] = SessionRow.fromMap({...rows[i].toMap(), ...cells});
    }
  }

  /// The long-form document of the app's working copy.
  String serialize() => serializeSessionTsv(rows);
}
