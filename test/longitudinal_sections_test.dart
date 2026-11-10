/// The longitudinal chooser and the targets it depends on.
///
/// Both were missing: the report always contained everything, and targets had
/// no effect at all. A chooser whose checkboxes change nothing is the defect
/// this pins, so each section is switched off in turn and the document is
/// asserted to lose it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dbs_annotator/app_info.dart' show kNotice;

import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/longitudinal_data.dart';
import 'package:dbs_annotator/report/longitudinal_pdf.dart';
import 'package:dbs_annotator/report/longitudinal_sections.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixture =
    'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv';

Map<String, List<SessionRow>> _twoVisits() {
  final source = File(_fixture).readAsStringSync();
  return {
    'sub-01_ses-20260203_task-programming_run-01_beh.tsv': parseSessionTsv(
      source,
    ),
    'sub-01_ses-20260918_task-programming_run-02_beh.tsv': parseSessionTsv(
      source.replaceAll('2026-02-03', '2026-09-18'),
    ),
  };
}

/// The document part's text, tags stripped. A .docx is a zip, so the bytes
/// have to be decoded before anything can be read out of them.
String _docxText(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final part = archive.files.firstWhere((f) => f.name == 'word/document.xml');
  return utf8.decode(part.content).replaceAll(RegExp('<[^>]*>'), ' ');
}

void main() {
  test('the desktop defaults leave the heavy sections off', () {
    expect(kDefaultLongitudinalSections, {
      LongitudinalSection.clinicalChart,
      LongitudinalSection.visits,
      LongitudinalSection.sessionChart,
      LongitudinalSection.sources,
    });
    // Four leads a visit turns a short report into a long one, so it is opt in.
    expect(
      kDefaultLongitudinalSections,
      isNot(contains(LongitudinalSection.electrodes)),
    );
  });

  test('every section has a label and a description for the chooser', () {
    for (final s in LongitudinalSection.values) {
      expect(s.label, isNotEmpty, reason: s.name);
      expect(s.description, isNotEmpty, reason: s.name);
    }
  });

  group('section gating', () {
    late LongitudinalReportData data;

    setUp(() => data = buildLongitudinalReportData(files: _twoVisits()));

    test('the three Qt sections appear when asked for', () {
      final all = _docxText(
        buildLongitudinalDocx(data: data, sections: kAllLongitudinalSections),
      );
      expect(all, contains('Session data'));
      expect(all, contains('Programming summary'));
      expect(all, contains('Source files'));
      expect(all, contains(kNotice));
    });

    test('each section disappears when unchecked', () {
      // Matched on something only that section emits: "Visits" alone also
      // appears in the page-one header ("Visits: 2"), so it would pass with
      // the section switched off.
      for (final (section, heading) in const [
        (LongitudinalSection.visits, 'Programme at visit end'),
        (LongitudinalSection.sessionTable, 'Session data'),
        (LongitudinalSection.summary, 'Programming summary'),
        (LongitudinalSection.sources, 'Source files'),
      ]) {
        final without = _docxText(
          buildLongitudinalDocx(
            data: data,
            sections: kAllLongitudinalSections.difference({section}),
          ),
        );
        expect(without, isNot(contains(heading)), reason: section.name);
      }
    });

    test('the programming summary reports each visit', () {
      final text = _docxText(
        buildLongitudinalDocx(
          data: data,
          sections: const {LongitudinalSection.summary},
        ),
      );
      // Both visits, each with its own configuration count.
      expect(text, contains('2026-02-03'));
      expect(text, contains('2026-09-18'));
      expect(text, contains('Configurations tested'));
    });
  });

  group('scale targets', () {
    test('without targets no block is banded', () {
      final data = buildLongitudinalReportData(files: _twoVisits());
      expect(data.sessionChart.bestXs, isEmpty);
      expect(data.sessionChart.secondXs, isEmpty);
    });

    test('with targets the best block of EACH visit is banded', () {
      final files = _twoVisits();
      final prefs = defaultScalePrefsFor([
        for (final rows in files.values) ...rows,
      ]);
      expect(prefs, isNotEmpty, reason: 'the fixture rates session scales');

      final data = buildLongitudinalReportData(files: files, scalePrefs: prefs);
      // Within-session ranking, so one band per visit, not one per report.
      expect(data.sessionChart.bestXs, isNotEmpty);
      expect(data.visits, hasLength(2));
      for (final visit in data.visits) {
        expect(
          visit.session.bestBlocks,
          isNotEmpty,
          reason: '${visit.date} should rank its own blocks',
        );
      }
    });

    test('targets fix the y axis instead of fitting it to the data', () {
      final files = _twoVisits();
      final fitted = buildLongitudinalReportData(files: files).sessionChart;
      final declared = buildLongitudinalReportData(
        files: files,
        scalePrefs: defaultScalePrefsFor([
          for (final rows in files.values) ...rows,
        ]),
      ).sessionChart;

      // The fixture rates 0-10 scales but never uses the whole range, so a
      // fitted axis is narrower than the declared one. Same scale, same axis,
      // at every visit: a drop between visits is a drop, not a rescale.
      expect(declared.yMin, lessThanOrEqualTo(fitted.yMin));
      expect(declared.yMax, greaterThanOrEqualTo(fitted.yMax));
      expect(declared.yMin, 0);
      expect(declared.yMax, 10);
    });

    test('the clinical figure is never banded', () {
      // One assessment per visit, so there is nothing to rank within one, and
      // ranking across them would compare numbers never on the same scale.
      final data = buildLongitudinalReportData(
        files: _twoVisits(),
        scalePrefs: defaultScalePrefsFor([
          for (final rows in _twoVisits().values) ...rows,
        ]),
      );
      expect(data.clinicalChart.bestXs, isEmpty);
      expect(data.clinicalChart.secondXs, isEmpty);
      expect(data.clinicalChart.aggregateIndex, isEmpty);
    });
  });
}
