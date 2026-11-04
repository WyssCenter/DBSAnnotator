import 'dart:io';

import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/core/timestamps.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/report_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the report prints must be what the file recorded: the same clock, and
/// every value against its own label. Both are properties a reader cannot
/// check for themselves, so nothing else in the suite would catch them going
/// wrong.
void main() {
  List<SessionRow> fixtureRows() => parseSessionTsv(
    File('test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv')
        .readAsStringSync(),
  );

  group('line breaks survive the report font', () {
    // A real TTF cmap has no entry for a line break, so a coverage set built
    // from one excludes it. This is the shipping configuration: the IBM Plex
    // faces are bundled.
    final ttfLike = <int>{for (var r = 0x20; r < 0x7f; r++) r, ...'µ°'.runes};

    test('a multi-line cell keeps its breaks and reports no loss', () {
      final t = ReportTextSanitiser(coverage: ttfLike);
      const cell = 'Obsessions: 8.00\nCompulsions: 7.50\nAnxiety: 5.00';

      expect(t(cell), cell);
      expect(
        t.lostCharacters,
        isFalse,
        reason: 'a line break is structure, not an unrenderable character',
      );
    });

    test('no report cell is handed to the font carrying a question mark', () {
      // The failure this guards: every value displaced onto the line of the
      // NEXT scale's name, so 8.00 reads as the Compulsions score.
      final t = ReportTextSanitiser(coverage: ttfLike);
      final data = buildSessionReportData(rows: fixtureRows());

      for (final row in data.tableData) {
        for (final cell in row) {
          expect(t(cell), isNot(contains('?')), reason: 'cell: $cell');
        }
      }
      expect(t.lostCharacters, isFalse);
    });

    test('a genuinely undrawable character is still reported', () {
      final t = ReportTextSanitiser(coverage: ttfLike);
      expect(t('中文'), '??');
      expect(t.lostCharacters, isTrue);
    });
  });

  group('the header prints the recorded clock', () {
    test('identical times in different offsets print identically', () {
      // The offsets are what the two sessions differ by, so rendering the
      // instant in the exporting machine's zone puts these five hours apart.
      // Asserting they agree holds in every timezone, including the UTC
      // machine where the defect is invisible.
      SessionReportData at(String offset) => buildSessionReportData(
        rows: [
          SessionRow(acqTime: '2026-02-03T09:00:00$offset', blockId: '1'),
          SessionRow(acqTime: '2026-02-03T09:14:00$offset', blockId: '2'),
        ],
      );

      for (final offset in ['+00:00', '+05:00', '-07:00']) {
        final data = at(offset);
        expect(data.sessionDate, '2026-02-03', reason: offset);
        expect(data.startTime, '09:00', reason: offset);
        expect(data.endTime, '09:14', reason: offset);
      }
    });

    test('the header agrees with the table it heads', () {
      final data = buildSessionReportData(rows: fixtureRows());
      final rows = fixtureRows()
        ..sort((a, b) => a.acqTime.compareTo(b.acqTime));

      expect(data.sessionDate, recordedDate(rows.first.acqTime));
      expect(recordedTime(rows.first.acqTime), startsWith(data.startTime));
      expect(recordedTime(rows.last.acqTime), startsWith(data.endTime));
      // The offset label describes the printed time, so it comes from the
      // file, and the printed time has to come from there too.
      expect(data.sessionStamp, contains(data.startTime));
      expect(
        data.sessionStamp,
        contains(offsetFromTimezoneCell(rows.first.acqTime)),
      );
    });
  });
}
