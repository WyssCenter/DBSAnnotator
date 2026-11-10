/// What can be produced from a set of uploaded TSVs, and why not when not.
///
/// The reports screen offers every action at once and greys out the ones the
/// upload cannot support, so this decides both the enabled set and the sentence
/// shown in place of a disabled action. Pure, because that table is the
/// feature and it is what the tests pin.
library;

import '../core/annotation.dart';
import '../core/bids.dart';
import '../core/session/aggregate.dart' show AggregateSource;
import '../core/session/longitudinal.dart' show patientIdsMatch;
import '../core/session/bids_session.dart';
import '../core/session/session_row.dart';
import '../core/session/tsv_kind.dart';

/// One uploaded file, classified by its header rather than its name.
typedef Uploaded = ({
  String name,
  TsvKind kind,
  List<SessionRow> rows,
  List<Annotation> notes,
});

/// [content] as an upload, classified by its header, or the reason it is not
/// one.
({Uploaded? file, String? rejected}) classifyUpload(
  String name,
  String content,
) {
  final kind = sniffTsvKind(content);
  return switch (kind) {
    TsvKind.programming => (
      file: (
        name: name,
        kind: kind,
        rows: parseAnySessionTsv(content),
        notes: const <Annotation>[],
      ),
      rejected: null,
    ),
    TsvKind.notes => (
      file: (
        name: name,
        kind: kind,
        rows: const <SessionRow>[],
        notes: parseAnnotations(content),
      ),
      rejected: null,
    ),
    TsvKind.unknown || TsvKind.unreadable => (
      file: null,
      rejected: tsvKindMismatch(name, kind, TsvKind.programming),
    ),
  };
}

/// The earliest instant recorded in [file], or null when none parses.
DateTime? earliestRecorded(Uploaded file) {
  DateTime? first;
  for (final at in [
    for (final r in file.rows) r.timestamp,
    for (final n in file.notes) DateTime.tryParse(n.acqTime),
  ]) {
    if (at != null && (first == null || at.isBefore(first))) first = at;
  }
  return first;
}

/// [files] ordered by patient, then from the earliest visit to the most
/// recent, so every preview, report and combined table reads the same way
/// whatever order the files were picked in. A file with no readable time goes
/// last within its patient.
List<Uploaded> chronological(Iterable<Uploaded> files) {
  String patient(Uploaded f) =>
      BidsName.label(BidsName.parse(f.name)?.subject ?? '');
  final keyed = [
    for (final (i, f) in files.indexed) (i: i, f: f, at: earliestRecorded(f)),
  ];
  keyed.sort((a, b) {
    final byPatient = patient(a.f).compareTo(patient(b.f));
    if (byPatient != 0) return byPatient;
    if (a.at != null && b.at != null && a.at != b.at) {
      return a.at!.compareTo(b.at!);
    }
    if ((a.at == null) != (b.at == null)) return a.at == null ? 1 : -1;
    return a.i.compareTo(b.i);
  });
  return [for (final k in keyed) k.f];
}

enum ReportAction {
  sessionReport(
    'Single session report',
    'One visit, as PDF or Word.',
    how:
        'The imported session is rendered as a report, with the sections you '
        'choose. Add to a BIDS folder saves the session, the report, or both, '
        'into a BIDS folder you already have.',
    needs: 'Exactly one imported session.',
    creates:
        'One PDF or Word file named after the session. Added to a BIDS folder, '
        'the session goes under sub-<participant>/ses-<session>/beh/ and the '
        'report under derivatives/dbs-annotator-reports/.',
  ),
  longitudinalReport(
    'Report across visits',
    'Change across visits.',
    how:
        'Every imported file is brought into one report, one visit per session '
        'in date order. A note from an older notes file goes to the visit of '
        'its day; a day with notes and no session gets its own Visits row and '
        'table.',
    needs:
        'Two or more files of one patient. A notes file from an earlier '
        'version counts as one of them.',
    creates:
        'One PDF or Word file, '
        'sub-<participant>_desc-longitudinal<yyyymmdd>_report, dated the day '
        'it was made.',
  ),
  aggregateTsv(
    'Combined table (TSV)',
    'Every visit in one analysis table.',
    how:
        'One row per configuration of every imported session, and one per '
        'visit for its initial assessment, with the participant, session and '
        'run added as columns and one column per scale. A note from an older '
        'notes file becomes a row of its own, with its time and text.',
    needs:
        'Two or more files, of any patients, whose names carry sub- and ses- '
        'entities.',
    creates:
        'A zip holding the table and the JSON sidecar describing its columns. '
        'Imported from a BIDS folder, both can be saved back into it.',
  ),
  bidsDataset(
    'BIDS folder (zip)',
    'The files laid out as a BIDS folder.',
    how:
        'Each session is placed at its BIDS path, with a sidecar, and the '
        'folder index files are written around them.',
    needs: 'At least one file whose name carries a sub- entity.',
    creates:
        'A zip of a BIDS folder: dataset_description.json, README, '
        'participants.tsv, a sessions.tsv per patient, and '
        'sub-<participant>/ses-<session>/beh/ per visit.',
  ),
  addToDataset(
    'Add to a BIDS folder',
    'Save these into a BIDS folder you already have.',
    how:
        'The files are planned into the BIDS folder and the plan is shown for '
        'you to confirm before anything is written. Nothing already there is '
        'overwritten; a taken name moves to the next free run.',
    needs:
        'A BIDS folder, or its zip on a tablet, and files whose names carry a '
        'sub- entity.',
    creates:
        'The new visits in that BIDS folder, with their sidecars and rows in '
        'participants.tsv, sessions.tsv and the scans files. Export gives a '
        'merged copy as a zip and leaves the original untouched.',
  );

  const ReportAction(
    this.label,
    this.description, {
    required this.how,
    required this.needs,
    required this.creates,
  });

  final String label;
  final String description;

  /// The info dialog: how the export works, the input, and the output.
  final String how;
  final String needs;
  final String creates;

  /// What the button says. The merge does not export anything: it writes into
  /// a dataset the user already has, and a button that says otherwise invites
  /// the tap it should not get.
  String get verb => this == ReportAction.addToDataset ? 'Add' : 'Export';
}

List<Uploaded> _programming(List<Uploaded> files) =>
    files.where((f) => f.kind == TsvKind.programming).toList();

List<Uploaded> _notes(List<Uploaded> files) =>
    files.where((f) => f.kind == TsvKind.notes).toList();

/// Files whose name carries the `sub-` entity a dataset path is built from.
List<Uploaded> withBidsEntities(List<Uploaded> files) =>
    files.where((f) => BidsName.parse(f.name) != null).toList();

/// Why [action] cannot run on [files], or null when it can.
///
/// [canWriteFolder] is false on iPadOS and Android, where a picked directory is
/// a security-scoped path or a `content://` URI that `dart:io` cannot write.
/// It changes how a dataset is merged, not whether it can be: those platforms
/// take the existing dataset as a zip and give a new one back.
String? unavailableReason(
  ReportAction action,
  List<Uploaded> files, {
  bool canWriteFolder = true,
}) {
  if (files.isEmpty) return 'Import a session first.';

  switch (action) {
    case ReportAction.sessionReport:
      if (files.length > 1) {
        return 'Import one session; several give a report across visits.';
      }
      if (files.single.kind != TsvKind.programming) {
        return 'A notes file from an earlier version has no report of its own.';
      }
      return null;

    case ReportAction.longitudinalReport:
      if (files.length < 2) return 'Needs two or more files.';
      if (!patientIdsMatch(files.map((f) => f.name).toList())) {
        return 'These files name different patients.';
      }
      return null;

    case ReportAction.aggregateTsv:
      if (files.length < 2) return 'Needs two or more files.';
      return null;

    case ReportAction.bidsDataset:
    case ReportAction.addToDataset:
      if (withBidsEntities(files).isEmpty) {
        return 'No imported file name carries a sub- entity.';
      }
      return null;
  }
}

/// The actions [files] can produce, in menu order.
Set<ReportAction> availableActions(
  List<Uploaded> files, {
  bool canWriteFolder = true,
}) => {
  for (final a in ReportAction.values)
    if (unavailableReason(a, files, canWriteFolder: canWriteFolder) == null) a,
};

/// [files] as the combined table's sources. A notes file contributes one row
/// per note, carrying only its time and text, so every other column is n/a.
List<AggregateSource> aggregateSources(List<Uploaded> files) => [
  for (final f in files)
    (
      filename: f.name,
      rows: f.kind == TsvKind.programming
          ? f.rows
          : [
              for (final (i, n) in f.notes.indexed)
                SessionRow(blockId: '$i', acqTime: n.acqTime, notes: n.notes),
            ],
    ),
];

/// One line describing what was uploaded, for the header.
String uploadSummary(List<Uploaded> files) {
  if (files.isEmpty) return 'No files imported.';
  final sessions = _programming(files).length;
  final notes = _notes(files).length;
  final parts = <String>[
    if (sessions > 0) '$sessions session${sessions == 1 ? '' : 's'}',
    if (notes > 0) '$notes notes file${notes == 1 ? '' : 's'}',
  ];
  return parts.join(' and ');
}
