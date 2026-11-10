/// What kind of TSV a file actually is, from its HEADER rather than the
/// renameable `task-` entity: `SessionRow.fromMap` is total, so an annotations
/// file handed to it silently yields one all-empty row per line.
library;

import '../tsv.dart';
import 'bids_session.dart';

enum TsvKind {
  programming,
  notes,

  /// A TSV whose header matches neither contract.
  unknown,

  /// Not parseable as a TSV at all: binary, empty, or no header.
  unreadable,
}

/// Columns only a programming TSV has: every session report groups on the
/// block index and `is_initial`. Either spelling of the block index counts.
const _blockMarkers = {'block_id', 'block_ID'};
const _programmingMarkers = {'is_initial'};

/// A notes file is `notes` plus a timestamp, which tells it apart from any
/// other one-column text file; legacy files spell it `date` + `time`.
const _notesRequired = {'notes'};
const _notesTimestampAlternatives = [
  {'acq_time'},
  {'date', 'time'},
];

/// Classify [content] by its header row. A programming TSV also contains every
/// annotation column, so it is checked first.
TsvKind sniffTsvKind(String content) {
  final List<List<String>> rows;
  try {
    rows = parseTsv(content);
  } catch (_) {
    return TsvKind.unreadable;
  }
  // The header alone is the evidence; a header-only file is a new session.
  if (rows.isEmpty || rows.first.isEmpty) return TsvKind.unreadable;
  final header = rows.first.map((c) => c.trim()).toSet();

  if (isBehHeader(header) ||
      _programmingMarkers.every(header.contains) &&
          _blockMarkers.any(header.contains)) {
    return TsvKind.programming;
  }
  if (_notesRequired.every(header.contains) &&
      _notesTimestampAlternatives.any((set) => set.every(header.contains))) {
    return TsvKind.notes;
  }
  return TsvKind.unknown;
}

/// A message naming what was found and what was expected, for a clinician.
String tsvKindMismatch(String filename, TsvKind found, TsvKind wanted) {
  String describe(TsvKind k) => switch (k) {
    TsvKind.programming => 'a programming session',
    TsvKind.notes => 'an annotations (notes) file',
    TsvKind.unknown => 'an unrecognised TSV',
    TsvKind.unreadable => 'not a readable TSV',
  };
  return '$filename is ${describe(found)}; this view needs '
      '${describe(wanted)}.';
}
