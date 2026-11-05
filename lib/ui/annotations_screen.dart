import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../core/annotation.dart';
import '../core/bids.dart';
import '../core/bids_merge.dart';
import '../core/bids_sidecar.dart';
import '../core/safe_file.dart';
import '../core/timestamps.dart';
import '../core/session/tsv_kind.dart';
import '../report/annotations_report.dart';
import '../report/session_docx.dart' show DocxPageSize;
import 'bids_export.dart';
import 'bids_merge_ui.dart';
import 'report_sections_dialog.dart' show askAttestation;
import 'save_target.dart';
import 'share_util.dart';
import 'theme.dart';
import 'close_guard.dart';

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

class _AnnotationsScreenState extends State<AnnotationsScreen> {
  // Serialised, atomic autosave to the user's file. See [SafeFileWriter].
  final _writer = SafeFileWriter();

  final _subjectCtrl = TextEditingController();
  final _taskCtrl = TextEditingController(text: _defaultTask);
  final _runCtrl = TextEditingController(text: '01');
  final _noteCtrl = TextEditingController();
  final _entries = <Annotation>[];

  int _currentStep = 0;
  // Chosen save path (from New/Open); when set, notes autosave to it.
  String? _savePath;
  // Working copy in the app's own storage, written on every note whatever the
  // picker returned. It is only deleted when the user discards it.
  String? _workingPath;
  bool _savePathIsSandboxCopy = false;
  bool _exportedSinceChange = false;
  // Bumped on every change, so an export started before one is not counted.
  int _changes = 0;
  bool _workingFailed = false;
  bool _fileFailed = false;
  // Autosaves run one at a time: a later one must not overwrite newer text,
  // nor file the notes into the dataset a second time.
  Future<void> _saving = Future.value();
  int _pendingSaves = 0;
  // New or Open is in progress; a second one must not start meanwhile.
  bool _switching = false;
  // A leave question is open; a second close or Back must not stack another.
  bool _leaveAsked = false;
  // Set when the notes are recorded into a BIDS dataset rather than a loose
  // file. Filed at the first note, for the reason the session screen gives.
  String? _datasetRoot;
  BidsName? _datasetName;

  /// Anchors the iPadOS share popover to the export button. See
  /// [shareOriginFrom].
  final _exportKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerRecovery());
    activeSessionGuard = _mayLeave;
  }

  @override
  void dispose() {
    if (activeSessionGuard == _mayLeave) activeSessionGuard = null;
    _subjectCtrl.dispose();
    _taskCtrl.dispose();
    _runCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  /// Offer back notes the app stopped in the middle of. Asking rather than
  /// restoring silently: the user may have moved on to another patient.
  Future<void> _offerRecovery() async {
    final left = await unfinishedWork();
    if (!mounted) return;
    File? file;
    var loaded = <Annotation>[];
    for (final candidate in left) {
      try {
        final content = await candidate.readAsString();
        if (sniffTsvKind(content) != TsvKind.notes) continue;
        loaded = parseAnnotations(content);
      } catch (_) {
        continue;
      }
      if (loaded.isEmpty) continue;
      file = candidate;
      break;
    }
    final found = file;
    if (found == null || !mounted) return;

    final name = pickedBasename(found.path);
    final keep = await askReopenUnfinished(
      context,
      title: 'Unfinished notes found',
      message:
          '$name was left open with ${loaded.length} notes recorded. They '
          'were saved as you went, and can be reopened here.',
    );
    if (!mounted || keep == null) return;
    if (!keep) {
      await discardWork(found.path);
      return;
    }
    if (_refuseWhileSaving()) return;
    final bids = BidsName.parse(name);
    setState(() {
      _entries
        ..clear()
        ..addAll(loaded.reversed);
      _workingPath = found.path;
      // No _savePath: guessing it would autosave over a file not chosen here.
      _savePath = null;
      _savePathIsSandboxCopy = false;
      _workingFailed = false;
      _fileFailed = false;
      _exportedSinceChange = false;
      _changes++;
      _datasetRoot = null;
      _datasetName = null;
      if (bids != null) _fillLabels(bids);
      _currentStep = 1;
    });
    _snack('Reopened $name. Export it to save it outside the app.');
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
          _datasetName?.session ??
          BidsName.sessionStamp(DateTime.now()),
      task: task.isEmpty ? _defaultTask : task,
      run: BidsName.index(run ?? _runCtrl.text.trim()),
    );
  }

  void _fillLabels(BidsName bids) {
    _subjectCtrl.text = bids.subject;
    _taskCtrl.text = bids.task.isEmpty ? _defaultTask : bids.task;
    _runCtrl.text = bids.run;
  }

  /// Write the `_beh.json` sidecar beside [tsvPath]; see the session screen's
  /// copy for why this is best-effort and silent.
  Future<void> _writeSidecar(String tsvPath) async {
    try {
      final json = tsvPath.replaceFirst(RegExp(r'\.tsv$'), '.json');
      if (json == tsvPath || File(json).existsSync()) return;
      final contract = await loadTsvContract();
      await File(json).writeAsString(
        annotationSidecarJson(
          contract,
          appVersion: appVersion,
          task: _bidsName().task,
        ),
      );
    } catch (_) {
      // No sidecar is a documentation loss, not a data loss.
    }
  }

  Future<void> _newSession() async {
    if (_switching) return;
    _switching = true;
    try {
      await _newSessionFlow();
    } finally {
      _switching = false;
    }
  }

  bool _refuseWhileSaving() {
    if (!_saveRunning) return false;
    _snack('A save is still running. Try again in a moment.');
    return true;
  }

  Future<void> _newSessionFlow() async {
    final subject = _subjectCtrl.text.trim().isEmpty
        ? '01'
        : _subjectCtrl.text.trim();
    final run = _runCtrl.text.trim().isEmpty ? '01' : _runCtrl.text.trim();
    final bids = _bidsName(
      subject: subject,
      run: run,
      session: BidsName.sessionStamp(DateTime.now()),
    );
    final name = bids.filename;

    // Loose file, or straight into a dataset: the answer decides where every
    // autosave of these notes lands.
    final into = await askNewTarget(context, bids, what: 'these notes');
    if (into == null || !mounted) return;
    final leave = await _askLeave();
    if (leave == null || !mounted || _refuseWhileSaving()) return;
    final oldWork = _workingPath;
    if (into.root != null) {
      final work = await workingPath(into.name.filename);
      if (!mounted || _refuseWhileSaving()) return;
      setState(() {
        _entries.clear();
        _savePath = null;
        _savePathIsSandboxCopy = false;
        _workingFailed = false;
        _fileFailed = false;
        _exportedSinceChange = false;
        _changes++;
        _workingPath = work;
        _datasetRoot = into.root;
        _datasetName = into.name;
        _subjectCtrl.text = subject;
        _runCtrl.text = into.name.run;
        _currentStep = 1;
      });
      if (leave == LeaveChoice.discard) await discardWork(oldWork);
      _snack(
        'Recording into ${into.root}. '
        'The notes are filed there as soon as the first note is added.',
      );
      return;
    }

    final NewTsvTarget? target;
    try {
      target = await createNewTsv(
        dialogTitle: 'Create new notes TSV',
        fileName: name,
        header: writeAnnotations(const []), // header only
        avoidPath: _savePath,
      );
    } catch (e) {
      if (mounted) _snack('Could not start a new file: $e');
      if (_savePath != null) _queueSave();
      return;
    }
    if (target == null || !mounted) return; // dialog shown but cancelled
    if (target.fellBack && mounted) {
      _snack('No file dialog available; saved to ${target.location}');
    }
    final p = target.path;
    if (p != null) await _writeSidecar(p);
    final work = await workingPath(name);
    if (!mounted || _refuseWhileSaving()) return;
    setState(() {
      _entries.clear();
      _savePath = p;
      _savePathIsSandboxCopy = !pickedPathAutosavesToOriginal(p);
      _workingFailed = false;
      _fileFailed = false;
      _exportedSinceChange = false;
      _changes++;
      _workingPath = work;
      _datasetRoot = null;
      _datasetName = null;
      _subjectCtrl.text = subject;
      _runCtrl.text = run;
      _currentStep = 1;
    });
    if (leave == LeaveChoice.discard) await discardWork(oldWork);
    _snack('New notes file: ${target.location}');
  }

  Future<void> _open() async {
    if (_switching) return;
    _switching = true;
    try {
      await _openFlow();
    } finally {
      _switching = false;
    }
  }

  Future<void> _openFlow() async {
    // `pickFile`, not `pickFiles`: file_picker 12 defaults `allowMultiple` to
    // true, so the plural call would silently accept a multi-selection.
    final PlatformFile? chosen;
    try {
      chosen = await FilePicker.pickFile(type: FileType.any);
    } catch (e) {
      if (mounted) {
        _snack('Open dialog unavailable. On Linux, install "zenity". ($e)');
      }
      return;
    }
    if (chosen == null) return;
    final picked = chosen; // non-nullable, so the setState closure can use it
    final content = await readPickedText(picked);
    if (content == null) {
      if (mounted) _snack('Could not read ${picked.name}.');
      return;
    }
    // Refuse the wrong workflow's file before anything sets `_savePath`.
    //
    // `parseAnnotations` is total and `sessionColumns` is a superset of
    // `annotationColumns`, so a session TSV parses here successfully, one
    // "note" per row. `_savePath` would then point at the clinician's session
    // file, and the first autosave would replace it with the five annotation
    // columns: every block, parameter and rating gone, atomically and with no
    // `.tmp` to recover from. This screen is the only one that writes back to
    // the file it opened.
    final kind = sniffTsvKind(content);
    if (kind != TsvKind.notes) {
      if (mounted) _snack(tsvKindMismatch(picked.name, kind, TsvKind.notes));
      return;
    }

    final loaded = parseAnnotations(content);
    final leave = await _askLeave();
    if (leave == null || !mounted || _refuseWhileSaving()) return;
    final oldWork = _workingPath;
    final bids = BidsName.parse(picked.name);
    final work = await workingPath(picked.name);
    if (!mounted || _refuseWhileSaving()) return;
    setState(() {
      _entries
        ..clear()
        // File is oldest-first; the UI shows newest-first.
        ..addAll(loaded.reversed);
      _savePath = picked.path;
      _savePathIsSandboxCopy = !pickedPathAutosavesToOriginal(picked.path);
      _workingFailed = false;
      _fileFailed = false;
      _exportedSinceChange = false;
      _changes++;
      _workingPath = work;
      _datasetRoot = null;
      _datasetName = null;
      if (bids != null) _fillLabels(bids);
      _currentStep = 1;
    });
    if (leave == LeaveChoice.discard) await discardWork(oldWork);
    _snack(
      'Opened ${picked.name} (${loaded.length} notes).'
      '${pickedPathAutosavesToOriginal(picked.path) ? '' : ' $sandboxCopyNotice'}',
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
              onPressed: _open,
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
    _autosave();
  }

  /// Write every note to disk as it is added.
  ///
  /// The working copy is unconditional; [_savePath] is written too when the
  /// picker returned a path `dart:io` can open, which on Android it does not.
  /// Both go through [SafeFileWriter], so a crash mid-write leaves either the
  /// previous complete file or the new one.
  Future<void> _autosave() {
    _exportedSinceChange = false;
    _changes++;
    return _queueSave();
  }

  Future<void> _queueSave() {
    _pendingSaves++;
    return _saving = _saving.then((_) => _autosaveOnce());
  }

  bool get _saveRunning => _pendingSaves > 0;

  Future<void> _autosaveOnce() async {
    try {
      await _autosaveBody();
    } catch (e) {
      _workingFailed = true;
      if (mounted) _snack('Could not save this note: $e');
    } finally {
      _pendingSaves--;
    }
  }

  Future<void> _autosaveBody() async {
    // The file is oldest-first; the UI list is newest-first.
    final text = writeAnnotations(_entries.reversed.toList());
    final hasEntries = _entries.isNotEmpty;
    final datasetRoot = _datasetRoot;
    final bidsFilename = _bidsName().filename;
    try {
      var work = _workingPath;
      if (work == null) {
        work = await workingPath(bidsFilename);
        _workingPath = work;
      }
      await _writer.write(work, text);
      _workingFailed = false;
    } catch (e) {
      _workingFailed = true;
      if (mounted) {
        _snack(
          _savePath == null && datasetRoot == null
              ? 'Could not save this note: $e'
              : "Could not update the app's recovery copy: $e",
        );
      }
    }
    if (datasetRoot != null && _savePath == null && hasEntries) {
      await _fileIntoDataset(text);
    }
    final path = _savePath;
    if (path == null) {
      _fileFailed = false;
      return;
    }
    try {
      await _writer.write(path, text);
      _fileFailed = false;
    } catch (e) {
      _fileFailed = true;
      if (mounted) {
        _snack(
          'Autosave to your file failed: $e.'
          '${_workingFailed ? ' This note is not saved anywhere yet.' : ' The note is saved in the app.'}',
        );
      }
    }
  }

  /// Place these notes in the chosen dataset; see [fileIntoDataset].
  Future<void> _fileIntoDataset(String text) async {
    final root = _datasetRoot;
    final name = _datasetName;
    if (root == null || name == null) return;
    final acqTime = _entries.last.acqTime;
    try {
      final filed = await fileIntoDataset(
        root: root,
        name: name,
        tsv: text,
        kind: 'annotation_tsv',
        acqTime: acqTime,
      );
      if (filed == null) {
        if (mounted) {
          _snack(
            'That dataset already holds ${name.filename}.'
            '${_workingFailed ? ' This note is not saved anywhere yet.' : ' These notes stay in the app.'} Export '
            'them under a different run.',
          );
        }
        if (mounted) setState(() => _datasetRoot = null);
        return;
      }
      if (!mounted) return;
      setState(() => _savePath = filed.path);
      _snack(
        'Filed as ${name.relativeDir}/${name.filename}.'
        '${filed.unread.isEmpty ? '' : ' ${unreadIndexNotice(filed.unread)}'}'
        '${filed.warning == null ? '' : ' ${filed.warning}'}',
      );
    } catch (e) {
      if (mounted) {
        _snack(
          'Could not file into the dataset: $e.'
          '${_workingFailed ? ' This note is not saved anywhere yet.' : ' The notes are saved in the app.'}',
        );
      }
      if (mounted) setState(() => _datasetRoot = null);
    }
  }

  Future<void> _export() async {
    if (_entries.isEmpty) {
      _snack('Add at least one note before exporting.');
      return;
    }
    final changes = _changes;
    final outcome = await exportFile(
      context,
      filename: _bidsName().filename,
      anchor: _exportKey,
      build: () async => (
        bytes: utf8.encode(writeAnnotations(_entries.reversed.toList())),
        warning: null,
      ),
    );
    if (outcome == ExportOutcome.saved && changes == _changes) {
      _exportedSinceChange = true;
    }
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
    final changes = _changes;
    final outcome = await exportBidsDataset(
      context,
      anchor: _exportKey,
      entries: [
        datasetEntry(
          name: _bidsName(),
          tsv: writeAnnotations(oldestFirst),
          contract: contract,
          kind: 'annotation_tsv',
          acqTime: oldestFirst.first.acqTime,
        ),
      ],
    );
    if (outcome == ExportOutcome.saved && changes == _changes) {
      _exportedSinceChange = true;
    }
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
      anchor: _exportKey,
      failureLabel: 'Report export failed',
      build: () async {
        final data = buildAnnotationsReportData(
          entries: _entries,
          subjectId: subject,
          sourceFile: _savePath == null ? '' : pickedBasename(_savePath!),
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
        MenuAnchor(
          builder: (context, controller, child) => OutlinedButton.icon(
            key: _exportKey,
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

  /// Ask whether to keep the recovery copy; see `close_guard.dart`. Null to
  /// stay, including when another question is already open.
  Future<LeaveChoice?> _askLeave() async {
    if (_leaveAsked) return null;
    _leaveAsked = true;
    try {
      final stillSaving = !await waitForSaves(() => _saving);
      if (!mounted) return LeaveChoice.keep;
      final guard = leaveGuardState(
        workingFailed: _workingFailed,
        fileFailed: _fileFailed,
        hasSavePath: _savePath != null,
        savePathIsSandboxCopy: _savePathIsSandboxCopy,
        exportedSinceChange: _exportedSinceChange,
        hasEntries: _entries.isNotEmpty,
        stillSaving: stillSaving,
      );
      return await askLeaveSession(
        context,
        _workingPath,
        onlyCopy: guard.onlyCopy,
        copyMayBeStale: guard.copyMayBeStale,
        entriesUnsaved: guard.entriesUnsaved,
        stillSaving: stillSaving && _entries.isNotEmpty,
      );
    } finally {
      _leaveAsked = false;
    }
  }

  Future<bool> _mayLeave() async {
    final choice = await _askLeave();
    if (choice == null) return false;
    if (choice == LeaveChoice.discard) await discardWork(_workingPath);
    return true;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (await _mayLeave() && context.mounted) Navigator.pop(context);
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
