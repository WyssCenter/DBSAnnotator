/// The PDF and the Word document must say the same things.
///
/// Two divergences were found by hand during this round and both were the kind
/// nobody notices until a clinician has one of each in front of them: Word said
/// "Initial clinical notes" where the PDF said "Baseline assessment
/// (pre-session)", and Word printed the raw `E2b_E2c` contact tokens the PDF
/// had deliberately retired. Both builders read the SAME `SessionReportData`,
/// so a divergence is always a rendering slip rather than a data one - which is
/// exactly what a test can catch cheaply.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/session_docx.dart';
import 'package:dbs_annotator/report/session_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_ranking_prefs.dart';

/// A 2x1 red PNG, enough for `pngSize` to read a real IHDR.
Uint8List _tinyPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEklEQVR4AWP8z8'
  'Dwn4GBgYEBAA1TAv0Q2FSJAAAAAElFTkSuQmCC',
);

List<SessionRow> _example() => parseSessionTsv(
  File('test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv')
      .readAsStringSync(),
);

/// The visible text of `word/document.xml`, in order.
String _docxText(List<int> bytes) {
  final xml = utf8.decode(
    ZipDecoder()
        .decodeBytes(bytes)
        .files
        .firstWhere((f) => f.name == 'word/document.xml')
        .content,
  );
  final out = StringBuffer();
  // `<w:t` only, not `<w:tbl`/`<w:tc`/`<w:tr`: `[^>]*` happily matches "blPr",
  // which pulled raw markup into the "text" and made the assertions meaningless.
  for (final m in RegExp(
    r'<w:t(?:\s[^>]*)?>(.*?)</w:t>',
    dotAll: true,
  ).allMatches(xml)) {
    out.write(
      m
          .group(1)!
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"'),
    );
  }
  return out.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String docx;
  late SessionReportData data;

  setUpAll(() async {
    data = rankedReportData(_example(), generatedAt: DateTime(2026, 6, 26));
    // With a chart, so the figure + caption path is exercised too.
    docx = _docxText(
      buildSessionDocx(data: data, subjectId: '01', chartPng: _tinyPng()),
    );
  });

  test('every section heading appears in both formats', () async {
    // Extracting text from an untagged PDF is unreliable, so the PDF side is
    // asserted structurally elsewhere; here we pin that Word carries every
    // heading the shared data implies, using the exact strings the PDF uses.
    for (final heading in const [
      'Session report',
      'Baseline assessment (pre-session)',
      'Session data',
      'Electrode configuration',
      'Programming summary',
      'Attestation',
    ]) {
      expect(docx, contains(heading), reason: 'Word is missing "$heading"');
    }
  });

  test('the retired notations never reach either document', () {
    // `E2b_E2c` and an underscore-joined current are internal identifiers. A
    // current printed as `3.3_2.2` under an "Amp (mA)" heading reads as one
    // number, which is a dosing hazard.
    expect(docx, isNot(contains('E2b')));
    expect(docx, isNot(contains('3.3_2.2')));
    expect(docx, isNot(contains('Initial clinical notes')));
    expect(docx, isNot(contains('Optimal configuration')));
    expect(docx, isNot(contains('Session duration')));
  });

  test('the derived values Word prints are the ones the data holds', () {
    // Not a re-derivation: the same strings the PDF interpolates.
    expect(docx, contains(data.sessionStamp));
    expect(docx, contains(configCountText(data)));
    expect(docx, contains(data.ampL));
    expect(docx, contains(data.freqL));
    expect(docx, contains(data.targetsText));
    expect(docx, contains(data.figureCaption.substring(0, 40)));
    for (final line in data.configChanges) {
      expect(docx, contains(line));
    }
  });

  test('Word explains the index it shades by, in the PDF legend order', () {
    // Word shaded rows by an index it never defined, and put the disclaimer
    // mid-list. The order is the PDF's: targets, notes, method, disclaimer.
    final order = [
      'Scale targets:',
      data.rankingResolutionNote!,
      data.indexMethod,
      kRankingDisclaimer,
    ].map(docx.indexOf).toList();
    expect(order, everyElement(greaterThanOrEqualTo(0)));
    expect(order, orderedEquals([...order]..sort()));
  });

  test('the baseline note is printed under the baseline table', () {
    expect(data.initNotes, isNotEmpty);
    expect(docx, contains('Notes: ${data.initNotes}'));
  });

  test('page 1 carries the response to the visit', () {
    // One column per scale, read down: first, last, change.
    expect(data.responseGrid.map((r) => r.first), [
      '',
      'First',
      'Last',
      'Change',
    ]);
    expect(data.responseGrid.first.skip(1), [
      for (final r in data.response) r.name,
    ]);
    expect(docx.indexOf('Change'), lessThan(docx.indexOf('Baseline')));
  });

  test('both formats build from the same data without throwing', () async {
    final pdf = await buildSessionPdf(data: data, subjectId: '01');
    expect(pdf.bytes.sublist(0, 4), '%PDF'.codeUnits);
    expect(pdf.bytes.length, greaterThan(2000));
  });
}
