/// Reading a programming session and its patient's history out of a BIDS
/// folder on disk.
library;

import 'dart:convert';
import 'dart:io';

import '../bids.dart';
import '../bids_sidecar.dart';
import '../schema_columns.dart';
import '../tsv.dart';
import 'bids_session.dart';
import 'session_row.dart';

/// The BIDS folder holding [path]: its nearest parent folder with a
/// `dataset_description.json`, or null.
String? bidsRootOf(String path) {
  var dir = File(path).parent;
  while (true) {
    if (File('${dir.path}/dataset_description.json').existsSync()) {
      return dir.path;
    }
    final up = dir.parent;
    if (up.path == dir.path) return null;
    dir = up;
  }
}

Future<List<Map<String, String>>> _records(String path) async {
  final file = File(path);
  if (!file.existsSync()) return [];
  try {
    return parseTsvRecords(await file.readAsString());
  } catch (_) {
    return [];
  }
}

Future<Map<String, String>> _scaleNames(String jsonPath) async {
  final file = File(jsonPath);
  if (!file.existsSync()) return const {};
  try {
    return scaleNamesIn(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
    );
  } catch (_) {
    return const {};
  }
}

String _sessionsTsv(String root, String subject) =>
    '$root/sub-$subject/sub-${subject}_sessions';

/// The patient labels in the folder's `participants.tsv`, without `sub-`.
Future<List<String>> participantsIn(String root) async => [
  for (final r in await _records('$root/participants.tsv'))
    if ((r['participant_id'] ?? '').isNotEmpty)
      BidsName.label(r['participant_id']!),
]..sort();

/// What the folder knows about [subject] before a new visit: the DBS
/// indication and the most recent visit's row, empty when there is none.
Future<({String indication, Map<String, String> lastVisit})> patientHistory(
  String root,
  String subject,
) async {
  final label = BidsName.label(subject);
  final person = (await _records(
    '$root/participants.tsv',
  )).where((r) => BidsName.label(r['participant_id'] ?? '') == label);
  final visits = await _records('${_sessionsTsv(root, label)}.tsv');
  visits.sort((a, b) => (a['acq_time'] ?? '').compareTo(b['acq_time'] ?? ''));
  return (
    indication: person.isEmpty
        ? ''
        : readColumn(person.first, 'dbs_indication'),
    lastVisit: visits.isEmpty ? const <String, String>{} : visits.last,
  );
}

/// The row [root] holds for the visit [name] belongs to, or an empty map.
Future<Map<String, String>> visitRow(String root, BidsName name) async {
  final label = BidsName.label(name.subject);
  final id = 'ses-${BidsName.label(name.session)}';
  return (await _records(
    '${_sessionsTsv(root, label)}.tsv',
  )).firstWhere((r) => r['session_id'] == id, orElse: () => const {});
}

/// Parse a session file's [content] into long-form rows, whichever form it
/// is in. A `beh/` file of the BIDS tables at [path] is joined with its
/// visit and participant rows from its BIDS folder, when it is in one.
Future<List<SessionRow>> readSessionFile(String content, {String? path}) async {
  final rows = parseTsv(content);
  if (path == null ||
      rows.isEmpty ||
      !isBehHeader(rows.first.map((c) => c.trim()))) {
    return parseAnySessionTsv(content);
  }
  final name = BidsName.parse(path.split(RegExp(r'[\\/]')).last);
  final root = bidsRootOf(path);
  if (root == null || name == null) return parseAnySessionTsv(content);
  final behRows = parseTsvRecords(content);
  final label = BidsName.label(name.subject);
  final person = (await _records('$root/participants.tsv')).firstWhere(
    (r) => BidsName.label(r['participant_id'] ?? '') == label,
    orElse: () => const {},
  );
  return joinSession(
    behRows: behRows,
    visit: await visitRow(root, name),
    participant: person,
    scaleNames: {
      ...await _scaleNames('${_sessionsTsv(root, label)}.json'),
      ...await _scaleNames(path.replaceFirst(RegExp(r'\.tsv$'), '.json')),
    },
  );
}
