/// Lay a set of recorded TSVs out as a BIDS dataset directory.
///
/// A file with BIDS entities in its name is not a BIDS dataset: the spec wants
/// a `sub-<label>/ses-<label>/beh/` tree with a `dataset_description.json`, a
/// `README` and a `participants.tsv` at its root. The app records one file per
/// visit wherever the platform's picker puts it, and this turns a folder of
/// those into something `bids-validator` accepts. Derived documents (the PDF
/// and Word reports) go under `derivatives/`, as BIDS requires.
library;

import 'dart:collection';
import 'dart:convert';

import 'bids.dart';
import 'schema_columns.dart';
import 'tsv.dart';

/// The BIDS version this layout targets.
const String bidsVersion = '1.10.0';

/// One recorded file to place in the dataset.
typedef DatasetEntry = ({
  BidsName name,
  String tsv,
  String sidecar,

  /// The instant of the first recorded row, for `scans.tsv`; empty when the
  /// file has no dated rows.
  String acqTime,

  /// The visit's row of `sessions.tsv`, the run's initial assessment for its
  /// `scans.tsv` row, and the person's row of `participants.tsv`; empty for a
  /// notes file.
  Map<String, String> visit,
  Map<String, String> initial,
  Map<String, String> participant,

  /// Each `scale_<name>` column of [initial], to its scale's name.
  Map<String, String> initialScales,
});

/// One file of the dataset: a path relative to the dataset root, and content.
typedef DatasetFile = ({String path, String content});

/// Build every file of a BIDS dataset for [entries], as paths relative to the
/// dataset root in a stable order, so a caller need not know the layout rules.
List<DatasetFile> buildBidsDataset(
  List<DatasetEntry> entries, {
  required Map<String, dynamic> contract,
  required String appName,
  required String appVersion,
  required String repoUrl,
}) {
  final files = <DatasetFile>[
    (
      path: 'dataset_description.json',
      content: _json(<String, dynamic>{
        'Name': 'DBS programming sessions',
        'BIDSVersion': bidsVersion,
        'DatasetType': 'raw',
        'GeneratedBy': [
          {'Name': appName, 'Version': appVersion, 'CodeURL': repoUrl},
        ],
      }),
    ),
    (path: 'README', content: _readme(appName, appVersion, repoUrl)),
  ];

  final subjects = <String>{
    for (final e in entries) BidsName.label(e.name.subject),
  }.toList()..sort();
  final indication = <String, String>{
    for (final e in entries)
      if ((e.participant['dbs_indication'] ?? '').isNotEmpty)
        BidsName.label(e.name.subject): e.participant['dbs_indication']!,
  };

  files.add((
    path: 'participants.tsv',
    content: writeTsvRecords(participantColumns, [
      for (final s in subjects)
        {'participant_id': 'sub-$s', 'dbs_indication': indication[s] ?? ''},
    ]),
  ));
  files.add((
    path: 'participants.json',
    content: _json(_describe(contract, 'participants_tsv')),
  ));

  final visits = <String, List<DatasetEntry>>{};
  for (final e in entries) {
    if (e.visit.isEmpty) continue;
    (visits[BidsName.label(e.name.subject)] ??= []).add(e);
  }
  for (final subject in visits.keys.toList()..sort()) {
    final rows = <String, Map<String, String>>{};
    for (final e in visits[subject]!) {
      final id = e.visit['session_id'] ?? '';
      final earlier = rows[id]?['acq_time'] ?? '';
      final now = e.visit['acq_time'] ?? '';
      rows[id] = {
        ...e.visit,
        'acq_time': earlier.isNotEmpty && earlier.compareTo(now) < 0
            ? earlier
            : now,
      };
    }
    final ordered = rows.keys.toList()..sort();
    files.add((
      path: 'sub-$subject/sub-${subject}_sessions.tsv',
      content: writeTsvRecords(visitColumns, [
        for (final k in ordered) rows[k]!,
      ]),
    ));
    files.add((
      path: 'sub-$subject/sub-${subject}_sessions.json',
      content: _json(_describe(contract, 'sessions_tsv')),
    ));
  }

  // scans.tsv is per subject+session, so group before emitting.
  final scans = <String, List<DatasetEntry>>{};
  for (final entry in entries) {
    final dir = entry.name.relativeDir;
    files.add((path: '$dir/${entry.name.filename}', content: entry.tsv));
    files.add((
      path: '$dir/${entry.name.sidecarFilename}',
      content: entry.sidecar,
    ));
    final sessionDir = dir.substring(0, dir.lastIndexOf('/'));
    (scans[sessionDir] ??= []).add(entry);
  }

  for (final sessionDir in scans.keys.toList()..sort()) {
    final group = scans[sessionDir]!;
    final first = group.first.name;
    final stem =
        '$sessionDir/sub-${BidsName.label(first.subject)}'
        '_ses-${BidsName.label(first.session)}_scans';
    final scales = <String, String>{for (final e in group) ...e.initialScales};
    files.add((
      path: '$stem.tsv',
      content: writeTsvRecords(
        [
          ...scanColumns.take(scanColumns.length - 1),
          ...scales.keys,
          scanColumns.last,
        ],
        [
          for (final e in group)
            {
              ...e.initial,
              // scans.tsv paths are relative to the subject/session directory.
              'filename': '${BidsName.datatype}/${e.name.filename}',
              'acq_time': e.acqTime,
            },
        ],
      ),
    ));
    files.add((
      path: '$stem.json',
      content: _json(_describe(contract, 'scans_tsv', scales: scales)),
    ));
  }

  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// The `dataset_description.json` a derivative needs of its own: "derivatives
/// datasets MUST include a dataset_description.json file at the root level".
DatasetFile derivativeDescription({
  required String dir,
  required String name,
  required String appName,
  required String appVersion,
  required String repoUrl,
}) => (
  path: '$dir/dataset_description.json',
  content: _json(<String, dynamic>{
    'Name': name,
    'BIDSVersion': bidsVersion,
    'DatasetType': 'derivative',
    'GeneratedBy': [
      {'Name': appName, 'Version': appVersion, 'CodeURL': repoUrl},
    ],
  }),
);

/// Where clinician-readable reports live inside a dataset.
const String reportsDerivativeDir = 'derivatives/dbs-annotator-reports';

/// Where the combined cross-session table lives inside a dataset: the raw tree
/// is one file per (subject, session, task, run), so a table spanning sessions
/// can only be a derivative, with its own [derivativeDescription].
const String aggregateDerivativeDir = 'derivatives/dbs-annotator-aggregate';

/// The combined table's stem inside [aggregateDerivativeDir]: no `sub-`
/// entity, because it spans subjects, and `desc-` is the entity BIDS provides
/// for a derivative variant. The CI validator job checks that this passes.
const String aggregateStem = 'desc-aggregate_beh';

final _recordedPath = RegExp(
  r'^((?:[^/]+/)*)sub-([A-Za-z0-9]+)/(?:ses-[A-Za-z0-9]+/)?beh/[^/]+_(?:beh|events)\.tsv$',
);

/// Folders that hold copies, derived data or archive debris, not recordings.
const _notRawFolders = {'sourcedata', 'code', 'derivatives', '__MACOSX'};

/// The session and notes TSVs in a dataset listing, by participant label and
/// in path order. A dataset folder is read from its root only. With [inZip],
/// any folders may wrap the dataset, as a zip made by archiving the folder
/// does: the root is then the shallowest folder holding a
/// `dataset_description.json`, or any folder when the zip has none. Files under
/// `sourcedata/`, `code/`, `derivatives/`, `__MACOSX/` and dot-folders, dot
/// files and other datatypes are left out.
Map<String, List<DatasetFile>> recordedFiles(
  List<DatasetFile> files, {
  bool inZip = false,
}) {
  bool excluded(String s) => _notRawFolders.contains(s) || s.startsWith('.');
  List<String> folders(String path) =>
      (path.split('/')..removeLast()).where((s) => s.isNotEmpty).toList();

  String unwrapped(String path) => path.replaceFirst(RegExp(r'^(\./)+'), '');

  final zipRoots = <String>{};
  if (inZip) {
    var shallowest = -1;
    for (final f in files) {
      final path = unwrapped(f.path);
      if (path.split('/').last != 'dataset_description.json') continue;
      final dir = folders(path);
      if (dir.any(excluded)) continue;
      if (shallowest < 0 || dir.length < shallowest) {
        shallowest = dir.length;
        zipRoots.clear();
      }
      if (dir.length == shallowest) zipRoots.add(dir.join('/'));
    }
  }

  final out = SplayTreeMap<String, List<DatasetFile>>();
  for (final f in [...files]..sort((a, b) => a.path.compareTo(b.path))) {
    final path = unwrapped(f.path);
    if (path.split('/').last.startsWith('.')) continue;
    final m = _recordedPath.firstMatch(path);
    if (m == null) continue;
    final wrappers = folders(m.group(1)!);
    if (zipRoots.isNotEmpty) {
      if (!zipRoots.contains(wrappers.join('/'))) continue;
    } else if (wrappers.isNotEmpty && !inZip) {
      continue;
    } else if (wrappers.any(excluded)) {
      continue;
    }
    out.putIfAbsent(m.group(2)!, () => []).add(f);
  }
  return out;
}

/// Column descriptions for an index table, from the contract's [kind]
/// section, plus its [scales] columns.
Map<String, dynamic> _describe(
  Map<String, dynamic> contract,
  String kind, {
  Map<String, String> scales = const {},
}) {
  final section = contract[kind] as Map<String, dynamic>;
  String plain(Object? text) => '${text ?? ''}'.replaceAll('``', '');
  return <String, dynamic>{
    for (final c in (section['columns'] as List).cast<Map<String, dynamic>>())
      c['name'] as String: {'Description': plain(c['description'])},
    for (final e in scales.entries)
      e.key: {
        'LongName': e.value,
        'Description': plain(
          (section['scale_columns'] as Map<String, dynamic>?)?['description'],
        ),
      },
  };
}

String _json(Object? value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

String _readme(String appName, String appVersion, String repoUrl) =>
    '''
# DBS programming sessions

Recorded with $appName $appVersion ($repoUrl).

Each file under `sub-*/ses-*/${BidsName.datatype}/` is one deep brain
stimulation programming session: one row per stimulation configuration that
was tried, with one `scale_<name>` column per rated scale. What belongs to the
visit (target, leads, IPG, medications and the initial assessment) is the
visit's row in `sub-*/sub-*_sessions.tsv`; the DBS indication is in
`participants.tsv`. Every `.json` sidecar documents its table's columns,
including each scale's name, the contact grammar used by the anode/cathode
cells and the current-split notation used by the amplitude cells.

`_beh.tsv` rather than `_events.tsv` because these files carry no `onset` or
`duration` column and accompany no recording, which is the case the
specification points at `_beh.tsv` for.

Reports generated from this data are under `$reportsDerivativeDir/`.

## Columns

Programming sessions (`task-programming`): ${sessionColumns.join(', ')}, with
the scale columns before `notes`.

Visits (`sub-*_sessions.tsv`): ${visitColumns.join(', ')}.

Runs (`sub-*_ses-*_scans.tsv`), one row per file with its initial assessment:
${scanColumns.join(', ')}, with the scale columns before `notes`.

Participants: ${participantColumns.join(', ')}.

Notes files from older versions (`task-notes`): ${annotationColumns.join(', ')}.

## Provenance

No demographics, identifiers or free-text beyond the clinical notes typed
during the visit are recorded. Subject labels are whatever the clinician typed;
check them before sharing.
''';
