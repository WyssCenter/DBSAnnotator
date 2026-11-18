/// The visits of the patient browser: read from the BIDS folder, and listed by
/// patient and session for one run, or all of them, to be chosen.
library;

import 'package:flutter/material.dart';

import '../core/bids.dart';
import '../core/bids_dataset.dart';
import '../core/bids_merge.dart' show kUnreadContent;
import '../core/session/bids_folder.dart';
import '../core/session/tsv_kind.dart';
import '../core/timestamps.dart';
import '../report/upload_actions.dart';
import 'bids_merge_ui.dart';
import 'session/entries_table.dart' show testedCount;

/// The patient choice that lists every patient; no BIDS label holds a `*`.
const kAllPatients = '*';

/// The runs [patient] has in the BIDS folder at [root], each joined with the
/// rows its folder holds for it, and the files left out with the reason.
Future<({List<Uploaded> visits, List<String> rejected})> folderVisits(
  String root,
  String patient,
) async {
  final listing =
      debugDataset ??
      await readDatasetDirectory(
        root,
        only: (p) =>
            p.startsWith(patient == kAllPatients ? 'sub-' : 'sub-$patient/') &&
            p.endsWith('.tsv'),
      );
  final visits = <Uploaded>[];
  final rejected = <String>[];
  for (final MapEntry(key: subject, value: files) in recordedFiles(
    listing,
  ).entries) {
    if (patient != kAllPatients && subject != patient) continue;
    for (final f in files) {
      final name = f.path.split('/').last;
      if (f.content == kUnreadContent) {
        rejected.add('$name could not be read');
        continue;
      }
      final c = classifyUpload(name, f.content);
      if (c.rejected case final why?) rejected.add(why);
      final file = c.file;
      if (file == null) continue;
      visits.add(
        file.kind == TsvKind.programming
            ? (
                name: name,
                kind: file.kind,
                rows: await readSessionFile(f.content, path: '$root/${f.path}'),
                notes: file.notes,
              )
            : file,
      );
    }
  }
  return (visits: chronological(visits), rejected: rejected);
}

/// The patient and session [f] belongs to.
String visitLabel(Uploaded f) {
  final name = BidsName.parse(f.name);
  if (name == null) return f.name;
  return [
    'sub-${name.subject}',
    if (name.session.isNotEmpty) 'ses-${name.session}',
  ].join(', ');
}

/// The run [f] is, and the date and time it starts.
String runLabel(Uploaded f) {
  final name = BidsName.parse(f.name);
  final at = [
    for (final r in f.rows) r.acqTime,
    for (final n in f.notes) n.acqTime,
  ].firstWhere((t) => recordedDate(t).isNotEmpty, orElse: () => '');
  return [
    if (name == null)
      f.name
    else
      '${f.kind == TsvKind.notes ? 'Notes, run' : 'Run'} ${name.run}',
    if (at.isNotEmpty)
      '${recordedDate(at)} ${recordedTime(at).substring(0, 5)}',
  ].join(', ');
}

class VisitList extends StatelessWidget {
  const VisitList({
    super.key,
    required this.visits,
    required this.selected,
    required this.onSelect,
  });

  final List<Uploaded> visits;

  /// The chosen run's file name, or null for every visit.
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byVisit = <String, List<Uploaded>>{};
    for (final f in visits) {
      byVisit.putIfAbsent(visitLabel(f), () => []).add(f);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (visits.length > 1)
          ListTile(
            dense: true,
            selected: selected == null,
            leading: const Icon(Icons.timeline, size: 20),
            title: const Text('All visits'),
            subtitle: Text(uploadSummary(visits)),
            onTap: () => onSelect(null),
          ),
        for (final MapEntry(key: visit, value: runs) in byVisit.entries) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
            child: Text(visit, style: theme.textTheme.titleSmall),
          ),
          for (final f in runs)
            ListTile(
              dense: true,
              selected: selected == f.name,
              leading: Icon(
                f.kind == TsvKind.programming
                    ? Icons.table_chart_outlined
                    : Icons.sticky_note_2_outlined,
                size: 20,
              ),
              title: Text(runLabel(f)),
              subtitle: Text(
                f.kind == TsvKind.programming
                    ? '${testedCount(f.rows)} configurations'
                    : '${f.notes.length} notes',
              ),
              onTap: () => onSelect(f.name),
            ),
        ],
      ],
    );
  }
}
