import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/bids.dart';
import '../core/bids_dataset.dart';
import '../core/bids_merge.dart';
import '../core/bids_sidecar.dart';
import '../core/safe_file.dart';
import '../core/schema_columns.dart';
import '../core/session/bids_folder.dart' show bidsRootOf;
import '../core/session/tsv_kind.dart';
import 'bids_merge_ui.dart';
import 'close_guard.dart';
import 'save_target.dart';
import 'share_util.dart';

/// The wording that differs between the session and notes screens.
typedef RecordingWords = ({
  String entry,
  String what,
  String thing,
  String staysInApp,
  String exportUnderOtherRun,
  String savedInApp,
  String filedOnFirstEntry,
  String newDialogTitle,
  String newFileSaid,
  String recoveryTitle,
  String pickerFailed,
});

/// The file lifecycle of a recording screen: autosave, New, Open, recovery,
/// export bookkeeping and the leave question, for content of type [C].
mixin RecordingFile<W extends StatefulWidget, C> on State<W> {
  RecordingWords get words;
  TsvKind get tsvKind;
  BidsName get bidsName;

  /// The whole file as it should be written now.
  String serialise();
  bool get hasEntries;

  /// `acq_time` of the oldest entry.
  String get firstAcqTime;

  /// Parse [content]; throws when it cannot be read.
  C readTsv(String content);

  /// Parse the file at [path] holding [content]; a screen whose files need
  /// their BIDS folder to be read whole overrides this.
  Future<C> readFile(String content, String? path) async => readTsv(content);

  /// This screen's content as an entry of a BIDS folder named [name].
  DatasetEntry datasetEntry(BidsName name, Map<String, dynamic> contract);
  bool isBlank(C content);

  /// What a recovered file holds, for the question, such as `3 blocks`.
  String recoveredCount(C content);

  /// What an opened file holds, for the snack, such as `3 notes`.
  String openedSummary(C content);

  /// Replace the content with [content]; runs inside setState.
  void show(C content, {required bool reopened});

  /// Fill the label fields from [name]; runs inside setState.
  void fillLabels(BidsName name);

  /// Show [message] once a file was opened or reopened.
  Future<void> announceLoaded(String message) async => _snack(message);

  /// Set while the opened file has columns the app does not keep: the line to
  /// show beside Export. Null otherwise.
  String? get unkeptNotice => _unkept.isEmpty
      ? null
      : 'The file you opened is not updated. It has columns the app does not '
            'keep (${_unkept.join(', ')}). Export saves ${words.thing} without '
            'them.';

  /// Share-popover anchor. ONE key, on the Export button: a menu item is
  /// already unmounted by the time the iPad share sheet asks for its rect.
  final exportKey = GlobalKey();

  String? get savePath => _savePath;
  bool get hasFile => _workingPath != null;

  /// Where the file is kept: the chosen file, the dataset, or the app's copy.
  String? get savedLocation => _savePath ?? _datasetRoot ?? _workingPath;

  /// The BIDS folder this visit is filed into, when there is one.
  String? get datasetRoot => _datasetRoot;
  bool get savePathIsSandboxCopy => _savePathIsSandboxCopy;
  BidsName? get datasetName => _datasetName;

  final _writer = SafeFileWriter();

  // Chosen save path (from New/Open); when set, entries autosave to it.
  String? _savePath;
  // Working copy in the app's own storage, written on every entry whatever
  // the picker returned. It is only deleted when the user discards it.
  String? _workingPath;
  // Set when recording into a BIDS dataset rather than a loose file. The file
  // is filed on the FIRST entry, not at creation: a header-only TSV that no
  // scans.tsv lists is a dataset that does not validate.
  String? _datasetRoot;
  BidsName? _datasetName;
  // True when _savePath is a mobile sandbox copy, not the user's own file.
  bool _savePathIsSandboxCopy = false;
  // The opened file's columns the app does not keep, and its path. Autosave
  // never writes that file: it has no save path while these are set.
  List<String> _unkept = const [];
  String? _openedPath;
  bool _exportedSinceChange = false;
  // Bumped on every change, so an export started before one is not counted.
  int _changes = 0;
  // Whether the last autosave failed to write the recovery copy / the user's
  // file, so that file is stale.
  bool _workingFailed = false;
  bool _fileFailed = false;
  // Autosaves run one at a time: a second one starting before the first has
  // filed the dataset copy would file it again.
  Future<void> _saving = Future.value();
  int _pendingSaves = 0;
  // New or Open is in progress; a second one must not start meanwhile.
  bool _switching = false;
  // A leave question is open; a second close or Back must not stack another.
  bool _leaveAsked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerRecovery());
    activeSessionGuard = mayLeave;
  }

  @override
  void dispose() {
    if (activeSessionGuard == mayLeave) activeSessionGuard = null;
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Write every entry to the working copy, and to the save path when there is
  /// one `dart:io` can open, which on Android there is not.
  Future<void> autosave() {
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
      if (mounted) _snack('Could not save this ${words.entry}: $e');
    } finally {
      _pendingSaves--;
    }
  }

  Future<void> _autosaveBody() async {
    final text = serialise();
    final entriesNow = hasEntries;
    final datasetRoot = _datasetRoot;
    final bidsFilename = bidsName.filename;
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
              ? 'Could not save this ${words.entry}: $e'
              : "Could not update the app's recovery copy: $e",
        );
      }
    }
    if (datasetRoot != null) {
      if (entriesNow) await _fileIntoDataset();
      return;
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
          '${_workingFailed ? ' This ${words.entry} is not saved anywhere yet.' : ' The ${words.entry} is saved in the app.'}',
        );
      }
    }
  }

  /// Place the file in the chosen dataset; see [fileIntoDataset].
  Future<void> _fileIntoDataset() async {
    final root = _datasetRoot;
    final name = _datasetName;
    if (root == null || name == null) return;
    final first = _savePath == null;
    try {
      final filed = await fileIntoDataset(
        root: root,
        entry: datasetEntry(name, await loadTsvContract()),
        filed: !first,
      );
      if (filed == null) {
        if (mounted) {
          _snack(
            'That BIDS folder already holds ${name.filename}.'
            '${_workingFailed ? ' This ${words.entry} is not saved anywhere yet.' : ' ${words.staysInApp}'} '
            '${words.exportUnderOtherRun}',
          );
        }
        if (mounted) setState(() => _datasetRoot = null);
        return;
      }
      if (!mounted) return;
      setState(() => _savePath = filed.path);
      if (!first && filed.unread.isEmpty && filed.warning == null) return;
      _snack(
        '${first ? 'Saved as ${name.relativeDir}/${name.filename}.' : ''}'
        '${filed.unread.isEmpty ? '' : ' ${unreadIndexNotice(filed.unread)}'}'
        '${filed.warning == null ? '' : ' ${filed.warning}'}',
      );
    } catch (e) {
      if (mounted) {
        _snack(
          'Could not file into the BIDS folder: $e.'
          '${_workingFailed ? ' This ${words.entry} is not saved anywhere yet.' : ' ${words.savedInApp}'}',
        );
      }
      if (mounted) setState(() => _datasetRoot = null);
    }
  }

  bool _refuseWhileSaving() {
    if (!_saveRunning) return false;
    _snack('A save is still running. Try again in a moment.');
    return true;
  }

  /// Point the screen at a new file; runs inside setState.
  void _useFile({
    required String? savePath,
    required bool sandboxCopy,
    required String? workingPath,
    required String? datasetRoot,
    required BidsName? datasetName,
    List<String> unkept = const [],
    String? openedPath,
  }) {
    _unkept = unkept;
    _openedPath = openedPath;
    _savePath = savePath;
    _savePathIsSandboxCopy = sandboxCopy;
    _workingPath = workingPath;
    _datasetRoot = datasetRoot;
    _datasetName = datasetName;
    _workingFailed = false;
    _fileFailed = false;
    _exportedSinceChange = false;
    _changes++;
  }

  /// Swap to another file once the user has answered the leave question.
  /// False when the screen went away or a save is still running.
  Future<bool> _replaceFile({
    required LeaveChoice leave,
    required String? oldWork,
    required String workingName,
    required String? savePath,
    required bool sandboxCopy,
    required String? datasetRoot,
    required BidsName? datasetName,
    required void Function() show,
    List<String> unkept = const [],
    String? openedPath,
  }) async {
    final String work;
    try {
      work = await workingPath(workingName);
    } catch (e) {
      if (mounted) _snack("Could not prepare the app's recovery copy: $e");
      return false;
    }
    if (!mounted || _refuseWhileSaving()) return false;
    await _endVisit();
    if (!mounted || _refuseWhileSaving()) return false;
    setState(() {
      show();
      _useFile(
        savePath: savePath,
        sandboxCopy: sandboxCopy,
        workingPath: work,
        datasetRoot: datasetRoot,
        datasetName: datasetName,
        unkept: unkept,
        openedPath: openedPath,
      );
    });
    if (leave == LeaveChoice.discard) await discardWork(oldWork);
    return true;
  }

  /// Start an empty visit saved into the BIDS folder at [root] as [name];
  /// [start] resets the content inside setState. False when nothing started.
  /// [ask] false when the user already agreed to leave the current file.
  Future<bool> newInFolder({
    required String root,
    required BidsName name,
    required void Function() start,
    bool ask = true,
  }) async {
    if (_switching) return false;
    _switching = true;
    try {
      final leave = await _askLeave(ask: ask);
      if (leave == null || !mounted || _refuseWhileSaving()) return false;
      return await _replaceFile(
        leave: leave,
        oldWork: _workingPath,
        workingName: name.filename,
        savePath: null,
        sandboxCopy: false,
        datasetRoot: root,
        datasetName: name,
        show: start,
      );
    } finally {
      _switching = false;
    }
  }

  /// Open an existing TSV of this screen's kind.
  Future<void> openFile() async {
    if (_switching) return;
    _switching = true;
    try {
      await _openFlow();
    } finally {
      _switching = false;
    }
  }

  Future<void> _openFlow() async {
    // `pickFile`, not `pickFiles`: `allowMultiple` defaults to TRUE, so
    // `pickFiles` here would silently accept a multi-selection.
    final PlatformFile? chosen;
    try {
      chosen = await FilePicker.pickFile(type: FileType.any);
    } catch (e) {
      if (mounted) _snack('${words.pickerFailed} ($e)');
      return;
    }
    if (chosen == null) return;
    final picked = chosen;
    final content = await readPickedText(picked);
    if (content == null) {
      if (mounted) _snack('Could not read ${picked.name}.');
      return;
    }
    // Refuse the wrong workflow's file before anything sets the save path.
    //
    // The session columns are a superset of the notes columns, so a session
    // TSV parses as notes, one "note" per row. The
    // save path would then point at the clinician's session file, and the
    // first autosave would replace it with the five annotation columns: every
    // block, parameter and rating gone, atomically and with no `.tmp` to
    // recover from.
    final kind = sniffTsvKind(content);
    if (kind != tsvKind) {
      if (mounted) _snack(tsvKindMismatch(picked.name, kind, tsvKind));
      return;
    }

    final C loaded;
    try {
      loaded = await readFile(content, picked.path);
    } catch (e) {
      if (mounted) _snack('Could not read ${picked.name}: $e');
      return;
    }
    final leave = await _askLeave();
    if (leave == null || !mounted || _refuseWhileSaving()) return;
    final oldWork = _workingPath;
    final bids = BidsName.parse(picked.name);
    final unkept = unkeptColumns(content, tsvKind);
    final keepsFile = unkept.isEmpty;
    final sandboxCopy =
        keepsFile && !pickedPathAutosavesToOriginal(picked.path);
    final root = keepsFile && bids != null && picked.path != null
        ? bidsRootOf(picked.path!)
        : null;
    final replaced = await _replaceFile(
      leave: leave,
      oldWork: oldWork,
      workingName: picked.name,
      savePath: keepsFile ? picked.path : null,
      sandboxCopy: sandboxCopy,
      unkept: unkept,
      openedPath: picked.path,
      datasetRoot: root,
      datasetName: root == null ? null : bids,
      show: () {
        show(loaded, reopened: false);
        if (bids != null) fillLabels(bids);
      },
    );
    if (!replaced) return;
    final opened = 'Opened ${picked.name} (${openedSummary(loaded)}).';
    await announceLoaded(
      keepsFile
          ? (sandboxCopy ? '$opened $sandboxCopyNotice' : opened)
          : '$opened The app does not keep these columns: ${unkept.join(', ')}. '
                'Your file is left unchanged. Export saves ${words.thing} without '
                'them.',
    );
  }

  /// Offer back a recording the app stopped in the middle of. Asking rather
  /// than restoring silently: the user may have moved on to another patient.
  Future<void> _offerRecovery() async {
    final left = await unfinishedWork();
    if (!mounted) return;
    File? file;
    C? recovered;
    for (final candidate in left) {
      try {
        final content = await candidate.readAsString();
        if (sniffTsvKind(content) != tsvKind) continue;
        final parsed = readTsv(content);
        if (isBlank(parsed)) continue;
        file = candidate;
        recovered = parsed;
        break;
      } catch (_) {
        continue;
      }
    }
    final found = file;
    final restored = recovered;
    if (found == null || restored == null || !mounted) return;

    final name = pickedBasename(found.path);
    final keep = await askReopenUnfinished(
      context,
      title: words.recoveryTitle,
      message:
          '$name was left open, ${recoveredCount(restored)}. It was saved '
          'as you went, and can be reopened here.',
    );
    if (!mounted || keep == null) return;
    if (!keep) {
      await discardWork(found.path);
      return;
    }
    if (_refuseWhileSaving()) return;
    final bids = BidsName.parse(name);
    setState(() {
      show(restored, reopened: true);
      // No save path: guessing it would autosave over a file not chosen here.
      _useFile(
        savePath: null,
        sandboxCopy: false,
        workingPath: found.path,
        datasetRoot: null,
        datasetName: null,
      );
      if (bids != null) fillLabels(bids);
    });
    await announceLoaded(
      'Reopened $name. Export it to save it outside the app.',
    );
  }

  /// The opened file as an [AvoidFile] while it has unkept columns, else null.
  AvoidFile? _unkeptFile(String reason) {
    final opened = _openedPath;
    if (_unkept.isEmpty || opened == null || !File(opened).existsSync()) {
      return null;
    }
    return (path: opened, reason: reason);
  }

  /// The file an export must not end on, or null when there is none.
  AvoidFile? get exportAvoid => _unkeptFile(
    'That is the file you opened. It has columns the app does not keep, so '
    'Export cannot save over it. Choose another name.',
  );

  /// Run [export] and, when it delivered and nothing changed meanwhile, lift
  /// the leave warning about an unexported file.
  Future<void> countExport(Future<ExportOutcome> Function() export) async {
    final changes = _changes;
    final outcome = await export();
    if (outcome == ExportOutcome.saved && changes == _changes) {
      _exportedSinceChange = true;
    }
  }

  /// Ask whether to keep the recovery copy; see `close_guard.dart`. Null to
  /// stay, including when another question is already open. Without [ask],
  /// the copy is kept when nothing else holds the session, and the question
  /// comes only when entries could not be saved.
  Future<LeaveChoice?> _askLeave({bool ask = true}) async {
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
        hasEntries: hasEntries,
        stillSaving: stillSaving,
      );
      if (!ask && !guard.entriesUnsaved && !stillSaving) {
        return guard.onlyCopy ? LeaveChoice.keep : LeaveChoice.discard;
      }
      return await askLeaveSession(
        context,
        _workingPath,
        onlyCopy: guard.onlyCopy,
        copyMayBeStale: guard.copyMayBeStale,
        entriesUnsaved: guard.entriesUnsaved,
        stillSaving: stillSaving && hasEntries,
      );
    } finally {
      _leaveAsked = false;
    }
  }

  /// False when the user chose to stay. Otherwise refreshes the dataset's
  /// combined table when the visit was filed into one, then deletes the working
  /// copy if the user chose to discard it.
  ///
  /// A request that arrives while another leave or a New or Open refresh runs
  /// waits for it. A window close that waited shows the refresh's unread
  /// message in a dialog, since nothing else would let it be read.
  Future<bool> mayLeave({bool closingWindow = false}) async {
    final leaving = _leaving;
    final ending = _ending;
    if (leaving == null && ending == null) {
      _unreadSnack = null;
      return _startLeaving(closingWindow);
    }
    final bool may;
    if (leaving != null) {
      may = await leaving;
    } else {
      await ending;
      may = await (_leaving ?? _startLeaving(closingWindow));
    }
    final unread = _unreadSnack;
    if (may && closingWindow && unread != null && mounted) {
      await _acknowledge(unread);
    }
    if (may && closingWindow) await _acknowledging;
    return may;
  }

  Future<bool> _startLeaving(bool closingWindow) async {
    final run = _askThenLeave(closingWindow);
    _leaving = run;
    try {
      return await run;
    } finally {
      if (identical(_leaving, run)) _leaving = null;
    }
  }

  Future<bool> _askThenLeave(bool closingWindow) async {
    if (!mounted || _left) return true;
    final choice = await _askLeave();
    if (choice == null) return false;
    _left = true;
    await _endVisit(closingWindow: closingWindow);
    if (choice == LeaveChoice.discard) await discardWork(_workingPath);
    return true;
  }

  /// Back: leave the screen once [mayLeave] agrees, popping only this screen's
  /// route, so a dialog on top is never popped in its place.
  Future<void> leaveOnBack() async {
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    if (route == null || !await mayLeave() || !route.isActive) return;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  // Set once leaving was agreed, so a later request does not ask the question
  // again.
  bool _left = false;

  // The leave in progress, from the question to the discard, for a second
  // request to wait on.
  Future<bool>? _leaving;

  // What the last refresh said by snack bar, until a dialog has shown it: a
  // window close that waited for that refresh would otherwise close the window
  // before it can be read.
  String? _unreadSnack;

  /// The refresh of the combined table at the end of a visit, while one runs.
  Future<void>? _ending;

  /// Refresh the combined table of the dataset this visit was filed into. One
  /// at a time: a second request waits for the running one.
  Future<void> _endVisit({bool closingWindow = false}) {
    final running = _ending;
    if (running != null) return running;
    return _ending = _refreshTable(closingWindow)
        .whenComplete(() => _ending = null);
  }

  Future<void> _refreshTable(bool closingWindow) async {
    final root = _datasetRoot;
    if (root == null || !mounted) return;
    if (_savePath == null && !_saveRunning) return;
    _unreadSnack = null;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    const table = 'the combined table under $aggregateDerivativeDir/';
    const later =
        'The next merge from Reports or the next visit recorded into this '
        'dataset will refresh it.';
    String? say;
    if (_saveRunning) {
      say = 'A save was still running, so $table was not updated. $later';
    } else {
      final progress = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('Updating the combined table'),
            content: LinearProgressIndicator(),
          ),
        ),
      );
      unawaited(navigator.push(progress));
      final run = _refresh(root);
      try {
        say = await run.timeout(refreshTimeLimit);
      } on TimeoutException {
        unawaited(
          run.then<void>(
            (_) {},
            onError: (Object e) =>
                debugPrint('The refresh that timed out failed: $e'),
          ),
        );
        say =
            'Updating $table did not finish in time, so it may not include '
            'this visit. $later';
      } catch (e) {
        say = 'Could not update $table: $e. $later';
      }
      if (progress.isActive) navigator.removeRoute(progress);
    }
    if (say == null) return;
    final shown = say;
    if (closingWindow && mounted) {
      await _acknowledge(shown);
    } else {
      _unreadSnack = shown;
      messenger.showSnackBar(SnackBar(content: Text(shown)));
    }
  }

  // The message dialog a window close shows, so a second close waits for its OK
  // instead of closing the window under it.
  Future<void>? _acknowledging;

  Future<void> _acknowledge(String message) {
    _unreadSnack = null;
    final shown = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        title: const Text('Combined table'),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    _acknowledging = shown;
    return shown.whenComplete(() {
      if (identical(_acknowledging, shown)) _acknowledging = null;
    });
  }

  Future<String?> _refresh(String root) async {
    await debugRefreshHold?.call();
    return (await refreshDatasetAggregate(root)).notice;
  }
}

/// How long the refresh at the end of a visit may take before leaving goes on.
/// The refresh itself still runs to its end.
@visibleForTesting
Duration refreshTimeLimit = const Duration(seconds: 60);

/// Tests set this to count refreshes and keep one running while they look at
/// the screen.
@visibleForTesting
Future<void> Function()? debugRefreshHold;
