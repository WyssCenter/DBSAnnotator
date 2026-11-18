/// The patient browser of the Session step: the chosen patient's visits in the
/// BIDS folder, what can be made from the ones chosen, and their preview.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';

import '../app_info.dart';
import '../core/annotation.dart';
import '../core/bids.dart';
import '../core/bids_dataset.dart';
import '../core/bids_merge.dart';
import '../core/bids_sidecar.dart';
import '../core/electrode/electrode_model.dart';
import '../core/prefs/user_prefs.dart';
import '../core/session/aggregate.dart';
import '../core/session/longitudinal.dart';
import '../core/session/scale_scoring.dart';
import '../core/session/session_row.dart';
import '../core/session/tsv_kind.dart';
import '../core/timestamps.dart';
import '../report/attestation.dart';
import '../report/entry_charts.dart';
import '../report/longitudinal_data.dart';
import '../report/longitudinal_pdf.dart';
import '../report/longitudinal_sections.dart';
import '../report/report_data.dart';
import '../report/report_sections.dart';
import '../report/session_docx.dart';
import '../report/session_pdf.dart';
import '../report/upload_actions.dart';
import 'bids_export.dart';
import 'bids_merge_ui.dart';
import 'report_action_row.dart';
import 'report_images.dart';
import 'report_sections_dialog.dart';
import 'save_target.dart';
import 'scale_targets_dialog.dart';
import 'scales_chart_painter.dart';
import 'session/entries_table.dart';
import 'session/entry_charts_view.dart';
import 'share_util.dart';
import 'theme.dart';
import 'visit_list.dart';
import 'preview_parts.dart';

class ImportExportPanel extends StatefulWidget {
  const ImportExportPanel({
    super.key,
    this.catalog,
    this.initialFiles,
    this.folder,
    this.patient,
    this.prefs,
    this.leading,
  });

  /// Injected by tests and the screenshot build, which have no asset bundle.
  final ElectrodeCatalog? catalog;
  final List<Uploaded>? initialFiles;

  /// The BIDS folder chosen on the Session step, the one the visits come from.
  final String? folder;

  /// The patient whose visits are listed, or [kAllPatients].
  final String? patient;

  /// The screen's preferences, shared so that neither copy saves over the other.
  final UserPrefs? prefs;

  /// Shown above the visit list.
  final Widget? leading;

  @override
  State<ImportExportPanel> createState() => _ImportExportPanelState();
}

class _ImportExportPanelState extends State<ImportExportPanel> {
  late List<Uploaded> _visits = chronological(widget.initialFiles ?? []);
  late String? _run = _visits.length == 1 ? _visits.single.name : null;
  bool _loading = false;
  int _loads = 0;
  bool _stacked = false;
  final _exportKey = GlobalKey();
  final _previewKey = GlobalKey();
  final _revision = ValueNotifier(0);
  int _visibleConfigs = kDefaultVisibleConfigs;
  Map<String, (double, double)> _ranges = const {};

  ElectrodeCatalog? _catalog;
  UserPrefs _ownPrefs = UserPrefs();
  List<ScalePref>? _targets;
  Set<ReportSection> _sections = kAllReportSections;

  /// The dataset folder files were loaded from, and their names: the combined
  /// table goes back into it only when every session came from there.
  ({String root, Set<String> names})? _datasetSource;

  @override
  void initState() {
    super.initState();
    _catalog = widget.catalog;
    if (_catalog == null) {
      loadElectrodeCatalog().then(
        (c) {
          if (mounted) setState(() => _catalog = c);
        },
        onError: (Object e) => debugPrint('Electrode catalog unavailable: $e'),
      );
    }
    if (widget.prefs == null) {
      loadUserPrefs().then((p) {
        if (mounted) setState(() => _ownPrefs = p);
      });
    }
    if (widget.initialFiles == null) _load();
    clinicalRanges(_prefs).then((r) {
      if (mounted) _changed(() => _ranges = r);
    });
  }

  @override
  void dispose() {
    _revision.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ImportExportPanel old) {
    super.didUpdateWidget(old);
    if (old.folder != widget.folder || old.patient != widget.patient) _load();
  }

  UserPrefs get _prefs => widget.prefs ?? _ownPrefs;

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  List<Uploaded> get _files => [
    for (final f in _visits)
      if (_run == null || f.name == _run) f,
  ];

  List<Uploaded> get _sessions =>
      _files.where((f) => f.kind == TsvKind.programming).toList();

  List<SessionRow> get _rows =>
      _sessions.isEmpty ? const [] : _sessions.single.rows;

  List<Annotation> get _notes => [
    for (final f in _files)
      if (f.kind == TsvKind.notes) ...f.notes,
  ];

  bool get _letter =>
      (_prefs.reportPageSize ?? kDefaultReportPageSize) == 'letter';

  Future<void> _load() async {
    final root = widget.folder;
    final patient = widget.patient;
    final load = ++_loads;
    _visits = const [];
    _run = null;
    _targets = null;
    _datasetSource = null;
    _loading = root != null && patient != null;
    if (root == null || patient == null) return;
    final ({List<Uploaded> visits, List<String> rejected}) found;
    try {
      found = await folderVisits(root, patient);
    } catch (e) {
      if (!mounted || load != _loads) return;
      setState(() => _loading = false);
      _snack('Could not read that folder: $e');
      return;
    }
    if (!mounted || load != _loads) return;
    setState(() {
      _visits = found.visits;
      _run = _visits.length == 1 ? _visits.single.name : null;
      _datasetSource = _visits.isEmpty
          ? null
          : (root: root, names: {for (final f in _visits) f.name});
      _loading = false;
    });
    if (found.rejected.isNotEmpty) _snack(found.rejected.join('; '));
  }

  void _select(String? run) {
    setState(() {
      _run = run;
      _targets = null;
    });
    if (!_stacked) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final preview = _previewKey.currentContext;
      if (preview != null && preview.mounted) {
        Scrollable.ensureVisible(
          preview,
          duration: const Duration(milliseconds: 300),
        );
      }
    });
  }

  String get _title {
    if (_run != null) {
      final f = _files.single;
      return '${visitLabel(f)}, ${runLabel(f)}';
    }
    final subjects = {
      for (final f in _visits) BidsName.parse(f.name)?.subject ?? '',
    };
    return subjects.length == 1 && subjects.single.isNotEmpty
        ? 'All visits of sub-${subjects.single}'
        : 'All visits';
  }

  /// The targets set, else the defaults the targets dialog offers, so a
  /// longitudinal report is ranked even when the dialog was not confirmed.
  List<ScalePref> get _targetsOrDefault =>
      _targets ??
      defaultScalePrefsFor([
        for (final f in _sessions)
          ...f.rows.where((r) => coerceInt(r.isInitial) != 1),
      ]);

  Future<void> _editTargets() async {
    final seed = _targetsOrDefault;
    if (seed.isEmpty) {
      _snack('The chosen files have no session scale ratings to rank.');
      return;
    }
    final updated = await showScaleTargetsDialog(context, seed);
    if (updated != null && mounted) _changed(() => _targets = updated);
  }

  void _changed(VoidCallback fn) {
    setState(fn);
    _revision.value++;
  }

  Future<void> _enlarge() => showEnlarged(
    context,
    title: _title,
    body: (context) => ValueListenableBuilder(
      valueListenable: _revision,
      builder: (context, _, _) => _preview(Theme.of(context), enlarged: true),
    ),
  );

  String? _warn(bool lost) => lost
      ? 'Some characters could not be rendered in the PDF and were replaced '
            'with "?". Add the IBM Plex fonts to assets/fonts/ for full '
            'Unicode, or export to Word instead.'
      : null;

  // ---- Actions ----

  String get _source => _sessions.single.name;

  /// The source TSV's name without its suffix, the stem of its report.
  String get _reportBase => _source
      .replaceAll(RegExp(r'\.tsv$'), '')
      .replaceAll(
        RegExp('_(${BidsName.behSuffix}|${BidsName.legacySuffix})\$'),
        '',
      );

  /// The sections to render. Null when cancelled.
  Future<Set<ReportSection>?> _askSessionSections() async {
    final sections = await showReportSectionsDialog(
      context,
      _sections,
      onEditTargets: _editTargets,
    );
    if (sections != null && mounted) setState(() => _sections = sections);
    return sections;
  }

  Future<ExportPayload> _buildSessionReport({
    required bool docx,
    required Set<ReportSection> sections,
    required ReportAttestation attestation,
  }) async {
    final subject = BidsName.parse(_source)?.subject ?? 'unknown';
    final data = buildSessionReportData(
      rows: _rows,
      scalePrefs: _targets,
      sourceFile: _source,
    );
    final gfx = await renderReportGraphics(
      data,
      _catalog?.withDevices(_prefs.devices).models[electrodeModelIn(_rows)],
      sections,
      right: _catalog
          ?.withDevices(_prefs.devices)
          .models[electrodeModelIn(_rows, right: true)],
    );
    if (docx) {
      return (
        bytes: buildSessionDocx(
          data: data,
          subjectId: subject,
          electrodeImages: gfx.electrodes,
          chartPng: gfx.chart,
          pageSize: _letter ? DocxPageSize.letter : DocxPageSize.a4,
          sections: sections,
          attestation: attestation,
        ),
        warning: null,
      );
    }
    final report = await buildSessionPdf(
      data: data,
      subjectId: subject,
      electrodeImages: gfx.electrodes,
      chartPng: gfx.chart,
      pageFormat: _letter ? PdfPageFormat.letter : PdfPageFormat.a4,
      sections: sections,
      attestation: attestation,
    );
    return (bytes: report.bytes, warning: _warn(report.lostCharacters));
  }

  Future<void> _sessionReport({required bool docx}) async {
    final sections = await _askSessionSections();
    if (sections == null || !mounted) return;
    final attestation = await askAttestation(context, rated: true);
    if (attestation == null || !mounted) return;
    await exportFile(
      context,
      filename: '${_reportBase}_report.${docx ? 'docx' : 'pdf'}',
      anchor: _exportKey,
      failureLabel: 'Report export failed',
      initialDirectory: reportFolderFor(
        _prefs,
        root: _datasetSource?.root,
        subject: BidsName.parse(_source)?.subject ?? '',
      ),
      onSaved: (path) => rememberReportFolder(_prefs, path),
      build: () => _buildSessionReport(
        docx: docx,
        sections: sections,
        attestation: attestation,
      ),
    );
  }

  /// File the one uploaded TSV, its report, or both into a dataset.
  Future<void> _addSingleToDataset() async {
    final choice = await askSingleSessionAdd(context);
    if (choice == null || !mounted) return;

    ExportPayload? report;
    if (choice.report) {
      final sections = await _askSessionSections();
      if (sections == null || !mounted) return;
      final attestation = await askAttestation(context, rated: true);
      if (attestation == null || !mounted) return;
      try {
        report = await _buildSessionReport(
          docx: choice.docx,
          sections: sections,
          attestation: attestation,
        );
      } catch (e) {
        if (mounted) _snack('Report export failed: $e');
        return;
      }
    }
    if (!mounted) return;
    await _addToDataset(
      inPlace: canWriteChosenFolder,
      tsv: choice.tsv,
      report: report == null
          ? null
          : (
              bytes: Uint8List.fromList(report.bytes),
              extension: choice.docx ? 'docx' : 'pdf',
              warning: report.warning,
            ),
    );
  }

  Future<Uint8List?> _chartPng(ScalesChartSpec spec) async {
    if (spec.isEmpty) return null;
    try {
      return await renderScalesChartPng(spec);
    } catch (e) {
      debugPrint('Longitudinal figure could not be rendered: $e');
      return null;
    }
  }

  Future<void> _longitudinalReport({required bool docx}) async {
    // The desktop asks for both before exporting, and it has to: a TSV carries
    // no record of the targets used when its own report was made.
    // The defaults every time, not the last export's choice, so a heavy
    // section ticked once is not carried into every later report. Notes
    // print only in the session tables, so with a notes file that section
    // starts ticked.
    final sections = await showLongitudinalSectionsDialog(context, {
      ...kDefaultLongitudinalSections,
      if (_notes.isNotEmpty) LongitudinalSection.sessionTable,
    }, onEditTargets: _editTargets);
    if (sections == null || !mounted) return;
    final attestation = await askAttestation(context, rated: true);
    if (attestation == null || !mounted) return;

    final ranges = await clinicalRanges(_prefs);
    if (!mounted) return;
    final data = buildLongitudinalReportData(
      clinicalRanges: ranges,
      files: {for (final f in _sessions) f.name: f.rows},
      notes: _notes,
      noteFilenames: [
        for (final f in _files)
          if (f.kind == TsvKind.notes) f.name,
      ],
      scalePrefs: _targetsOrDefault,
    );
    if (data.isEmpty && data.notesWithoutVisit.isEmpty) {
      _snack('The chosen files contain no visits or notes to report.');
      return;
    }
    // The creation date goes inside the desc- label: BIDS wants the suffix
    // last, and two reports of one patient must not share a name.
    final name =
        'sub-${BidsName.label(data.patientId)}'
        '_desc-longitudinal${data.generatedOn.replaceAll('-', '')}'
        '_report.${docx ? 'docx' : 'pdf'}';

    await exportFile(
      context,
      filename: name,
      anchor: _exportKey,
      failureLabel: 'Report export failed',
      initialDirectory: reportFolderFor(
        _prefs,
        root: _datasetSource?.root,
        subject: data.patientId,
      ),
      onSaved: (path) => rememberReportFolder(_prefs, path),
      build: () async {
        final clinical = await _chartPng(data.clinicalChart);
        final session = await _chartPng(data.sessionChart);
        // Four leads a visit, so this is rendered only when asked for.
        final leads = <String, ElectrodeReportImages>{};
        if (sections.contains(LongitudinalSection.electrodes)) {
          for (final visit in data.visits) {
            final rows = _sessions
                .firstWhere((f) => f.name == visit.filename)
                .rows;
            final gfx = await renderReportGraphics(
              visit.session,
              _catalog?.withDevices(_prefs.devices).models[electrodeModelIn(
                rows,
              )],
              const {ReportSection.electrodes},
              right: _catalog
                  ?.withDevices(_prefs.devices)
                  .models[electrodeModelIn(rows, right: true)],
            );
            if (gfx.electrodes != null) leads[visit.filename] = gfx.electrodes!;
          }
        }
        if (docx) {
          return (
            bytes: buildLongitudinalDocx(
              data: data,
              clinicalChartPng: clinical,
              sessionChartPng: session,
              electrodeImages: leads,
              pageSize: _letter ? DocxPageSize.letter : DocxPageSize.a4,
              sections: sections,
              attestation: attestation,
            ),
            warning: null,
          );
        }
        final report = await buildLongitudinalPdf(
          data: data,
          clinicalChartPng: clinical,
          sessionChartPng: session,
          electrodeImages: leads,
          pageFormat: _letter ? PdfPageFormat.letter : PdfPageFormat.a4,
          sections: sections,
          attestation: attestation,
        );
        return (bytes: report.bytes, warning: _warn(report.lostCharacters));
      },
    );
  }

  Future<void> _exportAggregate() async {
    final out = buildAggregate(aggregateSources(_files));
    if (out.rowCount == 0) {
      _snack(
        out.skipped.isEmpty
            ? 'The chosen files contain no rows to combine.'
            : 'No chosen file carries BIDS entities in its name.',
      );
      return;
    }
    if (out.skipped.isNotEmpty) {
      _snack(
        'Left out: '
        '${out.skipped.map((s) => '${s.filename}: ${s.reason}').join('; ')}',
      );
    }
    final String sidecar;
    try {
      sidecar = aggregateSidecarJson(
        await loadTsvContract(),
        appVersion: appVersion,
        scaleColumns: out.scaleNames,
      );
    } catch (e) {
      if (mounted) _snack('Combined table export failed: $e');
      return;
    }
    final summary = describeAggregate(out);

    final source = _datasetSource;
    if (!mounted) return;
    if (source != null && _files.every((f) => source.names.contains(f.name))) {
      try {
        final copy = await saveAggregateInto(
          context,
          source.root,
          tsv: out.tsv,
          sidecar: sidecar,
          summary: summary,
        );
        if (!copy) return;
      } catch (e) {
        if (mounted) _snack('Could not save into the BIDS folder: $e');
        return;
      }
    } else if (source != null) {
      _snack(
        'Not saved into the BIDS folder: some of these files were not read '
        'from it.',
      );
    }
    if (!mounted) return;

    // The table and the sidecar that documents its columns travel together.
    final stem = out.subjects.length == 1
        ? '${out.subjects.single}_$aggregateStem'
        : 'study_$aggregateStem';
    await exportFile(
      context,
      filename: '$stem.zip',
      anchor: _exportKey,
      failureLabel: 'Combined table export failed',
      build: () async => (
        bytes: textZip({'$stem.tsv': out.tsv, '$stem.json': sidecar}),
        warning: null,
      ),
    );
    if (mounted) _snack('$summary.');
  }

  /// Fold the uploaded files into a BIDS dataset the user already has.
  ///
  /// The plan is shown and confirmed before a byte is written: this is the one
  /// action here that touches data the app did not create, and it has no undo.
  ///
  /// [tsv] false files only the [report], beside the visit's own path.
  Future<void> _addToDataset({
    required bool inPlace,
    bool tsv = true,
    ({Uint8List bytes, String extension, String? warning})? report,
  }) async {
    final Map<String, dynamic> contract;
    try {
      contract = await loadTsvContract();
    } catch (e) {
      if (mounted) _snack('Could not read the TSV contract: $e');
      return;
    }
    final built = datasetFromUploads(_files, contract);
    if (built.files.isEmpty) {
      if (mounted) {
        _snack('No chosen file carries BIDS entities in its name.');
      }
      return;
    }

    // Writing into the folder, or reading a zip and giving a merged one back.
    final target = inPlace ? await _pickFolderTarget() : await _pickZipTarget();
    if (target == null || !mounted) return;

    final placed = datasetFromUploads(
      _files,
      contract,
      existing: target.existing,
    );
    final incoming = [if (tsv) ...placed.files];
    final binary = <String, Uint8List>{};
    if (report != null) {
      // Beside the visit where it is filed now, after any move to a free run.
      final filed = reportIntoDataset(
        placed.files,
        report.extension,
        target.existing,
      );
      incoming.addAll(filed.files);
      binary[filed.path] = report.bytes;
    }
    final plan = withRebuiltAggregate(
      target.existing,
      planBidsMerge(target.existing, incoming),
      contract,
    );
    if (plan.write.isEmpty) {
      _snack(
        plan.refused.isEmpty
            ? 'That BIDS folder already has these files.'
            : 'Nothing to add: ${plan.refused.join(', ')} already there.',
      );
      return;
    }
    final ok = await confirmMerge(
      context,
      plan,
      target.label,
      renumbered: tsv ? placed.renumbered : const [],
      keepsBackups: inPlace,
    );
    if (!ok || !mounted) return;

    final ({ExportOutcome outcome, String? warning}) applied;
    try {
      applied = await target.apply(plan, binary);
    } on DatasetChangedException catch (e) {
      if (mounted) _snack('$e');
      return;
    } catch (e) {
      if (mounted) _snack('The merge stopped partway: $e');
      return;
    }
    if (!mounted) return;
    final summary = [
      if (applied.outcome != ExportOutcome.notDelivered) ...[
        describeMergePlan(plan),
        if (plan.unread.isNotEmpty) unreadIndexNotice(plan.unread),
        if (plan.leftOut.isNotEmpty) leftOutNotice(plan.leftOut),
        ?applied.warning,
      ],
      ?report?.warning,
    ];
    if (summary.isEmpty) return;
    _snack(summary.map((s) => s.endsWith('.') ? s : '$s.').join(' '));
  }

  /// The chosen dataset, and how to write the merge back into it.
  Future<_MergeTarget?> _pickFolderTarget() async {
    try {
      final folder = await pickCheckedDatasetFolder(context);
      if (folder == null) return null;
      return (
        existing: folder.existing,
        label: folder.root,
        apply: (plan, binary) async {
          final warning = await applyMergeToDirectory(
            folder.root,
            plan,
            binary: binary,
            plannedAgainst: folder.existing,
          );
          return (outcome: ExportOutcome.saved, warning: warning);
        },
      );
    } catch (e) {
      if (mounted) _snack('Could not read that folder: $e');
      return null;
    }
  }

  Future<_MergeTarget?> _pickZipTarget() async {
    final zip = await pickDatasetZip(_snack);
    if (zip == null) return null;
    final existing = zip.files;
    final name = zip.name;
    final source = zip.bytes;
    if (!mounted) return null;
    final check = await checkDatasetFolder(
      context,
      name,
      existing,
      chooseAnother: 'Choose another file',
    );
    if (check == FolderCheck.chooseAnother) return await _pickZipTarget();
    if (check != FolderCheck.proceed) return null;
    return (
      existing: existing,
      label: name,
      apply: (plan, binary) async {
        if (!mounted) {
          return (outcome: ExportOutcome.notDelivered, warning: null);
        }
        final Uint8List merged;
        try {
          merged = mergedZip(source, plan, binary: binary);
        } catch (e) {
          _snack('Merged BIDS folder export failed: $e');
          return (outcome: ExportOutcome.notDelivered, warning: null);
        }
        final outcome = await exportFile(
          context,
          filename: '${name.replaceAll(RegExp(r'\.zip$'), '')}-merged.zip',
          anchor: _exportKey,
          failureLabel: 'Merged BIDS folder export failed',
          build: () async => (bytes: merged, warning: null),
        );
        return (outcome: outcome, warning: null);
      },
    );
  }

  Future<void> _exportBids() async {
    final Map<String, dynamic> contract;
    try {
      contract = await loadTsvContract();
    } catch (e) {
      if (mounted) _snack('BIDS export failed: $e');
      return;
    }
    final built = datasetFromUploads(_files, contract);
    if (!mounted) return;
    if (built.entries.isEmpty) {
      _snack('No chosen file carries BIDS entities in its name.');
      return;
    }
    await exportBidsDataset(
      context,
      anchor: _exportKey,
      entries: built.entries,
      extraFiles: [
        for (final f in built.files)
          if (f.path.startsWith('$aggregateDerivativeDir/')) f,
      ],
    );
    if (mounted && built.skipped.isNotEmpty) {
      _snack(
        'Skipped (no BIDS entities in the filename): '
        '${built.skipped.join(', ')}',
      );
    }
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.leading case final leading?) ...[
          leading,
          const Divider(height: 48),
        ],
        TitledSection(title: 'Visits', child: _visitList(theme)),
        if (_visits.isNotEmpty) ...[
          const Divider(height: 48),
          TitledSection(
            title: 'Reports and exports',
            child: Column(
              key: _exportKey,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PageSizeMenu(prefs: _prefs),
                ),
                const SizedBox(height: 8),
                _actions(theme),
              ],
            ),
          ),
        ],
      ],
    );
    final right = Column(
      key: _previewKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_visits.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: Text(_title, style: theme.textTheme.titleLarge)),
              TextButton.icon(
                onPressed: _enlarge,
                icon: const Icon(Icons.open_in_full, size: 18),
                label: const Text('Enlarge'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _preview(theme),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, c) {
        _stacked = c.maxWidth < 900;
        return _stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  left,
                  if (_visits.isNotEmpty) ...[const Divider(height: 48), right],
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: left),
                  const SizedBox(width: 48),
                  Expanded(flex: 3, child: right),
                ],
              );
      },
    );
  }

  Widget _visitList(ThemeData theme) {
    if (_loading) return const LinearProgressIndicator();
    if (_visits.isEmpty) {
      return Text(
        widget.folder == null
            ? 'Choose a BIDS folder above to see its visits.'
            : widget.patient == null
            ? 'Choose a patient to see their visits.'
            : 'No session or notes files found. $kBidsFolderRule',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return VisitList(visits: _visits, selected: _run, onSelect: _select);
  }

  /// Every action, always listed. A disabled one shows why in place of its
  /// description, which a menu item cannot do.
  Widget _actions(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final action in _shown)
        ReportActionRow(
          action: action,
          reason: unavailableReason(
            action,
            _files,
            canWriteFolder: canWriteChosenFolder,
          ),
          buttons: _buttonsFor(action),
        ),
    ],
  );

  ReportActionButton _btn(
    String label,
    Future<void> Function() run, [
    String? unavailable,
  ]) => (label: label, run: run, unavailable: unavailable);

  List<ReportActionButton> _buttonsFor(ReportAction action) => switch (action) {
    ReportAction.sessionReport => [
      _btn('PDF', () => _sessionReport(docx: false)),
      _btn('Word', () => _sessionReport(docx: true)),
      _btn(
        'Add to a BIDS folder',
        _addSingleToDataset,
        withBidsEntities(_files).isEmpty
            ? 'The file name carries no sub- entity.'
            : null,
      ),
    ],
    ReportAction.longitudinalReport => [
      _btn('PDF', () => _longitudinalReport(docx: false)),
      _btn('Word', () => _longitudinalReport(docx: true)),
    ],
    ReportAction.aggregateTsv => [_btn('Export', _exportAggregate)],
    ReportAction.bidsDataset => [_btn('Export', _exportBids)],
    // Both ways, so the choice is the user's rather than the platform's:
    // writing into the folder is the point, and a merged zip is the dry run
    // that leaves the original dataset untouched.
    ReportAction.addToDataset => [
      _btn(
        'Add',
        () => _addToDataset(inPlace: true),
        canWriteChosenFolder
            ? null
            : 'A tablet cannot be given a writable folder. Use Export.',
      ),
      _btn('Export', () => _addToDataset(inPlace: false)),
    ],
  };

  static const _shown = ReportAction.values;

  Widget _preview(ThemeData theme, {bool enlarged = false}) {
    if (_sessions.length == 1) {
      final rows = _sessions.single.rows;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${testedCount(rows)} configurations, '
                  '${electrodeModelIn(rows).isEmpty ? 'no model named' : electrodeModelIn(rows)}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _editTargets,
                icon: const Icon(Icons.adjust, size: 18),
                label: Text(
                  _targets == null ? 'Set scale targets' : 'Scale targets',
                ),
              ),
            ],
          ),
          if (_targets == null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                'No scale targets are set, so nothing is ranked.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          EntryChartsView(
            data: buildEntryChartData(rows, scalePrefs: _targets ?? const []),
            visibleConfigs: _visibleConfigs,
            onVisibleConfigsChanged: (n) => _changed(() => _visibleConfigs = n),
          ),
          SessionEntriesTable(rows: rows),
        ],
      );
    }
    if (_sessions.length > 1) {
      if (!patientIdsMatch(_sessions.map((f) => f.name).toList())) {
        return Text(
          'No chart is drawn across different patients.',
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
        );
      }
      return AcrossVisitsCharts(
        data: buildLongitudinalReportData(
          clinicalRanges: _ranges,
          files: {for (final f in _sessions) f.name: f.rows},
          scalePrefs: _targetsOrDefault,
        ),
        enlarged: enlarged,
      );
    }
    return Column(
      children: [
        for (final n in _notes.take(50))
          ListTile(
            dense: true,
            leading: Text(
              recordedTime(n.acqTime),
              style: theme.textTheme.bodySmall,
            ),
            title: Text(n.notes),
          ),
      ],
    );
  }
}

/// A dataset chosen for a merge: what it already holds, what to call it in the
/// confirmation, and how to write the merge back.
typedef _MergeTarget = ({
  List<DatasetFile> existing,
  String label,
  Future<({ExportOutcome outcome, String? warning})> Function(
    MergePlan plan,
    Map<String, Uint8List> binary,
  )
  apply,
});
