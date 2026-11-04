/// "Export BIDS dataset": the whole tree, as one zip.
///
/// A new dataset is always a zip: it is the one shape that works identically on
/// all five platforms, and `exportFile` already hands a single file to a
/// desktop Save-As dialog or an iPad share sheet. Writing a directory needs its
/// own permissions and has mobile failure modes, which is why only the merge
/// does it, and only on the desktop. See `bids_merge_ui.dart`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../core/bids.dart';
import '../core/bids_dataset.dart';
import '../core/annotation.dart';
import '../core/bids_merge.dart';
import '../core/bids_sidecar.dart';
import '../core/session/aggregate.dart';
import '../core/session/session_file.dart';
import '../core/session/tsv_kind.dart';
import '../report/upload_actions.dart';
import 'save_target.dart';
import 'share_util.dart';

/// Zip the dataset built from [entries] and deliver it.
///
/// [anchor] is the export button, for the iPad share popover. See
/// [ExportOutcome].
Future<ExportOutcome> exportBidsDataset(
  BuildContext context, {
  required List<DatasetEntry> entries,
  List<DatasetFile> extraFiles = const <DatasetFile>[],
  GlobalKey? anchor,
  AvoidFile? avoid,
}) async {
  if (entries.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Nothing to export yet.')));
    return ExportOutcome.notDelivered;
  }
  // Naming only the first of several subjects would be worse than generic.
  final subjects = {for (final e in entries) BidsName.label(e.name.subject)};
  final stem = subjects.length == 1
      ? 'sub-${subjects.first}_bids'
      : 'bids-dataset';

  return exportFile(
    context,
    filename: '$stem.zip',
    anchor: anchor,
    failureLabel: 'BIDS export failed',
    avoid: avoid,
    build: () async {
      final files = buildBidsDataset(
        entries,
        appName: appName,
        appVersion: appVersion,
        repoUrl: repoUrl,
      );
      final archive = Archive();
      // [extraFiles] carries derivatives, kept out of buildBidsDataset so the
      // raw tree's layout never depends on what a caller is deriving.
      for (final file in [...files, ...extraFiles]) {
        archive.addFile(
          ArchiveFile.bytes(file.path, utf8.encode(file.content)),
        );
      }
      return (
        bytes: Uint8List.fromList(ZipEncoder().encode(archive)),
        warning: null,
      );
    },
  );
}

/// A [DatasetEntry] for one recorded file.
///
/// [kind] is `session_tsv` or `annotation_tsv`. The sidecar comes from the
/// same contract that documents the columns, so the two cannot disagree.
DatasetEntry datasetEntry({
  required BidsName name,
  required String tsv,
  required Map<String, dynamic> contract,
  required String kind,
  required String acqTime,
}) => (
  name: name,
  tsv: tsv,
  sidecar: _encode(
    buildSidecar(contract, kind, appVersion: appVersion, task: name.task),
  ),
  acqTime: acqTime.isEmpty ? 'n/a' : acqTime,
);

String _encode(Map<String, dynamic> sidecar) =>
    '${const JsonEncoder.withIndent('  ').convert(sidecar)}\n';

/// The dataset [uploads] describe: its entries, the whole file list,
/// and the names left out for want of BIDS entities.
///
/// Shared by the zip export and the merge, so the two cannot disagree about
/// what a dataset made from this upload contains.
///
/// With [existing], a file whose name that dataset already uses for a
/// different recording moves to the next free run (see [renumberClashes]).
({
  List<DatasetEntry> entries,
  List<DatasetFile> files,
  List<String> skipped,
  List<String> renumbered,
})
datasetFromUploads(
  List<Uploaded> uploads,
  Map<String, dynamic> contract, {
  List<DatasetFile> existing = const [],
}) {
  final entries = <DatasetEntry>[];
  final recorded = <Uploaded>[];
  final skipped = <String>[];
  for (final file in uploads) {
    final name = BidsName.parse(file.name);
    if (name == null || name.session.isEmpty) {
      skipped.add(file.name);
      continue;
    }
    recorded.add(file);
    final isSession = file.kind == TsvKind.programming;
    entries.add(
      datasetEntry(
        // Re-emitted with the current suffix and column names, so a 0.4.x
        // `_events.tsv` lands in the dataset as a valid `_beh.tsv`.
        name: BidsName(
          subject: name.subject,
          session: name.session,
          task: name.task.isEmpty
              ? (isSession ? 'programming' : 'notes')
              : name.task,
          run: name.run,
        ),
        tsv: isSession
            ? serializeSessionTsv(file.rows)
            : writeAnnotations(file.notes),
        contract: contract,
        kind: isSession ? 'session_tsv' : 'annotation_tsv',
        acqTime: isSession
            ? (file.rows.isEmpty ? '' : file.rows.first.acqTime)
            : (file.notes.isEmpty ? '' : file.notes.first.acqTime),
      ),
    );
  }
  final placed = renumberClashes(existing, entries);
  if (entries.isEmpty) {
    return (
      entries: entries,
      files: const [],
      skipped: skipped,
      renumbered: const [],
    );
  }

  // The combined table goes where BIDS puts a cross-session derivation: its
  // own directory under `derivatives/`, with its own dataset_description.
  // Named as filed, after any renumbering, so run_id and source_file point at
  // the recording that sits at that path.
  final aggregate = buildAggregate([
    for (final (i, source) in aggregateSources(recorded).indexed)
      (filename: placed.entries[i].name.filename, rows: source.rows),
  ]);
  final files = <DatasetFile>[
    ...buildBidsDataset(
      placed.entries,
      appName: appName,
      appVersion: appVersion,
      repoUrl: repoUrl,
    ),
    if (aggregate.rowCount > 0) ...[
      derivativeDescription(
        dir: aggregateDerivativeDir,
        name: '$appName combined sessions',
        appName: appName,
        appVersion: appVersion,
        repoUrl: repoUrl,
      ),
      (
        path: '$aggregateDerivativeDir/$aggregateStem.tsv',
        content: aggregate.tsv,
      ),
      (
        path: '$aggregateDerivativeDir/$aggregateStem.json',
        content: aggregateSidecarJson(contract, appVersion: appVersion),
      ),
    ],
  ];
  return (
    entries: placed.entries,
    files: files,
    skipped: skipped,
    renumbered: placed.renumbered,
  );
}
