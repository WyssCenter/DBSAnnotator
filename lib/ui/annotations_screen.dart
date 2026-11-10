import 'package:flutter/material.dart';

import '../app_info.dart';
import '../core/annotation.dart';
import '../core/bids.dart';
import '../core/bids_sidecar.dart';
import '../core/timestamps.dart';
import '../core/session/tsv_kind.dart';
import '../report/annotations_report.dart';
import '../report/session_docx.dart' show DocxPageSize;
import 'bids_export.dart';
import 'recording_file.dart';
import 'report_sections_dialog.dart' show askAttestation;
import 'save_target.dart';
import 'share_util.dart';
import 'theme.dart';

/// Annotations workflow: a File step (patient / run, New or Open a BIDS
/// `task-notes` TSV) followed by a Notes step, structured like the
/// Complete-Workflow wizard but shorter. Fully offline, and the TSV is
/// drop-in for the desktop app.
class AnnotationsScreen extends StatefulWidget {
  const AnnotationsScreen({super.key});

  @override
  State<AnnotationsScreen> createState() => _AnnotationsScreenState();
}

/// The `task-` label of a notes file unless the user names another.
const _defaultTask = 'notes';

const RecordingWords _words = (
  entry: 'note',
  what: 'these notes',
  thing: 'the notes',
  staysInApp: 'These notes stay in the app.',
  exportUnderOtherRun: 'Export them under a different run.',
  savedInApp: 'The notes are saved in the app.',
  filedOnFirstEntry:
      'The notes are filed there as soon as the first note is added.',
  newDialogTitle: 'Create new notes TSV',
  newFileSaid: 'New notes file',
  recoveryTitle: 'Unfinished notes found',
  pickerFailed: 'Could not open the file picker. On Linux it needs the XDG desktop portal.',
);

class _AnnotationsScreenState extends State<AnnotationsScreen>
    with RecordingFile<AnnotationsScreen, List<Annotation>> {
  final _subjectCtrl = TextEditingController();
  final _taskCtrl = TextEditingController(text: _defaultTask);
  final _runCtrl = TextEditingController(text: '01');
  final _noteCtrl = TextEditingController();
  final _entries = <Annotation>[];

  int _currentStep = 0;

  @override
  RecordingWords get words => _words;

  @override
  TsvKind get tsvKind => TsvKind.notes;

  @override
  BidsName get bidsName => _bidsName();

  /// The file is oldest-first; the UI list is newest-first.
  @override
  String serialise() => writeAnnotations(_entries.reversed.toList());

  @override
  bool get hasEntries => _entries.isNotEmpty;

  @override
  String get firstAcqTime => _entries.last.acqTime;

  @override
  List<Annotation> readTsv(String content) => parseAnnotations(content);

  @override
  bool isBlank(List<Annotation> content) => content.isEmpty;

  @override
  String recoveredCount(List<Annotation> content) => '${content.length} notes';

  @override
  String openedSummary(List<Annotation> content) => '${content.length} notes';

  @override
  void show(List<Annotation> content, {required bool reopened}) {
    _entries
      ..clear()
      ..addAll(content.reversed);
    _currentStep = 1;
  }

  @override
  void fillLabels(BidsName name) {
    _subjectCtrl.text = name.subject;
    _taskCtrl.text = name.task.isEmpty ? _defaultTask : name.task;
    _runCtrl.text = name.run;
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _taskCtrl.dispose();
    _runCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// The BIDS entities for the notes TSV, its sidecar and the report
  /// derivative, so all three carry the same ones.
  ///
  /// [subject] and [run] are free text that ends up in a path, so they go
  /// through the sanitisers; run is an index in BIDS, not a label.
  ///
  /// The session is the label chosen when filing into a dataset, so exports
  /// carry the same `ses-` as the filed notes, and today's date otherwise.
  BidsName _bidsName({String? subject, String? run, String? session}) {
    final s = BidsName.label(subject ?? _subjectCtrl.text.trim());
    final task = BidsName.label(_taskCtrl.text.trim());
    return BidsName(
      subject: s.isEmpty ? 'unknown' : s,
      session:
          session ??
          datasetName?.session ??
          BidsName.sessionStamp(DateTime.now()),
      task: task.isEmpty ? _defaultTask : task,
      run: BidsName.index(run ?? _runCtrl.text.trim()),
    );
  }

  Future<void> _newSession() {
    final subject = _subjectCtrl.text.trim().isEmpty
        ? '01'
        : _subjectCtrl.text.trim();
    final run = _runCtrl.text.trim().isEmpty ? '01' : _runCtrl.text.trim();
    return newFile(
      proposed: _bidsName(
        subject: subject,
        run: run,
        session: BidsName.sessionStamp(DateTime.now()),
      ),
      header: writeAnnotations(const []),
      start: (filedAs) {
        _entries.clear();
        _subjectCtrl.text = subject;
        _runCtrl.text = filedAs?.run ?? run;
        _currentStep = 1;
      },
    );
  }

  Widget _fileStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(
                  labelText: 'Patient ID (sub-)',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _taskCtrl,
                decoration: const InputDecoration(
                  labelText: 'Task (task-)',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _runCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Run',
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _newSession,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('New'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: openFile,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open existing TSV'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _entries.isEmpty
              ? 'Empty. Add notes in the next step.'
              : '${_entries.length} notes loaded.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  void _addNote() {
    final text = _noteCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _entries.insert(0, Annotation.now(text));
      _noteCtrl.clear();
    });
    autosave();
  }

  Future<void> _export() async {
    if (_entries.isEmpty) {
      _snack('Add at least one note before exporting.');
      return;
    }
    await exportTsv();
  }

  /// Export these notes as a zipped one-subject BIDS dataset.
  Future<void> _exportBids() async {
    if (_entries.isEmpty) {
      _snack('Add at least one note before exporting.');
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
    final oldestFirst = _entries.reversed.toList();
    await countExport(
      () => exportBidsDataset(
        context,
        anchor: exportKey,
        avoid: exportAvoid,
        entries: [
          datasetEntry(
            name: _bidsName(),
            tsv: writeAnnotations(oldestFirst),
            contract: contract,
            kind: 'annotation_tsv',
            acqTime: oldestFirst.first.acqTime,
          ),
        ],
      ),
    );
  }

  /// Export the notes as a PDF or Word report.
  Future<void> _exportReport({required bool docx}) async {
    if (_entries.isEmpty) {
      _snack('Add at least one note before exporting a report.');
      return;
    }
    final attestation = await askAttestation(context, rated: false);
    if (attestation == null || !mounted) return;
    final name = _bidsName();
    final subject = name.subject;
    // `_report` is not a BIDS suffix; a report is a derivative, not raw data.
    // Same entities as the TSV so the two files sort together.
    final filename = name
        .withSuffix('report', extension: docx ? 'docx' : 'pdf')
        .filename;

    await exportFile(
      context,
      filename: filename,
      anchor: exportKey,
      failureLabel: 'Report export failed',
      avoid: exportAvoid,
      build: () async {
        final data = buildAnnotationsReportData(
          entries: _entries,
          subjectId: subject,
          sourceFile: savePath == null ? '' : pickedBasename(savePath!),
        );
        if (docx) {
          return (
            bytes: buildAnnotationsDocx(
              data,
              pageSize: DocxPageSize.a4,
              attestation: attestation,
            ),
            warning: null,
          );
        }
        final report = await buildAnnotationsPdf(
          data,
          attestation: attestation,
        );
        return (
          bytes: report.bytes,
          warning: report.lostCharacters
              ? 'Some characters could not be rendered in the PDF and were '
                    'replaced with "?". Add the IBM Plex fonts to assets/fonts/ '
                    'for full Unicode, or export to Word instead.'
              : null,
        );
      },
    );
  }

  Widget _notesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _noteCtrl,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: 'Note',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _addNote,
          icon: const Icon(Icons.add),
          label: const Text('Insert timestamped note'),
        ),
        const SizedBox(height: 8),
        if (unkeptNotice case final notice?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(notice, style: Theme.of(context).textTheme.bodySmall),
          ),
        MenuAnchor(
          builder: (context, controller, child) => OutlinedButton.icon(
            key: exportKey,
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: const Icon(Icons.ios_share),
            label: const Text('Export'),
          ),
          menuChildren: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => _exportReport(docx: false),
              child: const Text('Report (PDF)'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.description_outlined),
              onPressed: () => _exportReport(docx: true),
              child: const Text('Report (Word)'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.table_chart_outlined),
              onPressed: _export,
              child: const Text('Data (TSV)'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.folder_zip_outlined),
              onPressed: _exportBids,
              child: const Text('BIDS dataset (zip)'),
            ),
          ],
        ),
        const Divider(height: 32),
        Text(
          'Inserted notes (${_entries.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_entries.isEmpty)
          const Center(child: Text('No notes yet.'))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 30,
              dataRowMaxHeight: 96,
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Time')),
                DataColumn(label: Text('Note')),
              ],
              rows: [
                for (final e in _entries)
                  DataRow(
                    cells: [
                      DataCell(Text(_noteDate(e))),
                      DataCell(Text(_noteTime(e))),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Text(
                            e.notes,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
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
        title: const Text('Annotations'),
        actions: const [TextSizeButtons(), HelpButton(), ThemeToggleButton()],
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepTapped: (i) => setState(() => _currentStep = i),
        onStepContinue: _currentStep < 1
            ? () => setState(() => _currentStep += 1)
            : null,
        onStepCancel: _currentStep > 0
            ? () => setState(() => _currentStep -= 1)
            : null,
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                if (details.onStepContinue != null)
                  FilledButton.tonal(
                    onPressed: details.onStepContinue,
                    child: const Text('Next'),
                  ),
                if (details.onStepContinue != null &&
                    details.onStepCancel != null)
                  const SizedBox(width: 8),
                if (details.onStepCancel != null)
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Back'),
                  ),
              ],
            ),
          );
        },
        steps: [
          Step(
            title: const Text('File'),
            subtitle: const Text('Patient / task / run: new or open TSV'),
            isActive: _currentStep == 0,
            content: _fileStep(),
          ),
          Step(
            title: const Text('Notes'),
            subtitle: const Text('Timestamped notes → task-notes TSV'),
            isActive: _currentStep == 1,
            content: _notesStep(),
          ),
        ],
      ),
    );
  }
}

/// A note's date for the entries table, or '' when it has no usable instant.
///
/// Date and clock time are display forms of the note's `acq_time`, not stored
/// cells. Pre-0.5.0 files held a zone name with no offset, so their rows
/// resolve to an instant only via `Annotation.fromMap`'s backfill.
String _noteDate(Annotation e) => recordedDate(e.acqTime);

/// A note's clock time, with the recorded UTC offset when the row carries one.
String _noteTime(Annotation e) {
  final time = recordedTime(e.acqTime);
  if (time.isEmpty) return '';
  final offset = offsetFromTimezoneCell(e.acqTime);
  return offset.isEmpty ? time : '$time (UTC$offset)';
}
