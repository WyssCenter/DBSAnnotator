/// Fold new recordings into a BIDS dataset that already exists.
///
/// [buildBidsDataset] is a CREATE function: it regenerates `participants.tsv`
/// with its own single column and rewrites `dataset_description.json` and the
/// `README` from its own templates. Dropped onto a curated dataset that would
/// silently delete the study's demographic columns, its `Authors` and its
/// `DatasetDOI`, and the result is valid BIDS that passes the validator with no
/// error at all. So a merge classifies every path instead of writing them all,
/// and the classification is the whole feature.
library;

import 'bids.dart';
import 'bids_dataset.dart';
import 'tsv.dart';

/// What a merge will do, computed before anything is written.
typedef MergePlan = ({
  /// The files to write, path and final content.
  List<DatasetFile> write,

  /// Paths that did not exist in the target.
  List<String> added,

  /// Index files gaining rows, with the rows they gain.
  List<String> rowMerged,

  /// Paths the target already has that the merge leaves exactly as they are.
  List<String> keptAsIs,

  /// Incoming files refused because the target already holds that path, which
  /// would mean overwriting recorded clinical data.
  List<String> refused,
});

/// Dataset-level files the app generates but must never overwrite: they carry
/// what the lab wrote, not what this app knows.
const Set<String> kCuratedPaths = {
  'dataset_description.json',
  'README',
  'participants.json',
};

bool _isScans(String path) => path.endsWith('_scans.tsv');

/// What a chosen folder or zip holds, before anything is added to it.
enum DatasetFolderKind { dataset, empty, other }

/// A BIDS dataset has `dataset_description.json` at its top level. Hidden
/// files such as `.DS_Store` do not make a folder non-empty.
DatasetFolderKind datasetFolderKind(List<DatasetFile> files) {
  final visible = [
    for (final f in files)
      if (!f.path.split('/').any((part) => part.startsWith('.'))) f,
  ];
  if (visible.isEmpty) return DatasetFolderKind.empty;
  return visible.any((f) => f.path == 'dataset_description.json')
      ? DatasetFolderKind.dataset
      : DatasetFolderKind.other;
}

/// Plan the merge of [incoming] into the dataset described by [existing].
///
/// Both are whole-dataset file lists, so the caller can read the target from a
/// directory or from a zip and this stays the same function.
MergePlan planBidsMerge(
  List<DatasetFile> existing,
  List<DatasetFile> incoming,
) {
  final have = {for (final f in existing) f.path: f.content};
  final write = <DatasetFile>[];
  final added = <String>[];
  final rowMerged = <String>[];
  final keptAsIs = <String>[];
  final refused = <String>[];

  for (final file in incoming) {
    final path = file.path;
    final current = have[path];

    // Curated: the lab's, so written only when the dataset has none.
    if (kCuratedPaths.contains(path)) {
      if (current == null) {
        write.add(file);
        added.add(path);
      } else {
        keptAsIs.add(path);
      }
      continue;
    }

    // Index files: unioned, never replaced, so columns this app knows nothing
    // about survive.
    if (path == 'participants.tsv' || _isScans(path)) {
      if (current == null) {
        write.add(file);
        added.add(path);
        continue;
      }
      final key = path == 'participants.tsv' ? 'participant_id' : 'filename';
      final merged = _mergeRows(current, file.content, key);
      if (merged == null) {
        keptAsIs.add(path);
      } else {
        write.add((path: path, content: merged));
        rowMerged.add(path);
      }
      continue;
    }

    // Everything else is recorded data. An existing path means this visit is
    // already filed, and overwriting it would replace archived clinical data
    // with whatever was just uploaded.
    if (current == null) {
      write.add(file);
      added.add(path);
    } else if (current == file.content) {
      keptAsIs.add(path);
    } else {
      refused.add(path);
    }
  }

  // Anything the incoming set does not mention is untouched by construction:
  // other datatypes, derivatives, and whatever else the lab keeps here.
  return (
    write: write,
    added: added,
    rowMerged: rowMerged,
    keptAsIs: keptAsIs,
    refused: refused,
  );
}

/// Union two TSV tables on [key], keeping every column either side declares and
/// every row the target already had. Returns null when nothing would change.
///
/// The target's column order leads, so a lab's `participant_id, age, sex` stays
/// in that order and gains nothing but rows. A new row supplies only the
/// columns it knows; the rest are written as the missing-value code by
/// [writeTsvRecords].
String? _mergeRows(String existing, String incoming, String key) {
  final have = parseTsvRecords(existing);
  final want = parseTsvRecords(incoming);
  if (want.isEmpty) return null;

  final columns = <String>[
    ...(_headerOf(existing) ?? const []),
    for (final c in _headerOf(incoming) ?? const [])
      if (!(_headerOf(existing) ?? const []).contains(c)) c,
  ];
  if (columns.isEmpty) return null;

  final seen = {for (final r in have) r[key] ?? ''};
  final extra = [
    for (final r in want)
      if (!seen.contains(r[key] ?? '')) r,
  ];
  if (extra.isEmpty) return null;
  return writeTsvRecords(columns, [...have, ...extra]);
}

/// The column names of a TSV, or null when it has no header row.
List<String>? _headerOf(String tsv) {
  final rows = parseTsv(tsv);
  if (rows.isEmpty || rows.first.isEmpty) return null;
  return [for (final c in rows.first) c.trim()];
}

String _pathOf(BidsName n) => '${n.relativeDir}/${n.filename}';

/// [name], or the first later run whose path is not in [taken].
BidsName nextFreeRun(BidsName name, Set<String> taken) {
  var n = name;
  while (taken.contains(_pathOf(n))) {
    n = BidsName(
      subject: n.subject,
      session: n.session,
      task: n.task,
      run: BidsName.index('${int.parse(BidsName.index(n.run)) + 1}'),
      acquisition: n.acquisition,
      suffix: n.suffix,
      extension: n.extension,
    );
  }
  return n;
}

/// [entries], with any whose path a different recording in [existing] (or an
/// earlier entry) already uses moved to the next free run, so a second
/// recording is filed beside the first instead of being refused or written
/// over it. An entry identical to the file at its path keeps that path: adding
/// it again adds nothing. `renumbered` says which moved where.
({List<DatasetEntry> entries, List<String> renumbered}) renumberClashes(
  List<DatasetFile> existing,
  List<DatasetEntry> entries,
) {
  final content = {for (final f in existing) f.path: f.content};
  final taken = {...content.keys};
  final out = <DatasetEntry>[];
  final renumbered = <String>[];
  for (final e in entries) {
    var name = e.name;
    if (content[_pathOf(name)] != e.tsv) {
      name = nextFreeRun(name, taken);
      if (name.run != BidsName.index(e.name.run)) {
        renumbered.add('${e.name.filename} as run-${name.run}');
      }
    }
    taken.add(_pathOf(name));
    out.add((name: name, tsv: e.tsv, sidecar: e.sidecar, acqTime: e.acqTime));
  }
  return (entries: out, renumbered: renumbered);
}

/// [plan]'s unwritten paths as the user is shown them. A derivative already in
/// the dataset is never written into, so its folder is listed once as left
/// unchanged: "refused" reads as an error for a file nobody recorded.
({List<String> unchanged, List<String> refused}) shownUnwritten(
  MergePlan plan,
) {
  String? folder(String path) {
    final parts = path.split('/');
    return parts.length > 2 && parts.first == 'derivatives'
        ? '${parts[0]}/${parts[1]}/'
        : null;
  }

  final unchanged = <String>[];
  final refused = <String>[];
  for (final (path, wasRefused) in [
    for (final p in plan.keptAsIs) (p, false),
    for (final p in plan.refused) (p, true),
  ]) {
    final dir = folder(path);
    if (dir != null) {
      if (!unchanged.contains(dir)) unchanged.add(dir);
    } else {
      (wasRefused ? refused : unchanged).add(path);
    }
  }
  return (unchanged: unchanged, refused: refused);
}

/// One line describing [plan], for the confirmation shown before it runs.
String describeMergePlan(MergePlan plan) {
  final shown = shownUnwritten(plan);
  final parts = <String>[
    '${plan.added.length} file${plan.added.length == 1 ? '' : 's'} added',
    if (plan.rowMerged.isNotEmpty)
      '${plan.rowMerged.length} index file'
          '${plan.rowMerged.length == 1 ? '' : 's'} gaining rows',
    if (shown.unchanged.isNotEmpty) '${shown.unchanged.length} left as is',
    if (shown.refused.isNotEmpty) '${shown.refused.length} refused',
  ];
  return parts.join(' - ');
}
