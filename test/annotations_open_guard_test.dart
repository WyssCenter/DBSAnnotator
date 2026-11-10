/// The guard that stops the Annotations workflow destroying a programming
/// session TSV.
///
/// A programming TSV parses as notes without error, so `_open` in
/// `annotations_screen` must sniff the kind: it autosaves back to the file it
/// opened, and the first typed note would rewrite that file with only the five
/// annotation columns. Pure logic rather than a widget test; it pins the two
/// facts that make the guard necessary.
library;

import 'dart:io';

import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:dbs_annotator/core/session/tsv_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final programming = File(
    'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv',
  ).readAsStringSync();

  test('the sniffer is what distinguishes the two kinds', () {
    // The guard added to annotations_screen._open compares against this.
    expect(sniffTsvKind(programming), TsvKind.programming);
    expect(
      sniffTsvKind(writeAnnotations(parseAnnotations(programming))),
      TsvKind.notes,
    );
  });

  test('a programming TSV parses as notes WITHOUT error - the trap', () {
    // Why a guard is needed rather than a parse failure: `parseAnnotations`
    // is total, and every annotation column exists in a programming file.
    expect(
      annotationColumns.every(workingColumns.contains),
      isTrue,
      reason:
          'annotationColumns must be a subset of workingColumns for the '
          'silent-success trap to exist; if this ever stops being true, the '
          'guard is still correct but this test needs rewriting',
    );
    final asNotes = parseAnnotations(programming);
    expect(
      asNotes,
      isNotEmpty,
      reason:
          'it does not throw and does not come back empty - it comes back '
          'looking plausible, which is exactly why nothing caught it',
    );
  });

  test('round-tripping a programming file through the notes writer would '
      'destroy it', () {
    // What autosave does on the first typed note if the guard is removed.
    final rewritten = writeAnnotations(parseAnnotations(programming));
    final lostColumns = workingColumns.where(
      (c) => !annotationColumns.contains(c),
    );

    expect(lostColumns, isNotEmpty);
    for (final column in ['block_id', 'scale_name', 'scale_value']) {
      expect(
        workingColumns.contains(column),
        isTrue,
        reason: 'guarding against a schema rename silently weakening this test',
      );
      expect(
        rewritten.split('\n').first.split('\t'),
        isNot(contains(column)),
        reason:
            '$column survives in the notes-only rewrite, so this test is '
            'no longer demonstrating the data loss it claims to',
      );
    }
  });
}
