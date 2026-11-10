/// Reading an existing BIDS dataset, showing what a merge would do, and
/// writing it.
///
/// The plan itself is pure and lives in `core/bids_merge.dart`; this is the two
/// ways in and out of it. A folder on the desktop, a zip everywhere, over one
/// merge function, because the danger is in what gets overwritten and that must
/// not have two implementations.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, mapEquals, visibleForTesting;
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../core/bids.dart';
import '../core/bids_dataset.dart';
import '../core/bids_merge.dart';
import '../core/bids_sidecar.dart';
import '../core/safe_file.dart';
import '../core/session/aggregate.dart';
import '../core/session/tsv_kind.dart';
import '../report/upload_actions.dart';

/// Whether a picked directory can be written to. False on the tablets, where
/// it is a security-scoped path or a `content://` URI `dart:io` cannot open.
bool get canWriteChosenFolder =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// A dataset bigger than this is not something to round-trip through a tablet's
/// memory. Real DBS datasets carry imaging and run to gigabytes.
const int kMaxMergeZipBytes = 200 * 1024 * 1024;

/// Planned content of a binary file, such as a report, whose bytes travel
/// beside the plan. Never equal to [kUnreadContent], so an existing file at
/// that path is refused rather than kept.
const String kBinaryContent = '\u0000binary';

/// Tests set this to see which files [readDatasetDirectory] decodes.
@visibleForTesting
void Function(String path)? debugDatasetRead;

// Null while idle, so no finished future outlives the zone it was made in.
Future<void>? _datasetWrites;

/// Tests call this when one ends: a write its fake-async zone left unfinished
/// would otherwise hold up every later test.
@visibleForTesting
void resetDatasetQueue() => _datasetWrites = null;

/// Whether no write into a dataset is queued or running.
@visibleForTesting
bool get datasetQueueIdle => _datasetWrites == null;

/// Run [write] after every earlier write into a dataset folder has finished,
/// whether or not anyone still waits for it. Writers share one `.tmp` file per
/// target, so two at once can overwrite or rename away each other's.
@visibleForTesting
Future<T> inDatasetQueue<T>(Future<T> Function() write) {
  final previous = _datasetWrites;
  final run = previous == null ? write() : previous.then((_) => write());
  late final Future<void> tail;
  tail = run.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
    if (identical(_datasetWrites, tail)) _datasetWrites = null;
  });
  _datasetWrites = tail;
  return run;
}

bool _isTextPath(String path) =>
    path.endsWith('.tsv') ||
    path.endsWith('.json') ||
    path.endsWith('.md') ||
    path.endsWith('README');

/// Every file of the dataset rooted at [root], paths relative to it.
///
/// Only the text files the merge can reason about are decoded. Imaging and
/// anything else is recorded by path alone, which is all that is needed: those
/// paths are never written, and knowing they exist is what stops a collision.
/// With [only], files whose relative path it rejects are left out entirely.
Future<List<DatasetFile>> readDatasetDirectory(
  String root, {
  bool Function(String path)? only,
}) async {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  final out = <DatasetFile>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = entity.path
        .substring(root.length)
        .replaceAll(r'\', '/')
        .replaceAll(RegExp('^/+'), '');
    if (rel.isEmpty || (only != null && !only(rel))) continue;
    if (!_isTextPath(rel)) {
      out.add((path: rel, content: kUnreadContent));
      continue;
    }
    try {
      debugDatasetRead?.call(rel);
      out.add((path: rel, content: await entity.readAsString()));
    } catch (_) {
      out.add((path: rel, content: kUnreadContent));
    }
  }
  return out;
}

/// The same, out of an exported `.zip`.
List<DatasetFile> readDatasetZip(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final out = <DatasetFile>[];
  for (final file in archive.files) {
    if (!file.isFile) continue;
    if (!_isTextPath(file.name)) {
      out.add((path: file.name, content: kUnreadContent));
      continue;
    }
    try {
      out.add((path: file.name, content: utf8.decode(file.readBytes()!)));
    } catch (_) {
      out.add((path: file.name, content: kUnreadContent));
    }
  }
  return out;
}

/// The `.bidsignore` line that keeps the validator from failing on the
/// `<file>.bak-<timestamp>` copies a folder merge leaves beside what it replaces.
const String kBackupIgnoreLine = '*.bak-*';

/// Said when [ensureBackupsIgnored] could not do its job.
const String kBidsignoreWarning =
    '.bidsignore could not be updated, so the BIDS validator may flag the '
    '.bak- copies.';

/// Make sure `.bidsignore` at [root] lists [kBackupIgnoreLine], keeping its
/// lines. Best effort, since the copies are made: false when it cannot be done.
Future<bool> ensureBackupsIgnored(String root) async {
  final file = File('$root/.bidsignore');
  try {
    var text = '';
    if (file.existsSync()) {
      text = await file.readAsString();
      final lines = text.split(RegExp(r'\r?\n'));
      if (lines.any((line) => line.trim() == kBackupIgnoreLine)) return true;
      if (text.isNotEmpty && !text.endsWith('\n')) text += '\n';
    }
    await writeStringAtomic(file.path, '$text$kBackupIgnoreLine\n');
    return true;
  } on FormatException {
    return false;
  } on FileSystemException {
    try {
      File('${file.path}.tmp').deleteSync();
    } on FileSystemException {
      // The failure is already reported; a stray temp file is not worth more.
    }
    return false;
  }
}

/// The task entities this app records under.
const _appTasks = {'programming', 'notes'};

/// The combined table of the recorded session and notes TSVs in [files], each
/// row named after the file it came from, and the recorded files it leaves out
/// with a reason each.
///
/// A file is this app's when its header is one of this app's, its task is one
/// of [_appTasks], or its sidecar names this app as the generator. Any other
/// file under `beh/` belongs to another lab and is not reported.
({AggregateResult table, List<LeftOutFile> leftOut}) _combinedTable(
  List<DatasetFile> files,
) {
  final contents = {for (final f in files) f.path: f.content};
  bool writtenByThisApp(String tsvPath) {
    final sidecar = contents[tsvPath.replaceFirst(RegExp(r'\.tsv$'), '.json')];
    if (sidecar == null || sidecar == kUnreadContent) return false;
    try {
      final generated = (jsonDecode(sidecar) as Map)['GeneratedBy'];
      return generated is List &&
          generated.any((g) => g is Map && g['Name'] == appName);
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  final sources = <AggregateSource>[];
  final pathsByName = <String, List<String>>{};
  final leftOut = <LeftOutFile>[];
  for (final f in recordedFiles(files).values.expand((list) => list)) {
    final name = f.path.split('/').last;
    final kind = f.content == kUnreadContent ? null : sniffTsvKind(f.content);
    final isKind = kind == TsvKind.programming || kind == TsvKind.notes;
    Uploaded? upload;
    if (isKind) {
      try {
        upload = classifyUpload(name, f.content).file;
      } catch (_) {}
    }
    if (upload == null) {
      if (isKind ||
          _appTasks.contains(BidsName.parse(name)?.task) ||
          writtenByThisApp(f.path)) {
        leftOut.add((
          path: f.path,
          reason: kind == null
              ? 'could not be read as text'
              : 'not readable as a session or notes file',
        ));
      }
      continue;
    }
    sources.addAll(aggregateSources([upload]));
    (pathsByName[name] ??= []).add(f.path);
  }

  final table = buildAggregate(sources);
  final reasons = <String, List<String>>{};
  for (final skip in table.skipped) {
    (reasons[skip.filename] ??= []).add(skip.reason);
  }
  for (final MapEntry(key: name, value: why) in reasons.entries) {
    final paths = pathsByName[name]!;
    final skipped = paths.sublist(paths.length - why.length);
    for (final (i, path) in skipped.indexed) {
      leftOut.add((path: path, reason: why[i]));
    }
  }
  leftOut.sort((a, b) => a.path.compareTo(b.path));
  return (table: table, leftOut: leftOut);
}

/// [planned] with the combined table rebuilt from every session and notes TSV
/// the dataset [existing] will hold after the merge. An existing table is left
/// as it is when no row can be built, and its files are then `keptAsIs`.
MergePlan withRebuiltAggregate(
  List<DatasetFile> existing,
  MergePlan planned,
  Map<String, dynamic> contract,
) {
  const prefix = '$aggregateDerivativeDir/';
  List<T> outside<T>(List<T> items, String Function(T) path) => [
    for (final item in items)
      if (!path(item).startsWith(prefix)) item,
  ];
  String same(String path) => path;
  final write = outside(planned.write, (f) => f.path);
  final added = outside(planned.added, same);
  final rowMerged = outside(planned.rowMerged, same);
  final rebuilt = outside(planned.rebuilt, same);

  final have = {for (final f in existing) f.path: f.content};
  final combined = _combinedTable([
    for (final f in existing)
      if (!write.any((w) => w.path == f.path)) f,
    for (final f in write)
      if (f.content != kBinaryContent) f,
  ]);
  final aggregate = combined.table;
  if (aggregate.rowCount > 0) {
    final description = derivativeDescription(
      dir: aggregateDerivativeDir,
      name: '$appName combined sessions',
      appName: appName,
      appVersion: appVersion,
      repoUrl: repoUrl,
    );
    final derived = <DatasetFile>[
      (path: '$prefix$aggregateStem.tsv', content: aggregate.tsv),
      (
        path: '$prefix$aggregateStem.json',
        content: aggregateSidecarJson(contract, appVersion: appVersion),
      ),
    ];
    for (final f in derived) {
      if (have[f.path] == f.content) continue;
      write.add(f);
      (have.containsKey(f.path) ? rebuilt : added).add(f.path);
    }
    if (!have.containsKey(description.path)) {
      write.add(description);
      added.add(description.path);
    }
  }
  final keptAsIs = outside(planned.keptAsIs, same);
  if (!write.any((f) => f.path.startsWith(prefix))) {
    keptAsIs.addAll(
      [
        '$prefix$aggregateStem.tsv',
        '$prefix$aggregateStem.json',
        '${prefix}dataset_description.json',
      ].where(have.containsKey),
    );
  }
  return (
    write: write,
    added: added,
    rowMerged: rowMerged,
    rebuilt: rebuilt,
    keptAsIs: keptAsIs,
    unread: planned.unread,
    refused: outside(planned.refused, same),
    leftOut: [...planned.leftOut, ...combined.leftOut],
  );
}

/// Rebuild the combined table of the dataset at [root] by the rules of a merge
/// from Reports, writing only when it differs from the one there. Reads the
/// recorded files, their sidecars and the table's folder, nothing else; raw
/// data is never written. `notice` is what to tell the user: files left out
/// and why, or a `.bidsignore` warning; null when there is nothing to say.
/// Throws when the folder cannot be read or the table cannot be written.
Future<({List<LeftOutFile> leftOut, String? notice})> refreshDatasetAggregate(
  String root,
) => inDatasetQueue(() => _refreshDatasetAggregate(root));

Future<({List<LeftOutFile> leftOut, String? notice})> _refreshDatasetAggregate(
  String root,
) async {
  final contract = await loadTsvContract();
  bool recorded(String path) =>
      recordedFiles([(path: path, content: '')]).isNotEmpty;
  final existing = await readDatasetDirectory(
    root,
    only: (path) =>
        path.startsWith('$aggregateDerivativeDir/') ||
        recorded(path) ||
        (path.endsWith('.json') &&
            recorded(path.replaceFirst(RegExp(r'\.json$'), '.tsv'))),
  );
  final plan = withRebuiltAggregate(
    existing,
    planBidsMerge(existing, const []),
    contract,
  );
  final warning = await _applyMerge(root, plan);
  final notice = [
    if (plan.leftOut.isNotEmpty) leftOutNotice(plan.leftOut),
    ?warning,
  ].join(' ');
  return (leftOut: plan.leftOut, notice: notice.isEmpty ? null : notice);
}

/// Write [plan] into the dataset at [root].
///
/// Ordered so an interruption can never leave the dataset claiming files that
/// do not exist: the index files are backed up first, then the new leaf files
/// (a pure addition, where a half-done write leaves an unreferenced file the
/// validator will see and nothing is destroyed), then the indexes themselves.
///
/// [binary] holds the bytes of planned files whose content is [kBinaryContent].
///
/// Returns [kBidsignoreWarning] when backups were made and `.bidsignore` could
/// not be updated to hide them, else null.
///
/// With [plannedAgainst], the files the plan writes or checks are read again
/// once the write's turn comes, and a file whose content differs from the one
/// planned against, or that appeared, throws [DatasetChangedException] with
/// nothing written.
Future<String?> applyMergeToDirectory(
  String root,
  MergePlan plan, {
  Map<String, Uint8List> binary = const {},
  List<DatasetFile>? plannedAgainst,
}) => inDatasetQueue(() async {
  if (plannedAgainst != null) {
    await _requireUnchanged(root, plan, plannedAgainst);
  }
  return _applyMerge(root, plan, binary: binary);
});

/// Thrown when the dataset changed between planning a merge and applying it.
class DatasetChangedException implements Exception {
  const DatasetChangedException();

  @override
  String toString() =>
      'The BIDS folder changed while the merge was being prepared, so nothing '
      'was written. Run the merge again.';
}

Future<void> _requireUnchanged(
  String root,
  MergePlan plan,
  List<DatasetFile> planned,
) async {
  final paths = {
    for (final f in plan.write) f.path,
    ...plan.refused,
    ...plan.keptAsIs,
  };
  final before = {
    for (final f in planned)
      if (paths.contains(f.path)) f.path: f.content,
  };
  final now = {
    for (final f in await readDatasetDirectory(root, only: paths.contains))
      f.path: f.content,
  };
  if (!mapEquals(before, now)) throw const DatasetChangedException();
}

///
/// Without [backup], as while a visit is recorded, no `.bak-` copies are left.
Future<String?> _applyMerge(
  String root,
  MergePlan plan, {
  Map<String, Uint8List> binary = const {},
  bool backup = true,
}) async {
  String full(String rel) => '$root/$rel';

  final stamp = DateTime.now().millisecondsSinceEpoch;
  var backedUp = false;
  for (final path
      in backup ? [...plan.rowMerged, ...plan.rebuilt] : const <String>[]) {
    final file = File(full(path));
    if (file.existsSync()) {
      await file.copy('${full(path)}.bak-$stamp');
      backedUp = true;
    }
  }
  final warning = backedUp && !await ensureBackupsIgnored(root)
      ? kBidsignoreWarning
      : null;

  final indexes = {...plan.rowMerged, ...plan.rebuilt};
  for (final pass in [false, true]) {
    for (final file in plan.write) {
      if (indexes.contains(file.path) != pass) continue;
      final target = File(full(file.path));
      await target.parent.create(recursive: true);
      if (binary[file.path] case final bytes?) {
        await target.writeAsBytes(bytes, flush: true);
      } else {
        await writeStringAtomic(target.path, file.content);
      }
    }
  }
  return warning;
}

/// A report filed under [reportsDerivativeDir] at the path of the visit in
/// [visitFiles], with the derivative's description when [existing] has none.
/// The report's own entry carries [kBinaryContent]; its bytes go beside the
/// plan under the returned path.
({List<DatasetFile> files, String path}) reportIntoDataset(
  List<DatasetFile> visitFiles,
  String extension,
  List<DatasetFile> existing,
) {
  final visit = visitFiles
      .map((f) => f.path)
      .firstWhere((p) => p.contains('/beh/') && p.endsWith('_beh.tsv'));
  final path =
      '$reportsDerivativeDir/'
      '${visit.replaceAll(RegExp(r'_beh\.tsv$'), '')}_report.$extension';
  final description = derivativeDescription(
    dir: reportsDerivativeDir,
    name: '$appName reports',
    appName: appName,
    appVersion: appVersion,
    repoUrl: repoUrl,
  );
  return (
    files: [
      if (!existing.any((f) => f.path == description.path)) description,
      (path: path, content: kBinaryContent),
    ],
    path: path,
  );
}

/// The merged dataset as a new zip, leaving the original untouched. Every
/// entry of [source] that the plan does not write is copied byte for byte, so
/// imaging, PDFs and other files the merge never decodes survive.
Uint8List mergedZip(
  Uint8List source,
  MergePlan plan, {
  Map<String, Uint8List> binary = const {},
}) {
  final written = {for (final f in plan.write) f.path};
  final archive = Archive();
  for (final file in ZipDecoder().decodeBytes(source).files) {
    if (!file.isFile || written.contains(file.name)) continue;
    archive.addFile(ArchiveFile.bytes(file.name, file.readBytes()!));
  }
  for (final f in plan.write) {
    if (f.content == kBinaryContent) {
      if (binary[f.path] case final bytes?) {
        archive.addFile(ArchiveFile.bytes(f.path, bytes));
      }
    } else {
      archive.addFile(ArchiveFile.bytes(f.path, utf8.encode(f.content)));
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// What a folder must hold to be a BIDS dataset, said wherever one is chosen.
const kBidsFolderRule =
    'A BIDS dataset folder has a dataset_description.json at its top level '
    'and one sub-<participant> folder per participant, listed in '
    'participants.tsv.';

/// Where an added visit goes and what happens to the combined table in [plan].
String _addRule(MergePlan plan) {
  const dir = '$aggregateDerivativeDir/';
  bool writes(String path) => plan.write.any((f) => f.path == path);
  // Rows exist whenever anything under [dir] is written, so an unwritten table
  // beside a written description is current.
  final String fate;
  if (plan.added.contains('$dir$aggregateStem.tsv')) {
    fate = _kBidsTableCreated;
  } else if (writes('$dir$aggregateStem.tsv') ||
      writes('$dir$aggregateStem.json')) {
    fate = _kBidsTableRebuilt;
  } else if (plan.keptAsIs.contains('$dir$aggregateStem.tsv') ||
      writes('${dir}dataset_description.json')) {
    fate = _kBidsTableKept;
  } else {
    fate = _kBidsTableNotCreated;
  }
  return [
    _kBidsPlacement,
    if (plan.unread.isEmpty) _kBidsIndexRows,
    _kBidsNothingChanged,
    'The combined table under $dir',
    fate,
  ].join(' ');
}

const _kBidsPlacement =
    'Each visit is added as sub-<participant>/ses-<session>/beh/, as a '
    '_beh.tsv with its .json sidecar.';
const _kBidsIndexRows =
    'The participant gets a row in participants.tsv and the visit a row in '
    "that session's scans.tsv.";
const _kBidsNothingChanged =
    'Recorded files already in the BIDS folder are never changed.';
const _kBidsTableCreated =
    'is created from every session and notes file in the BIDS folder.';
const _kBidsTableRebuilt =
    'is rebuilt from every session and notes file in the BIDS folder.';
const _kBidsTableKept =
    'is left as it is, because it already matches the BIDS folder or no '
    'recording in the BIDS folder could be included.';
const _kBidsTableNotCreated =
    'is not created, because no recording in the BIDS folder could be included.';

/// The answer to [checkDatasetFolder].
enum FolderCheck { proceed, cancel, chooseAnother }

/// Check the dataset chosen as [label] before anything is added to it.
///
/// A BIDS dataset goes ahead. An empty folder can become one: the add then
/// writes its dataset_description.json, README and participants.tsv as well.
/// Anything else is refused with what a dataset needs, because adding to it
/// would scatter BIDS files through a folder that is not one.
Future<FolderCheck> checkDatasetFolder(
  BuildContext context,
  String label,
  List<DatasetFile> existing, {
  String chooseAnother = 'Choose another folder',
}) async {
  final kind = datasetFolderKind(existing);
  if (kind == DatasetFolderKind.dataset) return FolderCheck.proceed;
  final empty = kind == DatasetFolderKind.empty;
  final answer = await showDialog<FolderCheck>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        empty ? 'Start a new BIDS folder here?' : 'Not a BIDS folder',
      ),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Text(
          '$label\n\n$kBidsFolderRule\n\n'
          '${empty ? 'This folder is empty, so it can become one: its '
                    'dataset_description.json, README and participants.tsv '
                    'are written along with the first visit.' : 'This folder has other content and no '
                    'dataset_description.json. Choose the top-level folder of a '
                    'BIDS folder, or an empty folder to start one.'}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, FolderCheck.cancel),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            empty ? FolderCheck.proceed : FolderCheck.chooseAnother,
          ),
          child: Text(empty ? 'Start a BIDS folder' : chooseAnother),
        ),
      ],
    ),
  );
  return answer ?? FolderCheck.cancel;
}

/// Ask for a dataset folder until the one chosen is, or can become, a BIDS
/// dataset. Null when cancelled.
Future<({String root, List<DatasetFile> existing})?> pickCheckedDatasetFolder(
  BuildContext context,
) async {
  while (true) {
    final root = await pickDatasetFolder();
    if (root == null || !context.mounted) return null;
    final List<DatasetFile> existing;
    try {
      existing = await readDatasetDirectory(root);
    } on FileSystemException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read that folder: $e')),
        );
      }
      return null;
    }
    if (!context.mounted) return null;
    switch (await checkDatasetFolder(context, root, existing)) {
      case FolderCheck.proceed:
        return (root: root, existing: existing);
      case FolderCheck.cancel:
        return null;
      case FolderCheck.chooseAnother:
        continue;
    }
  }
}

/// File [entry] into the BIDS folder at [root]: its files at their BIDS
/// paths, and its rows in `participants.tsv`, `sessions.tsv` and `scans.tsv`
/// added or brought up to date. Returns the `beh/` file's path and any
/// warning from the write, or null when the folder already holds a different
/// recording under that name.
///
/// Once [filed], the entry's own files are rewritten on every save; before,
/// a file already at that path is refused rather than overwritten. Only the
/// paths the entry touches are read, so a large folder costs nothing extra.
Future<({String path, List<String> unread, String? warning})?> fileIntoDataset({
  required String root,
  required DatasetEntry entry,
  bool filed = false,
}) => inDatasetQueue(
  () => _fileIntoDataset(root: root, entry: entry, filed: filed),
);

Future<({String path, List<String> unread, String? warning})?>
_fileIntoDataset({
  required String root,
  required DatasetEntry entry,
  bool filed = false,
}) async {
  final contract = await loadTsvContract();
  final incoming = buildBidsDataset(
    [entry],
    contract: contract,
    appName: appName,
    appVersion: appVersion,
    repoUrl: repoUrl,
  );
  final existing = <DatasetFile>[];
  for (final f in incoming) {
    final file = File('$root/${f.path}');
    if (file.existsSync()) {
      existing.add((path: f.path, content: await file.readAsString()));
    }
  }
  final dir = entry.name.relativeDir;
  final plan = planBidsMerge(
    existing,
    incoming,
    upsert: true,
    overwrite: filed
        ? {'$dir/${entry.name.filename}', '$dir/${entry.name.sidecarFilename}'}
        : const {},
  );
  if (plan.refused.isNotEmpty) return null;
  final warning = await _applyMerge(root, plan, backup: false);
  return (
    path: '$root/$dir/${entry.name.filename}',
    unread: plan.unread,
    warning: warning,
  );
}

/// Show exactly what the merge will do and wait for a yes.
///
/// This is a gate, not a courtesy: writing into a dataset the app did not
/// create is the one operation here with no undo.
///
/// [renumbered] lists the files moved to a free run because their name was
/// taken by a different recording. [keepsBackups] is false when the merge
/// writes a new zip, which keeps no `.bak-` copies.
Future<bool> confirmMerge(
  BuildContext context,
  MergePlan plan,
  String target, {
  List<String> renumbered = const [],
  bool keepsBackups = true,
}) async {
  final theme = Theme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add to this BIDS folder?'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(target, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(_addRule(plan), style: theme.textTheme.bodySmall),
              if (plan.leftOut.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  leftOutNotice(plan.leftOut),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (plan.unread.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  unreadIndexNotice(plan.unread),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              for (final (label, paths) in [
                ('Added', plan.added),
                ('Filed under the next free run', renumbered),
                ('Gaining rows', plan.rowMerged),
                (
                  keepsBackups
                      ? 'Rebuilt (previous copy kept as .bak-...)'
                      : 'Rebuilt',
                  plan.rebuilt,
                ),
                ('Left unchanged', shownUnwritten(plan).unchanged),
                ('Refused: already recorded', shownUnwritten(plan).refused),
              ])
                if (paths.isNotEmpty) ...[
                  Text(
                    '$label (${paths.length})',
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final p in paths.take(12))
                    Text('  $p', style: theme.textTheme.bodySmall),
                  if (paths.length > 12)
                    Text(
                      '  and ${paths.length - 12} more',
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 8),
                ],
              Text(
                'Your dataset_description.json, README and participants.json '
                'are not rewritten, and participants.tsv keeps every column '
                'and row it already has.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: plan.write.isEmpty
              ? null
              : () => Navigator.pop(context, true),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// What to file from a single session: its TSV, its report, or both, and the
/// report's format. Null when cancelled.
Future<({bool tsv, bool report, bool docx})?> askSingleSessionAdd(
  BuildContext context,
) {
  var tsv = true;
  var report = false;
  var docx = false;
  return showDialog<({bool tsv, bool report, bool docx})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Add to a BIDS folder'),
        scrollable: true,
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                value: tsv,
                onChanged: (v) => setState(() => tsv = v ?? false),
                title: const Text('Session file and sidecar'),
                subtitle: const Text(
                  'Filed under sub-<participant>/ses-<session>/beh/.',
                ),
              ),
              CheckboxListTile(
                value: report,
                onChanged: (v) => setState(() => report = v ?? false),
                title: const Text('Report'),
                subtitle: const Text(
                  'Filed under $reportsDerivativeDir/, beside the same '
                  'participant and session.',
                ),
              ),
              if (report)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('PDF')),
                      ButtonSegment(value: true, label: Text('Word')),
                    ],
                    selected: {docx},
                    onSelectionChanged: (s) => setState(() => docx = s.single),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: tsv || report
                ? () => Navigator.pop(context, (
                    tsv: tsv,
                    report: report,
                    docx: docx,
                  ))
                : null,
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}

/// Ask for the dataset folder. Null when cancelled or unavailable.
Future<String?> pickDatasetFolder() async {
  try {
    return await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose the BIDS folder',
    );
  } catch (_) {
    return null;
  }
}

/// A dataset `.zip` picked from storage and read. Null when cancelled or when
/// it cannot be used, with the reason passed to [say].
Future<({String name, Uint8List bytes, List<DatasetFile> files})?>
pickDatasetZip(void Function(String) say) async {
  final PlatformFile? picked;
  try {
    picked = await FilePicker.pickFile(type: FileType.any);
  } catch (e) {
    say('Could not open the file picker. ($e)');
    return null;
  }
  if (picked == null) return null;
  final size = await picked.length();
  if (size > kMaxMergeZipBytes) {
    // Decoding a dataset that carries imaging would run a tablet out of
    // memory, so it is refused with its size rather than attempted.
    say(
      'That BIDS folder is ${(size / (1024 * 1024)).round()} MB. A zip works up '
      'to ${kMaxMergeZipBytes ~/ (1024 * 1024)} MB; use the desktop app.',
    );
    return null;
  }
  try {
    final bytes = await picked.readAsBytes();
    return (name: picked.name, bytes: bytes, files: readDatasetZip(bytes));
  } catch (e) {
    say('Could not read that BIDS folder: $e');
    return null;
  }
}

/// Stands in for the dataset picker in tests: the folder and its files.
({String? root, List<DatasetFile> files})? debugDataset;

/// The recorded TSVs of a dataset the user picks, narrowed to the participants
/// they choose: a folder on the desktop, the dataset `.zip` on the tablets.
/// `root` is the folder, null for a zip. Null when cancelled, with any reason
/// passed to [say].
Future<({String? root, List<({String name, String content})> files})?>
loadDatasetTsvs(BuildContext context, void Function(String) say) async {
  final ({String? root, List<DatasetFile> files}) source;
  if (debugDataset case final d?) {
    source = d;
  } else if (canWriteChosenFolder) {
    final root = await pickDatasetFolder();
    if (root == null) return null;
    try {
      source = (root: root, files: await readDatasetDirectory(root));
    } catch (e) {
      say('Could not read that folder: $e');
      return null;
    }
  } else {
    final zip = await pickDatasetZip(say);
    if (zip == null) return null;
    source = (root: null, files: zip.files);
  }
  final byParticipant = {
    for (final MapEntry(:key, :value) in recordedFiles(
      source.files,
      inZip: source.root == null,
    ).entries)
      if (value.any((f) => f.content != kUnreadContent))
        key: [
          for (final f in value)
            if (f.content != kUnreadContent) f,
        ],
  };
  if (byParticipant.isEmpty) {
    say('No session or notes files found there. $kBidsFolderRule');
    return null;
  }
  if (!context.mounted) return null;
  final chosen = await showDialog<Set<String>>(
    context: context,
    builder: (_) => _ParticipantsDialog(byParticipant),
  );
  if (chosen == null || chosen.isEmpty) return null;
  return (
    root: source.root,
    files: [
      for (final p in chosen)
        for (final f in byParticipant[p]!)
          (name: f.path.split('/').last, content: f.content),
    ],
  );
}

class _ParticipantsDialog extends StatefulWidget {
  const _ParticipantsDialog(this.byParticipant);

  final Map<String, List<DatasetFile>> byParticipant;

  @override
  State<_ParticipantsDialog> createState() => _ParticipantsDialogState();
}

class _ParticipantsDialogState extends State<_ParticipantsDialog> {
  late final Set<String> _chosen = {...widget.byParticipant.keys};

  @override
  Widget build(BuildContext context) {
    final all = _chosen.length == widget.byParticipant.length;
    return AlertDialog(
      title: const Text('Import which participants?'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final MapEntry(key: p, value: files)
                in widget.byParticipant.entries)
              CheckboxListTile(
                dense: true,
                value: _chosen.contains(p),
                title: Text('sub-$p'),
                subtitle: Text(
                  '${files.length} file${files.length == 1 ? '' : 's'}',
                ),
                onChanged: (on) => setState(
                  () => on == true ? _chosen.add(p) : _chosen.remove(p),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(
            () => all
                ? _chosen.clear()
                : _chosen.addAll(widget.byParticipant.keys),
          ),
          child: Text(all ? 'Select none' : 'Select all'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.pop(context, _chosen),
          child: const Text('Import'),
        ),
      ],
    );
  }
}

/// Write the combined table and its [sidecar] into the dataset at [root],
/// where BIDS puts a cross-session derivation. Returns the table's path.
///
/// The table is derived from the raw files, so a newer one replaces it; the
/// previous copy is kept beside it, and the raw tree is never written.
///
/// When a backup is made and `.bidsignore` cannot be updated to hide it, the
/// warning is [kBidsignoreWarning] and the write goes on.
Future<({String path, String? warning})> writeAggregateInto(
  String root, {
  required String tsv,
  required String sidecar,
}) => inDatasetQueue(() => _writeAggregateInto(root, tsv, sidecar));

Future<({String path, String? warning})> _writeAggregateInto(
  String root,
  String tsv,
  String sidecar,
) async {
  final dir = '$root/$aggregateDerivativeDir';
  await Directory(dir).create(recursive: true);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  var backedUp = false;
  for (final (name, content) in [
    ('$aggregateStem.tsv', tsv),
    ('$aggregateStem.json', sidecar),
  ]) {
    final file = File('$dir/$name');
    if (file.existsSync()) {
      if (await file.readAsString() == content) continue;
      await file.copy('${file.path}.bak-$stamp');
      backedUp = true;
    }
    await writeStringAtomic(file.path, content);
  }
  final warning = backedUp && !await ensureBackupsIgnored(root)
      ? kBidsignoreWarning
      : null;
  final description = derivativeDescription(
    dir: aggregateDerivativeDir,
    name: '$appName combined sessions',
    appName: appName,
    appVersion: appVersion,
    repoUrl: repoUrl,
  );
  final described = File('$root/${description.path}');
  if (!described.existsSync()) {
    await writeStringAtomic(described.path, description.content);
  }
  return (path: '$dir/$aggregateStem.tsv', warning: warning);
}

/// Save the combined table into the dataset at [root] (see
/// [writeAggregateInto]), say so, and ask whether to save a copy elsewhere
/// too. Throws when the write fails.
Future<bool> saveAggregateInto(
  BuildContext context,
  String root, {
  required String tsv,
  required String sidecar,
  required String summary,
}) async {
  final (:path, :warning) = await writeAggregateInto(
    root,
    tsv: tsv,
    sidecar: sidecar,
  );
  if (!context.mounted) return false;
  final copy = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Saved into the BIDS folder'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Text(
          '$summary, saved with its sidecar as\n$path\n\n'
          '${warning == null ? '' : '$warning\n\n'}'
          'Save a copy somewhere else too?',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('No'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Save a copy'),
        ),
      ],
    ),
  );
  return copy ?? false;
}

/// A zip of text files, by name.
Uint8List textZip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, text) {
    archive.addFile(ArchiveFile.bytes(name, utf8.encode(text)));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
