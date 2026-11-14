/// Report content pinned in `report_data`, which both builders render from.
library;

import 'dart:io';

import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_ranking_prefs.dart';

List<SessionRow> _example() => parseSessionTsv(
  File('test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv')
      .readAsStringSync(),
);

void main() {
  group('over the committed example', () {
    late SessionReportData data;
    setUp(() => data = rankedReportData(_example()));

    test('the table carries a time and an index per block', () {
      final time = sessionTableHeaders.indexOf('Time');
      final index = sessionTableHeaders.indexOf('Index');
      expect(time, greaterThanOrEqualTo(0));
      expect(index, greaterThanOrEqualTo(0));

      // tableData is two rows per block, L then R; the block-level cells sit on
      // the L row.
      final first = data.tableData.first;
      expect(first[time], matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
      expect(first[index], contains('0.50'));
      expect(
        first[index],
        contains('rank 5'),
        reason: 'blocks 3 and 4 tie, so block 1 is 5th of six distinct values',
      );
      // Equal printed indices must carry equal ranks: the document elsewhere
      // says those two blocks are indistinguishable.
      final byBlock = <String, String>{
        for (final row in data.tableData)
          if (row[index].isNotEmpty) row.first: row[index],
      };
      expect(byBlock['3'], contains('0.55'));
      expect(byBlock['3'], byBlock['4']);
      // The R row leaves them blank rather than repeating them.
      expect(data.tableData[1][time], isEmpty);
      expect(data.tableData[1][index], isEmpty);
    });

    test('one weight per column, summing to 100', () {
      expect(sessionTableColumnWeights, hasLength(sessionTableHeaders.length));
      expect(sessionTableColumnWeights.fold<double>(0, (a, b) => a + b), 100);
    });

    test('with no targets there is no blank Index column', () {
      final plain = buildSessionReportData(rows: _example());
      expect(plain.tableHeaders, isNot(contains('Index')));
      expect(plain.tableWeights, hasLength(plain.tableHeaders.length));
      expect(plain.tableWeights.fold<double>(0, (a, b) => a + b), 100);
      expect(
        plain.tableRows.every((r) => r.length == plain.tableHeaders.length),
        isTrue,
      );
      expect(data.tableHeaders, contains(kSessionIndexHeader));
    });

    test('response reports first -> last per scale', () {
      final byName = {for (final r in data.response) r.name: r};
      expect(
        byName.keys,
        containsAll(['Obsessions', 'Compulsions', 'Anxiety', 'Mood']),
      );
      expect(byName['Obsessions']!.first, 6);
      expect(byName['Obsessions']!.last, 2);
    });

    test('n scales rated per block, so the index is interpretable', () {
      // Every block in the example rates all five.
      expect(data.scalesRated.values.toSet(), {4});
    });

    test('the Time cell carries the gap from the previous block', () {
      final time = sessionTableHeaders.indexOf('Time');
      // Block 1 is the first, so no gap; the settings that follow are one to
      // three minutes apart, which is what taking five ratings costs. The gap
      // column makes the nine seconds between blocks 6 and 7 (identical
      // stimulation, ranked 1 and 2) visible without arithmetic.
      expect(data.tableData[0][time], '09:03:20');
      final second = data.tableData[2][time];
      expect(second, startsWith('09:05:05'));
      expect(second, contains('(+2 min)'));
      expect(
        data.tableData[data.tableData.length - 2][time],
        contains('(+9 s)'),
      );
    });

    test(
      'parameters list their distinct values and the blocks that used them',
      () {
        // A "5.0 - 7.5 mA" range hides that the right side went 5.0 -> 6.0 ->
        // 7.0 -> 6.0 -> 7.5 -> 6.0, implying a titration that never happened.
        expect(
          data.ampL,
          '5.0 mA (configurations 1-5), 6.0 mA (configurations 6-7)',
        );
        expect(data.ampR, contains('6.0 mA (configurations 2, 4, 6-7)'));
      },
    );

    test('an unchanged parameter says so instead of a degenerate range', () {
      expect(data.freqL, '130 Hz (unchanged)');
      expect(data.pwR, '90 µs (unchanged)');
    });

    test('the figure carries frequency and pulse width per side', () {
      // The live view in the app shows them; the report did not.
      expect(data.chart.frequency.keys, containsAll(['Left', 'Right']));
      expect(data.chart.pulseWidth['Left']!.values.toSet(), {90});
      expect(data.figureCaption, contains('pulse width'));
    });

    test('the figure caption is short and names the green', () {
      expect(data.figureCaption, contains('green bands'));
      expect(data.figureCaption, isNot(contains('blocks x')));
    });

    test('with no targets the caption says why there is no green', () {
      final bare = buildSessionReportData(rows: _example());
      expect(bare.figureCaption, contains('No scale targets were set'));
      expect(bare.figureCaption, isNot(contains('green bands')));
    });

    test('the index method is stated, not just the modes', () {
      expect(data.indexMethod, contains('unweighted mean'));
    });
  });

  group('contact rendering', () {
    test('a split is shown as percentages that sum to 100', () {
      // Three equal contacts rounded independently print 33/33/33 = 99 %, which
      // reads as a missing share.
      expect(
        contactsWithCurrent('E2a_E2b_E2c', '1.67_1.67_1.67'),
        '2a(34%) 2b(33%) 2c(33%)',
      );
      expect(contactsWithCurrent('E2b_E2c', '3.3_2.2'), '2b(60%) 2c(40%)');
    });

    test('a single contact gets no parenthetical', () {
      expect(contactsWithCurrent('E2c', '4.5'), '2c');
      expect(contactsWithCurrent('case', ''), 'case');
    });

    test('the E prefix and the underscore never reach the page', () {
      final out = contactsWithCurrent('E2b_E2c', '3.3_2.2');
      expect(out, isNot(contains('E')));
      expect(out, isNot(contains('_')));
    });

    test('a count mismatch prints the contacts alone rather than guessing', () {
      expect(contactsWithCurrent('E2b_E2c', '5.5'), '2b 2c');
    });
  });

  group('no targets means no ranking', () {
    test('nothing is invented for an externally-authored TSV', () {
      // Fabricating `min` over 0..10 yields an index, two green bands and a
      // "Scale targets" line asserting an intent nobody expressed: here, that
      // falling Mood and Energy were improvements.
      final bare = buildSessionReportData(rows: _example());
      expect(bare.hasTargets, isFalse);
      expect(bare.chart.aggregateIndex, isEmpty);
      expect(bare.chart.bestX, isNull);
      expect(bare.bestBlocks, isEmpty);
      expect(bare.secondBlocks, isEmpty);
      expect(bare.targetsText, kNoTargetsText);
    });

    test('an all-ignore pref set counts as no targets', () {
      final ignored = buildSessionReportData(
        rows: _example(),
        scalePrefs: const [
          (
            name: 'Obsessions',
            min: 0,
            max: 10,
            mode: ScaleMode.ignore,
            custom: null,
          ),
        ],
      );
      expect(ignored.hasTargets, isFalse);
      expect(ignored.chart.bestX, isNull);
    });
  });

  group('provenance and honesty', () {
    test('the session stamp carries the UTC offset', () {
      // The `timezone` column holds a platform zone name plus an offset
      // ("CEST +02:00"); only the offset half is portable, and a clinical
      // timestamp with no zone is ambiguous across DST. The synthetic example
      // is generated in UTC, so its offset is +00:00, which still exercises
      // the extraction: the parser must find and render an offset rather than
      // assume one.
      final data = rankedReportData(_example());
      expect(data.utcOffset, '+00:00');
      expect(data.sessionStamp, contains('(UTC+00:00)'));
      // Still ASCII, so the PDF's Latin-1 fallback can draw it.
      expect(data.sessionStamp.runes.every((r) => r < 0x80), isTrue);
    });

    test('rows with no timezone yield no offset rather than a wrong one', () {
      final data = buildSessionReportData(
        rows: const [
          SessionRow(
            blockId: '1',
            isInitial: '0',
            acqTime: '2026-01-01T09:00:00',
          ),
        ],
      );
      expect(data.utcOffset, isEmpty);
      expect(data.sessionStamp, isNot(contains('UTC')));
    });

    test('the source file and row count are carried through', () {
      final rows = _example();
      final data = buildSessionReportData(rows: rows, sourceFile: 'a_file.tsv');
      expect(data.sourceFile, 'a_file.tsv');
      expect(data.rowCount, rows.length);
    });

    test('targets print the bounds the index normalised into', () {
      // Without them a reader cannot reproduce a score, and the ranking turns
      // on the third decimal.
      expect(
        rankedReportData(_example()).targetsText,
        contains('Obsessions: min of 0-10'),
      );
    });
  });

  test('the disclaimer names what the ranking ignores', () {
    expect(kRankingDisclaimer, contains('side effects'));
    expect(kRankingDisclaimer, contains('tolerability'));
    expect(kRankingDisclaimer, contains('Notes'));
  });
}
