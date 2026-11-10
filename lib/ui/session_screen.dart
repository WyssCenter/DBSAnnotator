import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;

import '../core/bids.dart';
import '../core/bids_sidecar.dart';
import '../core/electrode/amplitude.dart';
import '../core/electrode/contact_state.dart';
import '../core/electrode/electrode_model.dart';
import '../core/electrode/stimulation_rule.dart';
import '../core/electrode/tokens.dart';
import '../core/prefs/user_prefs.dart';
import '../core/schema_columns.dart' show isInitialValue;
import '../core/session/authoring.dart';
import '../core/session/scale_presets.dart';
import '../core/session/tsv_kind.dart';
import '../core/session/scale_scoring.dart'
    show ScaleMode, ScalePref, scaleModeFromString;
import '../core/session/session_row.dart';
import '../core/timestamps.dart' show recordedTime;
import '../report/entry_charts.dart';
import '../report/report_data.dart';
import '../report/report_sections.dart';
import '../report/session_docx.dart';
import '../report/session_pdf.dart';
import '../app_info.dart';
import 'amplitude_split.dart';
import 'bids_export.dart';
import 'electrode_view.dart';
import 'list_editor_dialog.dart';
import 'report_images.dart';
import 'report_sections_dialog.dart';
import 'session/entries_table.dart';
import 'session/entry_charts_view.dart';
import 'scale_presets_dialog.dart';
import 'scale_targets_dialog.dart';
import 'save_target.dart';
import 'scale_slider.dart';
import 'share_util.dart';
import 'devices_dialog.dart';
import 'recording_file.dart';
import 'stim_defaults_dialog.dart';
import 'wizard_parts.dart';
import 'stim_params_form.dart';
import 'theme.dart';

/// A programming session in four steps: Setup, Initial assessment,
/// Programming and Finish, written as a `task-programming` TSV.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    this.catalog,
    this.limits,
    this.scalePresets,
    this.authoring,
  });

  /// Injectable for headless tests; loaded from bundled assets when null.
  final ElectrodeCatalog? catalog;
  final StimLimits? limits;
  final ScalePresets? scalePresets;

  /// A session already open, so Setup does not ask for one; injectable for
  /// headless tests. A fresh one is created when null.
  final SessionAuthoring? authoring;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

/// Desktop-identical number formatting: f"{x:.2f}".rstrip("0").rstrip(".").
String _fmtValue(double v) {
  var out = v.toStringAsFixed(2);
  while (out.endsWith('0')) {
    out = out.substring(0, out.length - 1);
  }
  if (out.endsWith('.')) out = out.substring(0, out.length - 1);
  return out;
}

/// The sentence for electrode models a file names that the catalogue lacks.
String _unknownModelsNotice(List<String> models) {
  if (models.length == 1) {
    return 'This file names an electrode model, ${models.first}, that is not '
        'in the catalogue.';
  }
  final head = models.sublist(0, models.length - 1).join(', ');
  return 'This file names electrode models $head and ${models.last} that are '
      'not in the catalogue.';
}

/// One clinical scale of the initial assessment: name and score.
class _ClinicalScaleEdit {
  final name = TextEditingController();
  final score = TextEditingController();

  void dispose() {
    name.dispose();
    score.dispose();
  }
}

/// One rating of Programming: its bounds, slider [value] and [omitted]
/// "not assessed" toggle.
class _SessionScaleEdit {
  _SessionScaleEdit({
    required double min,
    required double max,
    String name = '',
    this.mode = ScaleMode.min,
    this.step,
  }) : value = min,
       omitted = step != null {
    this.name.text = name;
    minCtrl.text = _fmtValue(min);
    maxCtrl.text = _fmtValue(max);
  }

  final name = TextEditingController();
  final minCtrl = TextEditingController();
  final maxCtrl = TextEditingController();
  double value;
  bool omitted;

  /// The rating step of an official item; null for a continuous bar.
  double? step;

  /// How this scale is scored when ranking configurations (the desktop export
  /// dialog's Min / Max / Custom radio). Seeded from the preset's contract cell
  /// and editable via [showScaleTargetsDialog].
  ScaleMode mode;
  double? custom;

  double minOr(double fallback) =>
      double.tryParse(minCtrl.text.trim()) ?? fallback;
  double maxOr(double fallback) =>
      double.tryParse(maxCtrl.text.trim()) ?? fallback;

  void dispose() {
    name.dispose();
    minCtrl.dispose();
    maxCtrl.dispose();
  }
}

/// One side's stimulation inputs: form controllers and electrode contacts.
class _SideInputs {
  final freq = TextEditingController();
  final amp = TextEditingController();
  final pulseWidth = TextEditingController();
  Map<ContactKey, ContactState> states = {};
  ContactState caseState = ContactState.off;
  String validationError = '';

  /// Per-side enable checkbox (desktop's checkable electrode group).
  bool enabled = true;

  /// Amplitude split percentages, aligned to the active cathodes; used to
  /// serialize `left/right_amplitude` when >= 2 cathodes are active.
  List<double> ampSplit = const [];

  void dispose() {
    freq.dispose();
    amp.dispose();
    pulseWidth.dispose();
  }
}

const _stepNames = ['Setup', 'Initial assessment', 'Programming', 'Finish'];
const _finishStep = 3;

const RecordingWords _words = (
  entry: 'entry',
  what: 'this visit',
  thing: 'the session',
  staysInApp: 'This visit stays in the app.',
  exportUnderOtherRun: 'Export it under a different run.',
  savedInApp: 'The visit is saved in the app.',
  filedOnFirstEntry:
      'The visit is filed there as soon as the first block is inserted.',
  newDialogTitle: 'Create new session TSV',
  newFileSaid: 'New session',
  recoveryTitle: 'Unfinished session found',
  pickerFailed: 'Could not open the file picker.',
);

class _SessionScreenState extends State<SessionScreen>
    with RecordingFile<SessionScreen, SessionAuthoring> {
  late SessionAuthoring _authoring = widget.authoring ?? SessionAuthoring();
  final _ids = BidsEntries('programming');
  // Notes are per-context: the initial-config notes persist across inserts (the
  // user keeps refining them); recording notes clear after each block.
  final _notesInitCtrl = TextEditingController();
  final _pathologyCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _leftIpgCtrl = TextEditingController(text: kDefaultIpg);
  final _rightIpgCtrl = TextEditingController();

  /// Whether one IPG drives both leads, so the right field is hidden.
  bool _sameIpg = true;
  final _medicationsCtrl = TextEditingController();
  final _notesRecCtrl = TextEditingController();

  // Electrode/param state is INDEPENDENT per step: editing the recording config
  // must not change what the initial config shows. The recording pair is seeded
  // once from the initial pair on first entry to the Recording step.
  final _leftInit = _SideInputs();
  final _rightInit = _SideInputs();
  final _leftRec = _SideInputs();
  final _rightRec = _SideInputs();
  bool _recSeeded = false;
  int? _initialBlock;
  String? _initialSaved;
  final _clinicalScales = <_ClinicalScaleEdit>[];
  final _sessionScales = <_SessionScaleEdit>[];
  // Removed rows are kept here so their controllers outlive the frame in
  // which their TextField unmounts; disposed with the screen.
  final _removedClinical = <_ClinicalScaleEdit>[];
  final _removedSession = <_SessionScaleEdit>[];

  int _currentStep = 0;
  String? _modelName;

  /// The right lead's model when it differs from the left one; null while
  /// both leads are [_modelName].
  String? _rightModelName;

  /// Whether the block about to be inserted is the one the patient leaves on.
  bool _leavesOn = false;

  /// Whether the block about to be inserted is starred.
  bool _starNext = false;
  // The indication whose scales are loaded.
  String? _selectedClinicalPreset;
  // Selected program name (desktop program combo).
  String? _selectedProgram;
  // Per-user overrides (programs + presets), loaded async.
  UserPrefs _prefs = UserPrefs();
  late final Future<(ElectrodeCatalog, StimLimits, ScalePresets)> _contracts;

  @override
  void initState() {
    super.initState();
    _contracts = _loadContracts();
    loadUserPrefs().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
    if (widget.authoring case final a?) {
      _fillSessionDetails(a.rows);
      _loadPathologyScales();
    }
  }

  // Chart data is derived from every inserted row, so it is cached and rebuilt
  // only when the rows actually change. Without this it would be recomputed on
  // every setState -- i.e. on every slider tick in this step -- and, because
  // EntryChartData holds maps with no value equality, every panel would repaint
  // too.
  EntryChartData? _entryChartsCache;
  List<ScalePref>? _entryChartsPrefs;

  EntryChartData _entryCharts() {
    final prefs = _scalePrefs();
    // Also rebuild when the TARGETS change, not only the rows: the bounds set
    // the scales panel's y axis and the modes decide which block is banded, so
    // caching on rows alone left the figure stale after editing either.
    if (_entryChartsCache == null || !listEquals(_entryChartsPrefs, prefs)) {
      _entryChartsPrefs = prefs;
      _entryChartsCache = buildEntryChartData(
        _authoring.rows,
        scalePrefs: prefs,
      );
    }
    return _entryChartsCache!;
  }

  /// Call wherever [_authoring] is mutated, or the figure goes stale.
  void _invalidateEntryCharts() => _entryChartsCache = null;

  /// The optimisation targets for every named session scale: the single input
  /// to both the on-screen ranking and the report's, so the green bands on the
  /// charts and in the document can never point at different blocks.
  List<ScalePref> _scalePrefs() => [
    for (final s in _sessionScales)
      if (s.name.text.trim().isNotEmpty)
        (
          name: s.name.text.trim(),
          min: s.minOr(0),
          max: s.maxOr(10),
          mode: s.mode,
          custom: s.custom,
        ),
  ];

  /// Edit the targets, then push them back onto the ratings so they, the
  /// figure and the report all stay in agreement.
  Future<void> _editScaleTargets() async {
    final updated = await showScaleTargetsDialog(context, _scalePrefs());
    if (updated == null || !mounted) return;
    final byName = {for (final p in updated) p.name: p};
    setState(() {
      for (final s in _sessionScales) {
        final p = byName[s.name.text.trim()];
        if (p == null) continue;
        s.minCtrl.text = _fmtValue(p.min);
        s.maxCtrl.text = _fmtValue(p.max);
        s.mode = p.mode;
        s.custom = p.custom;
      }
    });
  }

  /// The report content, computed ONCE per export and shared by the graphics
  /// step and both builders, so the two formats cannot disagree and
  /// `DateTime.now()` is read a single time.
  ///
  /// The rating bounds and optimisation modes go through as [ScalePref]s.
  /// Without them the report falls back to a 0-10 default, and the chart's
  /// y-axis clamp and the whole ranking ignore what the user typed.
  SessionReportData _reportData() => buildSessionReportData(
    rows: _authoring.rows,
    scalePrefs: _scalePrefs(),
    // Provenance: the report prints which file it came from, so it can be
    // tied back to one run among several of the same session.
    sourceFile: savePath == null ? '' : pickedBasename(savePath!),
  );

  /// Report paper size from the user preference, applied to BOTH formats so the
  /// PDF and the Word document always agree.
  bool get _reportLetter =>
      (_prefs.reportPageSize ?? kDefaultReportPageSize) == 'letter';

  /// Effective program names (user override, else the desktop defaults).
  List<String> get _programs => _prefs.programs ?? kDefaultPrograms;

  /// Desktop default electrode (step1_view: preselect "Medtronic SenSight
  /// B33005"), so the L/R canvases render immediately instead of a placeholder.
  static const String kDefaultModel = 'Medtronic SenSight B33005';

  /// The IPG Setup starts from, like [kDefaultModel] for the lead.
  static const String kDefaultIpg = 'Medtronic Percept RC';

  Future<(ElectrodeCatalog, StimLimits, ScalePresets)> _loadContracts() async {
    final catalog = widget.catalog ?? await loadElectrodeCatalog();
    final limits = widget.limits ?? await loadStimLimits();
    final presets = widget.scalePresets ?? await loadScalePresets();
    if (_modelName == null && catalog.models.containsKey(kDefaultModel)) {
      _modelName = kDefaultModel;
    }
    return (catalog, limits, presets);
  }

  @override
  void dispose() {
    _ids.dispose();
    _notesInitCtrl.dispose();
    _notesRecCtrl.dispose();
    _pathologyCtrl.dispose();
    _targetCtrl.dispose();
    _leftIpgCtrl.dispose();
    _rightIpgCtrl.dispose();
    _medicationsCtrl.dispose();
    _leftInit.dispose();
    _rightInit.dispose();
    _leftRec.dispose();
    _rightRec.dispose();
    for (final s in [..._clinicalScales, ..._removedClinical]) {
      s.dispose();
    }
    for (final s in [..._sessionScales, ..._removedSession]) {
      s.dispose();
    }
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// The `left_amplitude`/`right_amplitude` cell to WRITE for a side: '' when
  /// blank, otherwise the total encoded by encodeAmplitude.
  ///
  /// Named `_encodeAmplitudeCell`, not `_amplitudeCell`, because
  /// report_data.dart has an unrelated `_amplitudeCell` that RENDERS a stored
  /// cell for a report table. Two functions with one name on opposite sides of
  /// the same column invite exactly the wrong assumption.
  static String _encodeAmplitudeCell(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    final v = double.tryParse(t);
    return v == null ? t : encodeAmplitude(v, const []);
  }

  /// True when every stim field is blank or within limits; otherwise shows
  /// the blocking snackbar.
  bool _stimInRange(StimLimits limits, _SideInputs left, _SideInputs right) {
    final outOfRange = [
      rangeError(left.freq.text, limits.frequency),
      rangeError(left.amp.text, limits.amplitude),
      rangeError(left.pulseWidth.text, limits.pulseWidth),
      rangeError(right.freq.text, limits.frequency),
      rangeError(right.amp.text, limits.amplitude),
      rangeError(right.pulseWidth.text, limits.pulseWidth),
    ].whereType<String>();
    if (outOfRange.isNotEmpty) {
      _snack('Fix out-of-range stimulation values before inserting.');
      return false;
    }
    return true;
  }

  /// The 10 stimulation TSV cells from the given L/R inputs (initial or
  /// recording pair).
  Map<String, String> _stimCells(
    ElectrodeCatalog catalog,
    _SideInputs left,
    _SideInputs right,
  ) {
    final leads = _leads(catalog);
    var leftTokens = (anode: '', cathode: '');
    var rightTokens = (anode: '', cathode: '');
    if (leads.left case final model?) {
      leftTokens = encodeTokens(left.states, left.caseState, model);
    }
    if (leads.right case final model?) {
      rightTokens = encodeTokens(right.states, right.caseState, model);
    }
    return {
      'left_stim_freq': left.freq.text.trim(),
      'left_anode': leftTokens.anode,
      'left_cathode': leftTokens.cathode,
      'left_amplitude': _amplitudeFor(left, leftTokens),
      'left_pulse_width': left.pulseWidth.text.trim(),
      'right_stim_freq': right.freq.text.trim(),
      'right_anode': rightTokens.anode,
      'right_cathode': rightTokens.cathode,
      'right_amplitude': _amplitudeFor(right, rightTokens),
      'right_pulse_width': right.pulseWidth.text.trim(),
    };
  }

  /// Serialize a side's amplitude: an "a_b" split across cathodes when >= 2 are
  /// active (using the amplitude-split percentages), else the plain total.
  String _amplitudeFor(
    _SideInputs side,
    ({String anode, String cathode}) tokens,
  ) {
    final cathodes = tokens.cathode
        .split('_')
        .where((t) => t.isNotEmpty && t != 'case')
        .toList();
    final total = double.tryParse(side.amp.text.trim());
    if (cathodes.length >= 2 &&
        total != null &&
        side.ampSplit.length == cathodes.length) {
      return encodeAmplitude(total, side.ampSplit);
    }
    return _encodeAmplitudeCell(side.amp.text);
  }

  /// Copy one side's electrode + param state (for seeding recording from
  /// initial). Maps/lists are copied so the two pairs stay independent.
  void _copySide(_SideInputs from, _SideInputs to) {
    to.freq.text = from.freq.text;
    to.amp.text = from.amp.text;
    to.pulseWidth.text = from.pulseWidth.text;
    to.states = Map.of(from.states);
    to.caseState = from.caseState;
    to.enabled = from.enabled;
    to.ampSplit = List.of(from.ampSplit);
  }

  /// Write the initial assessment as one is_initial block when leaving its
  /// step, rewriting that block on later visits. False when values are invalid.
  bool _saveInitial(ElectrodeCatalog catalog, StimLimits limits) {
    final stim = _stimCells(catalog, _leftInit, _rightInit);
    final scales = [
      for (final s in _clinicalScales)
        (name: s.name.text.trim(), value: s.score.text.trim()),
    ];
    final notes = _notesInitCtrl.text.trim();
    final medications = _medicationsCtrl.text.trim();
    final models = (_modelName ?? '', _rightModelName ?? _modelName ?? '');
    final details = _sessionDetails;
    final signature = jsonEncode([
      stim,
      [for (final s in scales) '${s.name}=${s.value}'],
      notes,
      medications,
      _selectedProgram,
      models.$1,
      models.$2,
      details.pathology,
      details.target,
      details.leftIpg,
      details.rightIpg,
    ]);
    if (signature == _initialSaved) return true;
    final empty =
        stim.values.every((v) => v.isEmpty) &&
        scales.every((s) => s.value.isEmpty) &&
        notes.isEmpty &&
        medications.isEmpty;
    if (empty && _initialBlock == null) return true;
    if (!_stimInRange(limits, _leftInit, _rightInit)) return false;
    _invalidateEntryCharts();
    final inserted = _authoring.addInsert(
      isInitial: true,
      stim: stim,
      scales: scales,
      programId: _selectedProgram ?? '',
      leftElectrodeModel: models.$1,
      rightElectrodeModel: models.$2,
      pathology: details.pathology,
      target: details.target,
      leftIpgModel: details.leftIpg,
      rightIpgModel: details.rightIpg,
      medications: medications,
      notes: notes,
      replacing: _initialBlock,
    );
    _initialBlock = int.parse(inserted.first.blockId);
    _initialSaved = signature;
    autosave();
    _snack('Initial assessment saved.');
    return true;
  }

  /// Pathology, target and IPG as chosen in Setup, written on every row.
  ({String pathology, String target, String leftIpg, String rightIpg})
  get _sessionDetails => (
    pathology: _pathologyCtrl.text.trim(),
    target: _targetCtrl.text.trim(),
    leftIpg: _leftIpgCtrl.text.trim(),
    rightIpg: (_sameIpg ? _leftIpgCtrl : _rightIpgCtrl).text.trim(),
  );

  /// Fill pathology, target and IPG from an opened or recovered file.
  void _fillSessionDetails(List<SessionRow> rows) {
    _pathologyCtrl.text = sessionValueIn(rows, (r) => r.pathology);
    _targetCtrl.text = sessionValueIn(rows, (r) => r.target);
    _leftIpgCtrl.text = sessionValueIn(rows, (r) => r.leftIpgModel);
    _rightIpgCtrl.text = sessionValueIn(rows, (r) => r.rightIpgModel);
    _sameIpg =
        _rightIpgCtrl.text.isEmpty || _rightIpgCtrl.text == _leftIpgCtrl.text;
  }

  /// Edit and save one of the Setup lists with the shared list editor.
  Future<void> _editList(
    String title,
    List<String> items,
    void Function(List<String>) keep,
  ) async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => ListEditorDialog(title: title, items: List.of(items)),
    );
    if (result == null || !mounted) return;
    setState(() => keep(result));
    await saveUserPrefs(_prefs);
  }

  bool get _started => hasFile || widget.authoring != null;

  /// Move to [step], saving the initial assessment when leaving it and asking
  /// which configuration the patient leaves on when entering Finish.
  Future<void> _goTo(int step) async {
    if (step == _currentStep) return;
    if (step > 0 && !_started) {
      _snack(
        'Enter the patient ID and press New, or open a saved session, '
        'so the data has somewhere to be saved.',
      );
      return;
    }
    if (_currentStep == 1) {
      final (rawCatalog, limits, _) = await _contracts;
      final catalog = rawCatalog.withDevices(_prefs.devices);
      if (!mounted || !_saveInitial(catalog, limits)) return;
    }
    if (step == _finishStep && !await _confirmLeftOn()) return;
    if (step == 1) {
      final limits = (await _contracts).$2.withDefaults(_prefs.stimDefaults);
      _fillStimDefaults(limits.defaults[_pathologyCtrl.text.trim()]);
    }
    if (!mounted) return;
    setState(() {
      if (step == 2 && !_recSeeded) {
        _copySide(_leftInit, _leftRec);
        _copySide(_rightInit, _rightRec);
        _recSeeded = true;
      }
      _currentStep = step;
    });
  }

  /// Start both initial sides from the indication's [defaults], unless any
  /// stimulation value is already there.
  void _fillStimDefaults(List<num>? defaults) {
    final sides = [_leftInit, _rightInit];
    if (defaults == null ||
        sides.any(
          (s) => [s.freq, s.amp, s.pulseWidth].any((c) => c.text.isNotEmpty),
        )) {
      return;
    }
    for (final s in sides) {
      s.freq.text = presetLabel(defaults[0]);
      s.amp.text = presetLabel(defaults[1]);
      s.pulseWidth.text = presetLabel(defaults[2]);
    }
  }

  /// One Programming block (is_initial=0); omitted ratings write the
  /// contract's omitted literal.
  void _insertRecording(ElectrodeCatalog catalog, StimLimits limits) {
    if (!_stimInRange(limits, _leftRec, _rightRec)) return;
    _invalidateEntryCharts();
    final inserted = _authoring.addInsert(
      isInitial: false,
      stim: _stimCells(catalog, _leftRec, _rightRec),
      scales: [
        for (final s in _sessionScales)
          (
            name: s.name.text.trim(),
            value: s.omitted
                ? limits.sessionScaleOmittedTsv
                : _fmtValue(s.value),
          ),
      ],
      programId: _selectedProgram ?? '',
      leftElectrodeModel: _modelName ?? '',
      rightElectrodeModel: _rightModelName ?? _modelName ?? '',
      pathology: _sessionDetails.pathology,
      target: _sessionDetails.target,
      leftIpgModel: _sessionDetails.leftIpg,
      rightIpgModel: _sessionDetails.rightIpg,
      starred: _starNext,
      notes: _notesRecCtrl.text.trim(),
    );
    if (_leavesOn) _authoring.markFinalBlock(inserted.first.blockId);
    setState(() {
      _notesRecCtrl.clear();
      _leavesOn = false;
      _starNext = false;
    });
    autosave();
    _snack(
      'Inserted recording block ${inserted.first.blockId} '
      '(${inserted.length} row${inserted.length == 1 ? '' : 's'}).',
    );
  }

  void _toggleStar(String blockId) {
    final on = starredBlocksIn(_authoring.rows).contains(blockId);
    setState(() => _authoring.setStarred(blockId, !on));
    _invalidateEntryCharts();
    autosave();
  }

  @override
  RecordingWords get words => _words;

  @override
  TsvKind get tsvKind => TsvKind.programming;

  @override
  BidsName get bidsName => datasetName ?? _ids.name;

  @override
  String serialise() => _authoring.serialize();

  @override
  bool get hasEntries => _authoring.rows.isNotEmpty;

  @override
  String get firstAcqTime => _authoring.rows.first.acqTime;

  @override
  SessionAuthoring readTsv(String content) =>
      SessionAuthoring()..loadExisting(content);

  @override
  bool isBlank(SessionAuthoring content) => content.rows.isEmpty;

  @override
  String recoveredCount(SessionAuthoring content) =>
      '${blockCount(content.rows)} blocks';

  @override
  String openedSummary(SessionAuthoring content) =>
      '${content.rows.length} rows, next block ${content.blockId}, '
      'append ${content.appendId}';

  @override
  void show(SessionAuthoring content, {required bool reopened}) {
    _invalidateEntryCharts();
    _authoring = content;
    _initialBlock = null;
    _initialSaved = null;
    _fillSessionDetails(content.rows);
    _selectedClinicalPreset = null;
    if (reopened) _currentStep = 2;
  }

  @override
  void fillLabels(BidsName name) => _ids.fill(name);

  @override
  Future<void> announceLoaded(String message) async {
    _loadPathologyScales();
    final unknownModels = await _syncModelsToRows();
    if (!mounted) return;
    _snack(message);
    if (unknownModels.isNotEmpty) {
      _snack(
        '${_unknownModelsNotice(unknownModels)} The diagrams show '
        '${_modelName ?? 'the selected model'} instead.',
      );
    }
  }

  Future<void> _newSession() {
    if (_ids.subject.text.trim().isEmpty) {
      _snack('Enter the patient ID first.');
      return Future.value();
    }
    final authoring = SessionAuthoring();
    return newFile(
      proposed: _ids.name,
      header: authoring.serialize(),
      prefs: _prefs,
      start: (filedAs) {
        _invalidateEntryCharts();
        _authoring = authoring;
        if (filedAs != null) _ids.run.text = filedAs.run;
        _initialBlock = null;
        _initialSaved = null;
      },
    );
  }

  /// The file names its own electrode model, so the dropdown follows it. A
  /// mismatch is not cosmetic: it labels one lead's contacts with another
  /// lead's geometry, in the diagrams here and in the report.
  Future<List<String>> _syncModelsToRows() async {
    final catalog = (await _contracts).$1.withDevices(_prefs.devices);
    final named = electrodeModelIn(_authoring.rows);
    final namedRight = electrodeModelIn(_authoring.rows, right: true);
    final unknown = {
      for (final n in [named, namedRight])
        if (n.isNotEmpty && !catalog.models.containsKey(n)) '"$n"',
    }.toList();
    if (mounted && named.isNotEmpty && unknown.isEmpty) {
      setState(() {
        _modelName = named;
        _rightModelName = namedRight.isEmpty || namedRight == named
            ? null
            : namedRight;
      });
    }
    return unknown;
  }

  /// Report sections the user last chose (all of them, by default).
  Set<ReportSection> get _sections {
    final saved = _prefs.reportSections;
    if (saved == null) return kAllReportSections;
    final on = {
      for (final s in ReportSection.values)
        if (saved.contains(s.name)) s,
    };
    // An empty saved list would silently produce a title page and nothing else.
    return on.isEmpty ? kAllReportSections : on;
  }

  /// Ask which sections to include, offering the scale targets alongside, since
  /// they are what the ranking inside two of those sections is measured
  /// against. Returns null if the user cancelled the export.
  Future<Set<ReportSection>?> _askSections() async {
    final chosen = await showReportSectionsDialog(
      context,
      _sections,
      onEditTargets: _editScaleTargets,
    );
    if (chosen == null) return null;
    setState(() => _prefs.reportSections = [for (final s in chosen) s.name]);
    saveUserPrefs(_prefs);
    return chosen;
  }

  Future<void> _export() async {
    if (_authoring.rows.isEmpty) {
      _snack('Insert at least one block before exporting.');
      return;
    }
    await exportTsv();
  }

  /// Export this session as a one-subject BIDS dataset (zipped).
  ///
  /// The TSV on its own carries BIDS entities in its *name*; this is the tree
  /// those entities describe (`sub-XX/ses-YYYYMMDD/beh/` with the sidecar, a
  /// `dataset_description.json`, a `README`, `participants.tsv` and
  /// `scans.tsv`), which is what a validator and a colleague pooling several
  /// patients actually need.
  Future<void> _exportBids() async {
    if (_authoring.rows.isEmpty) {
      _snack('Insert at least one block before exporting.');
      return;
    }
    final Map<String, dynamic> contract;
    try {
      contract = await loadTsvContract();
    } catch (e) {
      if (mounted) _snack('BIDS export failed: $e');
      return;
    }
    if (!mounted) return;
    final rows = _authoring.rows;
    await countExport(
      () => exportBidsDataset(
        context,
        anchor: exportKey,
        avoid: exportAvoid,
        entries: [
          datasetEntry(
            name: _ids.name,
            tsv: _authoring.serialize(),
            contract: contract,
            kind: 'session_tsv',
            acqTime: rows.isEmpty ? '' : rows.first.acqTime,
          ),
        ],
      ),
    );
  }

  /// Build the session report in [format] and share it (mobile) or save it
  /// (desktop). Both formats are built from ONE [SessionReportData] and one
  /// section selection, so they cannot disagree about content.
  Future<void> _exportReport(_Leads leads, {required bool docx}) async {
    if (_authoring.rows.isEmpty) {
      _snack('Insert at least one block before exporting a report.');
      return;
    }
    final sections = await _askSections();
    if (sections == null || !mounted) return;
    final attestation = await askAttestation(context, rated: true);
    if (attestation == null || !mounted) return;

    // A report is a derivative, not raw data: `_report` is not a BIDS suffix.
    final l = _ids.name;
    final filename = l
        .withSuffix('report', extension: docx ? 'docx' : 'pdf')
        .filename;

    await exportFile(
      context,
      filename: filename,
      anchor: exportKey,
      avoid: exportAvoid,
      failureLabel: 'Report export failed',
      build: () async {
        final data = _reportData();
        // Only rasterise what the chosen sections will actually embed.
        final gfx = await renderReportGraphics(
          data,
          leads.left,
          sections,
          right: leads.right,
        );
        if (docx) {
          return (
            bytes: buildSessionDocx(
              data: data,
              subjectId: l.subject,
              electrodeImages: gfx.electrodes,
              chartPng: gfx.chart,
              pageSize: _reportLetter ? DocxPageSize.letter : DocxPageSize.a4,
              sections: sections,
              attestation: attestation,
            ),
            warning: null,
          );
        }
        final report = await buildSessionPdf(
          data: data,
          subjectId: l.subject,
          electrodeImages: gfx.electrodes,
          chartPng: gfx.chart,
          pageFormat: _reportLetter ? PdfPageFormat.letter : PdfPageFormat.a4,
          sections: sections,
          attestation: attestation,
        );
        return (
          bytes: report.bytes,
          // Silently altering a clinical note is worse than saying so.
          warning: report.lostCharacters
              ? 'Some characters could not be rendered in the PDF and were '
                    'replaced with "?". Add the IBM Plex fonts to assets/fonts/ '
                    'for full Unicode, or export to Word instead.'
              : null,
        );
      },
    );
  }

  /// The last step: what was recorded, then the exports grouped by reader.
  Widget _finishView(_Leads leads) {
    final configs = {
      for (final r in _authoring.rows)
        if (!isInitialValue(r.isInitial)) r.blockId,
    }.length;
    final leftOn = finalBlockIn(_authoring.rows);
    final saved = savedLocation;
    Widget action(IconData icon, String label, VoidCallback onTap) =>
        OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
        );
    return Column(
      key: exportKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GroupCard(
          title: 'Session summary',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Configurations tested: $configs'),
              Text(
                'Patient leaves on: '
                '${leftOn == null ? 'not recorded' : 'block $leftOn'}',
              ),
              if (saved != null) Text('Saved to: $saved'),
              if (savePathIsSandboxCopy)
                Text(
                  sandboxCopyNotice,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GroupCard(
          title: 'For the patient record',
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              action(
                Icons.picture_as_pdf,
                'Report (PDF)',
                () => _exportReport(leads, docx: false),
              ),
              action(
                Icons.description_outlined,
                'Report (Word)',
                () => _exportReport(leads, docx: true),
              ),
              DropdownButton<String>(
                value: _prefs.reportPageSize ?? kDefaultReportPageSize,
                items: [
                  for (final size in kReportPageSizes)
                    DropdownMenuItem(
                      value: size,
                      child: Text(size == 'letter' ? 'US Letter' : 'A4'),
                    ),
                ],
                onChanged: (size) {
                  if (size == null) return;
                  setState(() => _prefs.reportPageSize = size);
                  saveUserPrefs(_prefs);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GroupCard(
          title: 'For research',
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              action(Icons.table_chart_outlined, 'Raw data file', _export),
              action(
                Icons.folder_zip_outlined,
                'Research dataset (BIDS, zip)',
                _exportBids,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Two rows: the configuration (parameters beside electrodes) and the
  /// observations (scales beside notes), the observations first when
  /// [observationsFirst]. Narrow screens stack everything in one column.
  Widget _stepBody(
    Widget params,
    Widget electrodes,
    Widget scalesCard,
    Widget notes, {
    bool observationsFirst = false,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        Widget pair(Widget a, Widget b) => wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: a),
                  const SizedBox(width: 12),
                  Expanded(child: b),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [a, const SizedBox(height: 12), b],
              );
        final rows = [pair(params, electrodes), pair(scalesCard, notes)];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            observationsFirst ? rows[1] : rows[0],
            const Divider(height: 28, thickness: 1.2),
            observationsFirst ? rows[0] : rows[1],
          ],
        );
      },
    );
  }

  Future<void> _editDevices(ElectrodeCatalog catalog) async {
    final result = await showDevicesDialog(context, devices: catalog.devices);
    if (result == null || !mounted) return;
    setState(() => _prefs.devices = result);
    await saveUserPrefs(_prefs);
  }

  Widget _modelCard(ElectrodeCatalog catalog) {
    // ElectrodeView resets on model change; mirror it in every captured pair
    // of the side whose lead changed (initial and recording).
    void reset(List<_SideInputs> sides) {
      for (final s in sides) {
        s.states = {};
        s.caseState = ContactState.off;
      }
    }

    Widget menu(
      String label,
      Map<String, List<String>> groups, {
      String? value,
      TextEditingController? controller,
      bool enabled = true,
      ValueChanged<String>? onSelected,
    }) => DropdownMenu<String>(
      key: controller == null ? ValueKey('$label $value') : null,
      controller: controller,
      initialSelection: value,
      label: Text(label),
      enabled: enabled,
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      onSelected: (name) {
        if (name != null) onSelected?.call(name);
      },
      dropdownMenuEntries: [
        for (final group in groups.entries) ...[
          DropdownMenuEntry(
            value: '#${group.key}',
            label: group.key,
            enabled: false,
            labelWidget: Text(
              group.key,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          for (final name in group.value)
            DropdownMenuEntry(
              value: name,
              label: name,
              leadingIcon: const SizedBox(width: 12),
            ),
        ],
      ],
    );

    Widget sameBox(String title, bool value, ValueChanged<bool>? onChanged) =>
        CheckboxListTile(
          value: value,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(title),
          onChanged: onChanged == null ? null : (v) => onChanged(v ?? true),
        );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );

    final same = _rightModelName == null;
    final ipgLocked =
        sessionValueIn(_authoring.rows, (r) => r.leftIpgModel) != '';
    return GroupCard(
      title: 'Devices',
      action: IconButton(
        icon: const Icon(Icons.settings),
        tooltip: 'Devices settings',
        onPressed: () => _editDevices(catalog),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            heading('Leads'),
            menu(
              same ? 'Lead model' : 'Left lead model',
              catalog.manufacturers,
              value: _modelName,
              onSelected: (name) => setState(() {
                _modelName = name;
                reset(
                  same
                      ? [_leftInit, _rightInit, _leftRec, _rightRec]
                      : [_leftInit, _leftRec],
                );
              }),
            ),
            sameBox(
              'Same lead on both sides',
              same,
              (v) => setState(() => _rightModelName = v ? null : _modelName),
            ),
            if (!same)
              menu(
                'Right lead model',
                catalog.manufacturers,
                value: _rightModelName,
                onSelected: (name) => setState(() {
                  _rightModelName = name;
                  reset([_rightInit, _rightRec]);
                }),
              ),
            const Divider(height: 24),
            heading('Implanted pulse generator (IPG)'),
            menu(
              _sameIpg ? 'IPG model' : 'Left IPG model',
              catalog.ipgs,
              controller: _leftIpgCtrl,
              enabled: !ipgLocked,
            ),
            sameBox(
              'Same IPG on both sides',
              _sameIpg,
              ipgLocked ? null : (v) => setState(() => _sameIpg = v),
            ),
            if (!_sameIpg)
              menu(
                'Right IPG model',
                catalog.ipgs,
                controller: _rightIpgCtrl,
                enabled: !ipgLocked,
              ),
          ],
        ),
      ),
    );
  }

  /// A pick-only field offering [options], [locked] once the session's rows
  /// record a value.
  Widget _choiceField({
    required TextEditingController controller,
    required String label,
    required List<String> options,
    required bool locked,
    ValueChanged<String?>? onSelected,
  }) => DropdownMenu<String>(
    controller: controller,
    label: Text(label),
    enabled: !locked,
    expandedInsets: EdgeInsets.zero,
    requestFocusOnTap: false,
    onSelected: onSelected,
    dropdownMenuEntries: [
      for (final o in options) DropdownMenuEntry(value: o, label: o),
    ],
  );

  /// Both leads' models, the right falling back to the left when they match.
  _Leads _leads(ElectrodeCatalog catalog) => (
    left: _modelName == null ? null : catalog.models[_modelName],
    right: catalog.models[_rightModelName ?? _modelName],
  );

  /// Ask which recorded block the patient leaves on, defaulting to the one
  /// already marked, else the last, and write the choice into the file. False
  /// when cancelled.
  Future<bool> _confirmLeftOn() async {
    final blocks = <String, String>{};
    for (final r in _authoring.rows) {
      if (isInitialValue(r.isInitial)) continue;
      blocks.putIfAbsent(r.blockId, () => recordedTime(r.acqTime));
    }
    if (blocks.isEmpty) return true;
    final marked = finalBlockIn(_authoring.rows);
    var choice = marked ?? blocks.keys.last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Which configuration does the patient leave on?'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: RadioGroup<String>(
                groupValue: choice,
                onChanged: (v) => setState(() => choice = v ?? choice),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in blocks.entries)
                      RadioListTile<String>(
                        value: e.key,
                        dense: true,
                        title: Text('Block ${e.key}'),
                        subtitle: e.value.isEmpty ? null : Text(e.value),
                      ),
                    const RadioListTile<String>(
                      value: '',
                      dense: true,
                      title: Text('Not recorded'),
                      subtitle: Text(
                        'The report then shows the last configuration '
                        'recorded, and says so.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return false;
    final picked = choice.isEmpty ? null : choice;
    if (picked != marked) {
      setState(() => _authoring.markFinalBlock(picked));
      await autosave();
    }
    return true;
  }

  Widget _programCard() {
    final items = _programs;
    final value = items.contains(_selectedProgram) ? _selectedProgram : null;
    return GroupCard(
      title: 'Program',
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                isDense: true,
                hint: const Text('Select program'),
                items: [
                  for (final p in items)
                    DropdownMenuItem<String>(value: p, child: Text(p)),
                ],
                onChanged: (p) => setState(() => _selectedProgram = p),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 18),
            tooltip: 'Edit programs',
            onPressed: () => _editList('Programs', _programs, (l) {
              _prefs.programs = l;
              if (!l.contains(_selectedProgram)) _selectedProgram = null;
            }),
          ),
        ],
      ),
    );
  }

  /// Active cathode labels for [side] (from the encoded cathode string), which
  /// drive the amplitude-split rows.
  List<String> _cathodesFor(_SideInputs side, ElectrodeModel? model) {
    if (model == null) return const [];
    final cathode = encodeTokens(side.states, side.caseState, model).cathode;
    return cathode
        .split('_')
        .where((t) => t.isNotEmpty && t != 'case')
        .toList();
  }

  /// Column 1 item: one side's stim params + its amplitude split.
  Widget _paramsCard(
    String title,
    _SideInputs side,
    ElectrodeModel? model,
    StimLimits limits,
  ) {
    final card = GroupCard(
      title: side.enabled ? title : '$title (off)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StimParamsForm(
            limits: limits,
            frequency: side.freq,
            amplitude: side.amp,
            pulseWidth: side.pulseWidth,
          ),
          ListenableBuilder(
            listenable: side.amp,
            builder: (context, _) => AmplitudeSplit(
              cathodes: _cathodesFor(side, model),
              total: double.tryParse(side.amp.text.trim()) ?? 0,
              decimals: limits.amplitudeDecimals,
              initial: side.ampSplit,
              onChanged: (pct) => side.ampSplit = pct,
            ),
          ),
        ],
      ),
    );
    return Opacity(opacity: side.enabled ? 1 : 0.6, child: card);
  }

  /// Column 1: program + Left/Right param groups.
  Widget _paramsColumn(
    _Leads leads,
    StimLimits limits, {
    required _SideInputs left,
    required _SideInputs right,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _programCard(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Parameters',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.settings, size: 18),
              tooltip: 'Default settings per DBS indication',
              onPressed: () => _editStimDefaults(limits),
            ),
          ],
        ),
        _paramsCard('Left', left, leads.left, limits),
        const SizedBox(height: 12),
        _paramsCard('Right', right, leads.right, limits),
      ],
    );
  }

  /// Edit and keep the starting settings of each DBS indication.
  Future<void> _editStimDefaults(StimLimits limits) async {
    final presets = (await _contracts).$3;
    if (!mounted) return;
    final result = await showStimDefaultsDialog(
      context,
      limits: limits,
      indications: _prefs.pathologies ?? presets.pathologies,
    );
    if (result == null) return;
    setState(() => _prefs.stimDefaults = result);
    await saveUserPrefs(_prefs);
  }

  /// Desktop validation box: green "valid" or a red-bordered "invalid".
  Widget _validationBox(_SideInputs side) {
    final ok = side.validationError.isEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: ok
          ? null
          : BoxDecoration(
              border: Border.all(color: DbsColors.invalid, width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
      // An Icon, not a literal U+2713 in the string. A bare tick renders only
      // if the active font happens to carry that codepoint; on the platforms
      // this app targets it is often supplied by an OS fallback font, so it can
      // come out as an empty box. The icon font is bundled with the app.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 14,
            color: ok ? DbsColors.valid : DbsColors.invalid,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              ok ? 'Configuration valid' : 'Invalid: ${side.validationError}',
              style: TextStyle(
                color: ok ? DbsColors.valid : DbsColors.invalid,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One electrode pane: enable checkbox + the canvas (dimmed when disabled) +
  /// the validation box.
  Widget _electrodePane(String title, _SideInputs side, ElectrodeModel? model) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Checkbox(
              value: side.enabled,
              onChanged: (v) => setState(() => side.enabled = v ?? true),
            ),
            Text(title),
          ],
        ),
        SizedBox(
          // Grow with the window so maximizing enlarges the canvas (and its
          // contacts / ring caps, easing taps); floored for small screens.
          height: (MediaQuery.sizeOf(context).height * 0.55).clamp(
            320.0,
            900.0,
          ),
          child: model == null
              ? const Center(child: Text('Select an electrode model'))
              : Opacity(
                  opacity: side.enabled ? 1 : 0.3,
                  child: IgnorePointer(
                    ignoring: !side.enabled,
                    child: ElectrodeView(
                      model: model,
                      // Remounted on step switch; seed with captured config.
                      initialStates: side.states,
                      initialCaseState: side.caseState,
                      onChanged: (states, caseState) => setState(() {
                        side.states = states;
                        side.caseState = caseState;
                      }),
                      onValidation: (valid, error) => setState(
                        () => side.validationError = valid ? '' : error,
                      ),
                    ),
                  ),
                ),
        ),
        _validationBox(side),
      ],
    );
  }

  Widget _legend() {
    Widget swatch(Color base, Color border, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 12,
          decoration: BoxDecoration(
            color: base,
            border: Border.all(color: border),
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 4,
      children: [
        swatch(DbsColors.offBase, DbsColors.offBorder, 'Off'),
        swatch(DbsColors.anodicBase, DbsColors.anodicBorder, 'Anodic (+)'),
        swatch(
          DbsColors.cathodicBase,
          DbsColors.cathodicBorder,
          'Cathodic (-)',
        ),
      ],
    );
  }

  /// Column 2: the two electrode canvases side by side + legend.
  Widget _electrodesColumn(_Leads leads, _SideInputs left, _SideInputs right) {
    return GroupCard(
      title: 'Electrodes',
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _electrodePane('Left', left, leads.left)),
              const SizedBox(width: 8),
              Expanded(child: _electrodePane('Right', right, leads.right)),
            ],
          ),
          const SizedBox(height: 8),
          _legend(),
        ],
      ),
    );
  }

  /// The Notes field, given a generous viewport-relative height so it has real
  /// room. The Stepper scrolls when the column is taller than the window, so
  /// this never overflows on short desktop windows (`expands` needs the bounded
  /// box the SizedBox provides).
  Widget _notesField(TextEditingController notesCtrl) {
    return SizedBox(
      height: (MediaQuery.sizeOf(context).height * 0.3).clamp(180.0, 600.0),
      child: TextField(
        controller: notesCtrl,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: const InputDecoration(
          labelText: 'Notes',
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
      ),
    );
  }

  Widget _setupStep(
    ElectrodeCatalog catalog,
    ScalePresets presets,
    StimLimits limits,
  ) {
    final pathologies = _prefs.pathologies ?? presets.pathologies;
    final targets = _prefs.targets ?? presets.targets;
    final started = _started;
    const field = InputDecoration(border: OutlineInputBorder());
    Widget gear(String tooltip, VoidCallback onPressed) => IconButton(
      icon: const Icon(Icons.settings),
      tooltip: tooltip,
      onPressed: onPressed,
    );

    final session = GroupCard(
      title: 'Patient and session file',
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BidsNameFields(entries: _ids, decoration: field),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _newSession,
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('New session'),
                ),
                OutlinedButton.icon(
                  onPressed: openFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open saved session'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  started ? Icons.check_circle_outline : Icons.info_outline,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    started
                        ? 'Session started: ${_ids.name.filename}'
                        : 'Enter the patient ID, then start a new session '
                              'or open a saved one.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final clinical = GroupCard(
      title: 'Clinical details',
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _choiceField(
                    controller: _pathologyCtrl,
                    label: 'DBS indication',
                    options: pathologies,
                    locked:
                        sessionValueIn(_authoring.rows, (r) => r.pathology) !=
                        '',
                    onSelected: (p) {
                      if (p == null) return;
                      setState(() {});
                      if (_selectedClinicalPreset == null &&
                          presets.buttons.contains(p)) {
                        _applyClinicalPreset(p, presets, limits);
                      }
                    },
                  ),
                ),
                gear(
                  'Edit DBS indications',
                  () => _editList(
                    'DBS indications',
                    pathologies,
                    (l) => _prefs.pathologies = l,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _choiceField(
                    controller: _targetCtrl,
                    label: 'Anatomical target',
                    options: targets,
                    locked:
                        sessionValueIn(_authoring.rows, (r) => r.target) != '',
                  ),
                ),
                gear(
                  'Edit targets',
                  () => _editList(
                    'Anatomical targets',
                    targets,
                    (l) => _prefs.targets = l,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 900) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              session,
              const SizedBox(height: 16),
              clinical,
              const SizedBox(height: 16),
              _modelCard(catalog),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: session),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  clinical,
                  const SizedBox(height: 16),
                  _modelCard(catalog),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Load the session pathology's clinical scales and ratings.
  void _applyClinicalPreset(
    String preset,
    ScalePresets presets,
    StimLimits limits,
  ) {
    setState(() {
      _selectedClinicalPreset = preset;
      _addClinicalScales(preset, presets);
      _loadSessionPresetRows(preset, presets, limits);
    });
  }

  /// Add a group's clinical scales, skipping names already listed. Call
  /// inside setState.
  void _addClinicalScales(String group, ScalePresets presets) {
    final listed = {for (final s in _clinicalScales) s.name.text.trim()};
    for (final name in clinicalRows(presets, group)) {
      if (listed.add(name)) {
        _clinicalScales.add(_ClinicalScaleEdit()..name.text = name);
      }
    }
  }

  /// Load the scales of the pathology recorded in an opened file.
  Future<void> _loadPathologyScales() async {
    final pathology = _pathologyCtrl.text.trim();
    if (pathology.isEmpty || _selectedClinicalPreset != null) return;
    final (_, limits, raw) = await _contracts;
    final presets = mergeScalePresets(raw, _prefs);
    if (mounted && presets.buttons.contains(pathology)) {
      _applyClinicalPreset(pathology, presets, limits);
    }
  }

  /// A "+" menu with one submenu per pathology, the session's own first, in
  /// which a ticked scale is one currently listed; ticking adds it, unticking
  /// removes it. [onEmpty] adds a blank row.
  Widget _addScalesMenu({
    required ScalePresets presets,
    required String tooltip,
    required List<String> Function(String group) namesOf,
    required bool Function(String name) listed,
    required void Function(String group, String name, bool on) onToggle,
    VoidCallback? onEmpty,
  }) {
    final own = _selectedClinicalPreset;
    final groups = [
      if (own != null && presets.buttons.contains(own)) own,
      for (final g in presets.buttons)
        if (g != own) g,
    ];
    return MenuAnchor(
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Icons.add),
        tooltip: tooltip,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        for (final g in groups)
          SubmenuButton(
            menuChildren: [
              for (final name in namesOf(g))
                CheckboxMenuButton(
                  value: listed(name),
                  closeOnActivate: false,
                  onChanged: (on) =>
                      setState(() => onToggle(g, name, on ?? false)),
                  child: Text(name),
                ),
            ],
            child: Text('Scales for $g'),
          ),
        if (onEmpty != null) ...[
          const Divider(height: 8),
          MenuItemButton(
            onPressed: onEmpty,
            child: const Text('One empty scale'),
          ),
        ],
      ],
    );
  }

  /// Edit + persist the clinical scale presets via the desktop-style group
  /// editor (all disease groups → scale names). [presets] is the effective
  /// (defaults + overrides) set; the result replaces `UserPrefs.clinical` and
  /// is merged live via mergeScalePresets in build().
  Future<void> _editClinicalPresets(ScalePresets presets) async {
    final edited = await showClinicalPresetsDialog(
      context,
      presets: presets.clinical,
      ranges: presets.clinicalRanges,
    );
    if (edited == null) return;
    setState(() {
      _prefs.clinical = edited.groups;
      _prefs.clinicalRanges = edited.ranges;
    });
    await saveUserPrefs(_prefs);
    final (_, _, raw) = await _contracts;
    if (!mounted) return;
    final pathology = _selectedClinicalPreset;
    if (pathology != null) {
      setState(
        () => _addClinicalScales(pathology, mergeScalePresets(raw, _prefs)),
      );
    }
    _snack('Clinical scale presets saved.');
  }

  /// Edit and persist the session scale presets via the group editor: all
  /// disease groups, (name,min,max) rows, report mode preserved.
  Future<void> _editSessionPresets(ScalePresets presets) async {
    final edited = await showSessionPresetsDialog(
      context,
      presets: presets.session,
    );
    if (edited == null) return;
    setState(() => _prefs.session = edited);
    await saveUserPrefs(_prefs);
    final (_, limits, raw) = await _contracts;
    if (!mounted) return;
    final pathology = _selectedClinicalPreset;
    if (pathology != null) {
      setState(
        () => _loadSessionPresetRows(
          pathology,
          mergeScalePresets(raw, _prefs),
          limits,
        ),
      );
    }
    _snack('Session scale presets saved.');
  }

  Widget _clinicalScalesCard(ScalePresets presets, StimLimits limits) {
    return Card(
      color: DbsColors.assessmentFill(
        Theme.of(context).brightness == Brightness.dark,
      ),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Clinical scales',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings clinical scales',
                  onPressed: () => _editClinicalPresets(presets),
                ),
                _addScalesMenu(
                  presets: presets,
                  tooltip: 'Add clinical scales',
                  namesOf: (g) => clinicalRows(presets, g),
                  listed: (name) =>
                      _clinicalScales.any((s) => s.name.text.trim() == name),
                  onToggle: (_, name, on) {
                    if (on) {
                      _clinicalScales.add(
                        _ClinicalScaleEdit()..name.text = name,
                      );
                      return;
                    }
                    final gone = _clinicalScales
                        .where((s) => s.name.text.trim() == name)
                        .toList();
                    _clinicalScales.removeWhere(gone.contains);
                    _removedClinical.addAll(gone);
                  },
                  onEmpty: () =>
                      setState(() => _clinicalScales.add(_ClinicalScaleEdit())),
                ),
              ],
            ),
            for (final scale in _clinicalScales)
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: scale.name,
                      decoration: const InputDecoration(
                        labelText: 'Scale name',
                        isDense: true,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: TextField(
                        controller: scale.score,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Score',
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Remove clinical scale',
                    onPressed: () => setState(() {
                      _clinicalScales.remove(scale);
                      _removedClinical.add(scale);
                    }),
                  ),
                ],
              ),
            if (_clinicalScales.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No scales. The insert writes one scale-less '
                  'row (like the desktop).',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _initialStep(StimLimits limits, ScalePresets presets, _Leads leads) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DbsColors.assessmentFill(
          Theme.of(context).brightness == Brightness.dark,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _phaseHint(
              'How the patient is on arrival, before any change. '
              'Saved when you press Next.',
            ),
            _stepBody(
              _paramsColumn(leads, limits, left: _leftInit, right: _rightInit),
              _electrodesColumn(leads, _leftInit, _rightInit),
              _clinicalScalesCard(presets, limits),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _medicationsCtrl,
                    minLines: 3,
                    maxLines: null,
                    decoration: const InputDecoration(
                      labelText: 'Medications',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _notesField(_notesInitCtrl),
                ],
              ),
              observationsFirst: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _phaseHint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );

  /// Add a group's rating rows, and refresh the range, step and target of rows
  /// already listed under the same name. Call inside setState.
  void _loadSessionPresetRows(
    String preset,
    ScalePresets presets,
    StimLimits limits,
  ) {
    final fallback = limits.sessionScale;
    final listed = {for (final s in _sessionScales) s.name.text.trim(): s};
    for (final row in sessionRows(presets, preset)) {
      final min = double.tryParse(row.min) ?? fallback.min;
      final max = double.tryParse(row.max) ?? fallback.max;
      if (listed[row.name] case final s?) {
        s.minCtrl.text = _fmtValue(min);
        s.maxCtrl.text = _fmtValue(max);
        s.mode = scaleModeFromString(row.mode);
        s.step = double.tryParse(row.step);
        continue;
      }
      _sessionScales.add(_sessionScaleFrom(row, limits));
    }
  }

  _SessionScaleEdit _sessionScaleFrom(SessionScaleRow row, StimLimits limits) =>
      _SessionScaleEdit(
        min: double.tryParse(row.min) ?? limits.sessionScale.min,
        max: double.tryParse(row.max) ?? limits.sessionScale.max,
        name: row.name,
        mode: scaleModeFromString(row.mode),
        step: double.tryParse(row.step),
      );

  /// One rating row: name, a bar bounded by the scale's min/max, and the
  /// not-assessed switch, written as the contract's omitted literal.
  Widget _ratingRow(_SessionScaleEdit scale, StimLimits limits) {
    final min = scale.minOr(limits.sessionScale.min);
    var max = scale.maxOr(limits.sessionScale.max);
    if (max <= min) max = min + 1;
    final name = scale.name.text.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(name.isEmpty ? '(unnamed scale)' : name),
          ),
          Expanded(
            flex: 5,
            child: ScaleSlider(
              value: scale.value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              step: scale.step ?? 0.25,
              omitted: scale.omitted,
              onChanged: (v) => setState(() {
                scale.value = v;
                scale.omitted = false;
              }),
              onOmitToggle: () =>
                  setState(() => scale.omitted = !scale.omitted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ratingsCard(StimLimits limits, ScalePresets presets) {
    return Card(
      // Warm fill + outline to match GroupCard (dark-safe; no M3 blue).
      color: DbsColors.cardFill(
        Theme.of(context).brightness == Brightness.dark,
      ),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ratings for this configuration',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings session scales',
                  onPressed: () => _editSessionPresets(presets),
                ),
                _addScalesMenu(
                  presets: presets,
                  tooltip: 'Add ratings',
                  namesOf: (g) => [
                    for (final r in sessionRows(presets, g)) r.name,
                  ],
                  listed: (name) =>
                      _sessionScales.any((s) => s.name.text.trim() == name),
                  onToggle: (g, name, on) {
                    if (on) {
                      _sessionScales.add(
                        _sessionScaleFrom(
                          sessionRows(
                            presets,
                            g,
                          ).firstWhere((r) => r.name == name),
                          limits,
                        ),
                      );
                      return;
                    }
                    final gone = _sessionScales
                        .where((s) => s.name.text.trim() == name)
                        .toList();
                    _sessionScales.removeWhere(gone.contains);
                    _removedSession.addAll(gone);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_sessionScales.isEmpty)
              const Text(
                'No ratings yet. Choose the pathology in Setup, or add '
                'ratings with +.',
              )
            else
              for (final scale in _sessionScales) _ratingRow(scale, limits),
          ],
        ),
      ),
    );
  }

  /// Review table of every inserted TSV row (one row per scale), so the user
  /// can check what has been recorded instead of only the transient snackbars.
  Widget _recordingStep(
    ElectrodeCatalog catalog,
    StimLimits limits,
    ScalePresets presets,
    _Leads leads,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _phaseHint('Test configurations and rate each one.'),
        _stepBody(
          _paramsColumn(leads, limits, left: _leftRec, right: _rightRec),
          _electrodesColumn(leads, _leftRec, _rightRec),
          _ratingsCard(limits, presets),
          _notesField(_notesRecCtrl),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: _starNext,
          onChanged: (v) => setState(() => _starNext = v),
          secondary: Icon(_starNext ? Icons.star : Icons.star_border),
          title: const Text('Star this configuration'),
          subtitle: const Text(
            'Marks it as particularly good. Any number can be starred, '
            'earlier ones too, from the table below.',
          ),
        ),
        SwitchListTile(
          value: _leavesOn,
          onChanged: (v) => setState(() => _leavesOn = v),
          title: const Text('Patient leaves on this'),
          subtitle: const Text(
            'Marks this block as the configuration the patient goes home with. '
            'Confirmed when the session ends.',
          ),
        ),
        FilledButton.icon(
          onPressed: () => _insertRecording(catalog, limits),
          icon: const Icon(Icons.add),
          label: const Text('Save configuration'),
        ),
        const Divider(height: 32),
        Row(
          children: [
            Expanded(
              child: Text(
                'Inserted entries (append ${_authoring.appendId})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _editScaleTargets,
              icon: const Icon(Icons.adjust, size: 18),
              label: const Text('Scale targets'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Column(
            children: [
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: _prefs.entryChartsExpanded ?? false,
                onExpansionChanged: (open) {
                  _prefs.entryChartsExpanded = open;
                  saveUserPrefs(_prefs);
                },
                title: Text(
                  'Comparison charts',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                children: [
                  EntryChartsView(
                    data: _entryCharts(),
                    order: _prefs.entryPanelOrder,
                    onOrderChanged: (ids) {
                      setState(() => _prefs.entryPanelOrder = ids);
                      saveUserPrefs(_prefs);
                    },
                    visibleConfigs:
                        _prefs.entryVisibleConfigs ?? kDefaultVisibleConfigs,
                    onVisibleConfigsChanged: (n) {
                      setState(() => _prefs.entryVisibleConfigs = n);
                      saveUserPrefs(_prefs);
                    },
                    bestXs: _entryCharts().bestXs,
                    secondXs: _entryCharts().secondXs,
                  ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: _prefs.entryTableExpanded ?? true,
                onExpansionChanged: (open) {
                  _prefs.entryTableExpanded = open;
                  saveUserPrefs(_prefs);
                },
                title: Text(
                  'Table of all entries '
                  '(${blockCount(_authoring.rows)} blocks)',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  SessionEntriesTable(
                    rows: _authoring.rows,
                    onToggleStar: _toggleStar,
                    bestBlocks: _entryCharts().bestXs,
                    secondBlocks: _entryCharts().secondXs,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop) await leaveOnBack();
    },
    child: _page(context),
  );

  Widget _page(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete workflow'),
        actions: const [TextSizeButtons(), HelpButton(), ThemeToggleButton()],
      ),
      body: FutureBuilder<(ElectrodeCatalog, StimLimits, ScalePresets)>(
        future: _contracts,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Could not load schema contracts: '
                '${snapshot.error}',
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (rawCatalog, rawLimits, rawPresets) = snapshot.data!;
          final catalog = rawCatalog.withDevices(_prefs.devices);
          final limits = rawLimits.withDefaults(_prefs.stimDefaults);
          final presets = mergeScalePresets(rawPresets, _prefs);
          final leads = _leads(catalog);
          // Only the active step builds its (heavy) content: keeps one
          // ElectrodeView / one Notes field per side in the tree at a time,
          // so state lives in _SessionScreenState, not in step widgets.
          Widget when(int step, Widget Function() builder) =>
              _currentStep == step ? builder() : const SizedBox.shrink();
          final contents = <Widget Function()>[
            () => _setupStep(catalog, presets, limits),
            () => _initialStep(limits, presets, leads),
            () => _recordingStep(catalog, limits, presets, leads),
            () => _finishView(leads),
          ];
          final l = _ids.name;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_currentStep > 0)
                SessionStrip(
                  parts: [
                    'Patient ${l.subject}',
                    'Run ${l.run}',
                    for (final detail in [
                      _sessionDetails.pathology,
                      _sessionDetails.target,
                    ])
                      if (detail.isNotEmpty) detail,
                    if (_modelName case final left?)
                      'Lead $left'
                          '${_rightModelName == null ? '' : ' / $_rightModelName'}',
                    if (_sessionDetails.leftIpg.isNotEmpty)
                      _sessionDetails.rightIpg == _sessionDetails.leftIpg
                          ? 'IPG ${_sessionDetails.leftIpg}'
                          : 'IPG ${_sessionDetails.leftIpg} / '
                                '${_sessionDetails.rightIpg}',
                  ],
                  onTap: () => _goTo(0),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => Stepper(
                    type: c.maxWidth >= 900
                        ? StepperType.horizontal
                        : StepperType.vertical,
                    currentStep: _currentStep,
                    onStepTapped: _goTo,
                    controlsBuilder: (context, details) =>
                        const SizedBox.shrink(),
                    steps: [
                      for (var i = 0; i < contents.length; i++)
                        Step(
                          title: Text(_stepNames[i]),
                          isActive: _currentStep == i,
                          content: when(i, contents[i]),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: StepControls(
        label: _stepNames[_currentStep],
        onBack: _currentStep > 0 ? () => _goTo(_currentStep - 1) : null,
        onNext: _currentStep < _finishStep
            ? () => _goTo(_currentStep + 1)
            : null,
      ),
    );
  }
}

/// The left and right leads' models; either is null when none is selected.
typedef _Leads = ({ElectrodeModel? left, ElectrodeModel? right});
