/// The serialisation boundary every clinical record passes through.
///
/// `lib/core/tsv.dart` had no direct test, and was only exercised transitively.
/// That is how the line-ending detection bug below survived: it is unreachable
/// from any round-trip that writes with this library, because the trigger is a
/// cell containing a `\r\n` that arrived from OUTSIDE the app.
library;

import 'package:dbs_annotator/core/tsv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseTsv line endings', () {
    test('LF-terminated rows parse', () {
      final rows = parseTsv('a\tb\nc\td\n');
      expect(rows, [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('CRLF-terminated rows parse (pre-0.5.0 files)', () {
      final rows = parseTsv('a\tb\r\nc\td\r\n');
      expect(rows, [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    // A `notes` cell can legitimately contain a CRLF, pasted from a Windows
    // app or an EHR web page, and the writer quotes it so it survives a round
    // trip. The row terminator must therefore be read from the first line
    // ending only. Deriving it by scanning the whole document finds the quoted
    // CRLF, takes CRLF as the terminator, and then matches nothing: the quoted
    // pair is not a row break (terminators only match outside quotes) and the
    // real LF terminators no longer match, so the whole document collapses to
    // one row. `parseTsvRecords` skips the header and yields zero records
    // while `sniffTsvKind` still recognises the file from its intact header,
    // so a session opens reporting "0 rows" and the next insert autosaves a
    // one-row file over it.
    test('a quoted CRLF inside a cell does not break row splitting', () {
      const doc =
          'name\tnote\n'
          'first\t"line one\r\nline two"\n'
          'second\tplain\n';
      final rows = parseTsv(doc);
      expect(rows.length, 3, reason: 'header + 2 data rows');
      expect(rows[1][0], 'first');
      expect(
        rows[1][1],
        'line one\r\nline two',
        reason: 'the embedded CRLF is content, and must be preserved verbatim',
      );
      expect(rows[2], ['second', 'plain']);
    });

    test('a quoted bare CR inside a cell is preserved', () {
      final rows = parseTsv('a\tb\n1\t"x\ry"\n');
      expect(rows[1][1], 'x\ry');
    });

    test('a quoted LF inside a cell does not break row splitting', () {
      final rows = parseTsv('a\tb\n1\t"x\ny"\n');
      expect(rows.length, 2);
      expect(rows[1][1], 'x\ny');
    });
  });

  group('parseTsvRecords', () {
    test('a BOM or padding in the header does not hide the first column', () {
      final recs = parseTsvRecords('\uFEFFid\t name \nx\ty\n');
      expect(recs.single, {'id': 'x', 'name': 'y'});
    });

    test('blank and whitespace-only lines are not records', () {
      final recs = parseTsvRecords('a\tb\nx\ty\n \t\n\n');
      expect(recs, [
        {'a': 'x', 'b': 'y'},
      ]);
    });

    test('maps each row onto the header', () {
      final recs = parseTsvRecords('one\ttwo\nx\ty\n');
      expect(recs, [
        {'one': 'x', 'two': 'y'},
      ]);
    });

    test('a row shorter than the header yields empty strings, not a throw', () {
      final recs = parseTsvRecords('one\ttwo\tthree\nx\ty\n');
      expect(recs.single['three'], '');
    });

    // Documents current behaviour rather than endorsing it: cells beyond the
    // header are dropped on read, and `writeTsvRecords` emits only the columns
    // it knows, so a file carrying a column this version does not understand
    // loses it on the next autosave. Recorded in the review backlog.
    test('cells beyond the header are dropped', () {
      final recs = parseTsvRecords('one\ttwo\nx\ty\tz\n');
      expect(recs.single.keys, ['one', 'two']);
      expect(recs.single.containsValue('z'), isFalse);
    });

    test('a header with no data rows yields no records', () {
      expect(parseTsvRecords('one\ttwo\n'), isEmpty);
    });
  });

  group('writeTsv', () {
    test('round-trips a cell containing a tab, a quote and a newline', () {
      final original = [
        ['h1', 'h2'],
        ['plain', 'has\ttab "quote" and\nnewline'],
      ];
      expect(parseTsv(writeTsv(original)), original);
    });

    test('terminates with a newline so two exports can be concatenated', () {
      expect(
        writeTsv([
          ['a'],
        ]),
        endsWith('\n'),
      );
    });

    test('writes LF, not CRLF', () {
      expect(
        writeTsv([
          ['a'],
          ['b'],
        ]),
        isNot(contains('\r')),
      );
    });

    test('an empty row list yields an empty document', () {
      expect(writeTsv([]), '');
      expect(parseTsv(''), isEmpty);
    });
  });
}
