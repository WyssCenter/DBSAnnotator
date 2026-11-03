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
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../core/bids.dart';
import '../core/bids_dataset.dart';
import '../core/bids_merge.dart';
import '../core/bids_sidecar.dart';
import '../core/safe_file.dart';
import 'bids_export.dart';

/// Whether a picked directory can be written to. False on the tablets, where
/// it is a security-scoped path or a `content://` URI `dart:io` cannot open.
bool get canWriteChosenFolder =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// A dataset bigger than this is not something to round-trip through a tablet's
/// memory. Real DBS datasets carry imaging and run to gigabytes.
const int kMaxMergeZipBytes = 200 * 1024 * 1024;

/// Content recorded for a file whose bytes were not read: it exists, so a path
/// collision is still detected, but it can never compare equal to anything the
/// app would write.
const String kUnreadContent = '\u0000unread';

/// Planned content of a binary file, such as a report, whose bytes travel
/// beside the plan. Never equal to [kUnreadContent], so an existing file at
/// that path is refused rather than kept.
const String kBinaryContent = '\u0000binary';

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
Future<List<DatasetFile>> readDatasetDirectory(String root) async {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  final out = <DatasetFile>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = entity.path
        .substring(root.length)
        .replaceAll(r'\', '/')
        .replaceAll(RegExp('^/+'), '');
    if (rel.isEmpty) continue;
    if (!_isTextPath(rel)) {
      out.add((path: rel, content: kUnreadContent));
      continue;
    }
    try {
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

/// Write [plan] into the dataset at [root].
///
/// Ordered so an interruption can never leave the dataset claiming files that
/// do not exist: the index files are backed up first, then the new leaf files
/// (a pure addition, where a half-done write leaves an unreferenced file the
/// validator will see and nothing is destroyed), then the indexes themselves.
///
/// [binary] holds the bytes of planned files whose content is [kBinaryContent].
Future<void> applyMergeToDirectory(
  String root,
  MergePlan plan, {
  Map<String, Uint8List> binary = const {},
}) async {
  String full(String rel) => '$root/$rel';

  final stamp = DateTime.now().millisecondsSinceEpoch;
  for (final path in plan.rowMerged) {
    final file = File(full(path));
    if (file.existsSync()) await file.copy('${full(path)}.bak-$stamp');
  }

  final indexes = {...plan.rowMerged};
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

/// The merged dataset as a new zip, leaving the original untouched.
Uint8List mergedZip(
  List<DatasetFile> existing,
  MergePlan plan, {
  Map<String, Uint8List> binary = const {},
}) {
  final byPath = {for (final f in existing) f.path: f.content};
  for (final f in plan.write) {
    byPath[f.path] = f.content;
  }
  final archive = Archive();
  for (final path in byPath.keys.toList()..sort()) {
    if (byPath[path] == kBinaryContent) {
      if (binary[path] case final bytes?) {
        archive.addFile(ArchiveFile.bytes(path, bytes));
      }
      continue;
    }
    final content = byPath[path]!;
    // A file whose bytes were never read cannot be re-emitted, and writing a
    // placeholder in its place would corrupt it.
    if (content == kUnreadContent) continue;
    archive.addFile(ArchiveFile.bytes(path, utf8.encode(content)));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// What a folder must hold to be a BIDS dataset, said wherever one is chosen.
const kBidsFolderRule =
    'A BIDS dataset folder has a dataset_description.json at its top level '
    'and one sub-<participant> folder per participant, listed in '
    'participants.tsv.';

/// Where an added visit goes, said on every add.
const kBidsAddRule =
    'Each visit is added as sub-<participant>/ses-<session>/beh/, as a '
    '_beh.tsv with its .json sidecar. The participant gets a row in '
    'participants.tsv and the visit a row in that session\'s scans.tsv. '
    'Nothing already in the dataset is changed.';

/// Said where recording into a dataset is offered but cannot be done.
const kDatasetDesktopOnly =
    'Recording into a dataset needs the desktop app, which can write into a '
    'chosen folder. Record a loose TSV here and add it to a dataset later '
    'from Reports > Add.';

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
        empty ? 'Start a new BIDS dataset here?' : 'Not a BIDS dataset',
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
                    'BIDS dataset, or an empty folder to start one.'}',
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
          child: Text(empty ? 'Start a dataset' : chooseAnother),
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
    final existing = await readDatasetDirectory(root);
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

/// Ask whether a new recording is a loose file or goes into a dataset, and
/// which one. [what] names the recording in the dialogs: "this visit".
/// `root` is null for a loose file.
Future<({String? root, BidsName name})?> askNewTarget(
  BuildContext context,
  BidsName proposed, {
  required String what,
}) async {
  final theme = Theme.of(context);
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Where should $what be saved?'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A loose TSV goes wherever you choose. Into a dataset, it is '
              'filed at its BIDS path and the dataset index files are kept up '
              'to date as you record.',
            ),
            if (!canWriteChosenFolder) ...[
              const SizedBox(height: 8),
              Text(kDatasetDesktopOnly, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'loose'),
          child: const Text('Loose TSV'),
        ),
        FilledButton(
          onPressed: canWriteChosenFolder
              ? () => Navigator.pop(context, 'dataset')
              : null,
          child: const Text('Into a dataset'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return null;
  if (choice == 'loose') return (root: null, name: proposed);

  final folder = await pickCheckedDatasetFolder(context);
  if (folder == null || !context.mounted) return null;
  final name = nextFreeRun(proposed, {for (final f in folder.existing) f.path});
  if (!await confirmRecordInto(context, folder.root, name, what: what)) {
    return null;
  }
  return (root: folder.root, name: name);
}

/// Say where a recording filed straight into a dataset will go.
Future<bool> confirmRecordInto(
  BuildContext context,
  String root,
  BidsName name, {
  required String what,
}) async {
  final theme = Theme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Record into this dataset?'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(root, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(
              '${what[0].toUpperCase()}${what.substring(1)} will be filed as:',
            ),
            Text(
              '  ${name.relativeDir}/${name.filename}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'when the first entry is recorded, and updated at every entry '
              'after that. $kBidsAddRule',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Record here'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// File one recorded TSV of [kind] into the dataset at [root] as [name]: the
/// TSV and its sidecar at the BIDS path, and the dataset index files brought
/// up to date. Returns the file's path, or null when the dataset already
/// holds it.
///
/// Goes through [planBidsMerge] like every other write into a dataset, so a
/// `participants.tsv` carrying the study's own columns keeps them, and a file
/// already filed there is refused rather than overwritten.
Future<String?> fileIntoDataset({
  required String root,
  required BidsName name,
  required String tsv,
  required String kind,
  required String acqTime,
}) async {
  final contract = await loadTsvContract();
  final incoming = buildBidsDataset(
    [
      datasetEntry(
        name: name,
        tsv: tsv,
        contract: contract,
        kind: kind,
        acqTime: acqTime,
      ),
    ],
    appName: appName,
    appVersion: appVersion,
    repoUrl: repoUrl,
  );
  final plan = planBidsMerge(await readDatasetDirectory(root), incoming);
  if (plan.refused.isNotEmpty) return null;
  await applyMergeToDirectory(root, plan);
  return '$root/${name.relativeDir}/${name.filename}';
}

/// Show exactly what the merge will do and wait for a yes.
///
/// This is a gate, not a courtesy: writing into a dataset the app did not
/// create is the one operation here with no undo.
///
/// [renumbered] lists the files moved to a free run because their name was
/// taken by a different recording.
Future<bool> confirmMerge(
  BuildContext context,
  MergePlan plan,
  String target, {
  List<String> renumbered = const [],
}) async {
  final theme = Theme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add to this dataset?'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(target, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(kBidsAddRule, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              for (final (label, paths) in [
                ('Added', plan.added),
                ('Filed under the next free run', renumbered),
                ('Gaining rows', plan.rowMerged),
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
        title: const Text('Add to a BIDS dataset'),
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
                title: const Text('Session TSV and sidecar'),
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
      dialogTitle: 'Choose the BIDS dataset folder',
    );
  } catch (_) {
    return null;
  }
}

/// A dataset `.zip` picked from storage and read. Null when cancelled or when
/// it cannot be used, with the reason passed to [say].
Future<({String name, List<DatasetFile> files})?> pickDatasetZip(
  void Function(String) say,
) async {
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
      'That dataset is ${(size / (1024 * 1024)).round()} MB. A zip works up '
      'to ${kMaxMergeZipBytes ~/ (1024 * 1024)} MB; use the desktop app.',
    );
    return null;
  }
  try {
    return (
      name: picked.name,
      files: readDatasetZip(await picked.readAsBytes()),
    );
  } catch (e) {
    say('Could not read that dataset: $e');
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
  final byParticipant = recordedFiles([
    for (final f in source.files)
      if (f.content != kUnreadContent) f,
  ]);
  if (byParticipant.isEmpty) {
    say('No session or notes TSVs found there. $kBidsFolderRule');
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
      title: const Text('Load which participants?'),
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
          child: const Text('Load'),
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
Future<String> writeAggregateInto(
  String root, {
  required String tsv,
  required String sidecar,
}) async {
  final dir = '$root/$aggregateDerivativeDir';
  await Directory(dir).create(recursive: true);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  for (final (name, content) in [
    ('$aggregateStem.tsv', tsv),
    ('$aggregateStem.json', sidecar),
  ]) {
    final file = File('$dir/$name');
    if (file.existsSync()) {
      if (await file.readAsString() == content) continue;
      await file.copy('${file.path}.bak-$stamp');
    }
    await writeStringAtomic(file.path, content);
  }
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
  return '$dir/$aggregateStem.tsv';
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
  final path = await writeAggregateInto(root, tsv: tsv, sidecar: sidecar);
  if (!context.mounted) return false;
  final copy = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Saved into the dataset'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Text(
          '$summary, saved with its sidecar as\n$path\n\n'
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
