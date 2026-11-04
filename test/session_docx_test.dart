import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dbs_annotator/core/brand_palette.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/docx_ooxml.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/report_sections.dart';
import 'package:dbs_annotator/report/session_docx.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_ranking_prefs.dart';

/// A 2x1 red PNG, so `pngSize` can read a real IHDR.
Uint8List _tinyPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEklEQVR4AWP8z8'
  'Dwn4GBgYEBAA1TAv0Q2FSJAAAAAElFTkSuQmCC',
);

/// Read a part's UTF-8 text from the docx (zip) bytes.
String _part(List<int> bytes, String name) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.files.firstWhere((f) => f.name == name);
  return utf8.decode(file.content);
}

void main() {
  const rows = [
    SessionRow(
      acqTime: '2026-07-29T09:00:00',
      blockId: '0',
      appendId: '1',
      isInitial: '1',
      scaleName: 'UPDRS-III',
      scaleValue: '32',
      leftElectrodeModel: 'SenSight B33005',
      rightElectrodeModel: 'SenSight B33005',
      leftAnode: 'C',
      leftCathode: '1',
      rightAnode: 'C',
      rightCathode: '9',
      notes: 'Baseline assessment before titration',
    ),
    SessionRow(
      acqTime: '2026-07-29T09:30:00',
      blockId: '1',
      appendId: '1',
      isInitial: '0',
      scaleName: 'Tremor',
      scaleValue: '2',
      leftElectrodeModel: 'SenSight B33005',
      rightElectrodeModel: 'SenSight B33005',
      programId: 'A',
      leftStimFreq: '130',
      leftAnode: 'C',
      leftCathode: '1_2',
      leftAmplitude: '1.5_1',
      leftPulseWidth: '60 µs',
      rightStimFreq: '130',
      rightAnode: 'C',
      rightCathode: '9',
      rightAmplitude: '2',
      rightPulseWidth: '60',
      notes: 'Paresthesia & resolved <30 s', // exercises XML escaping
    ),
    // A second recording block, so the table has a block BOUNDARY (separator
    // rule) and two distinct scores to rank (best vs second-best shading).
    SessionRow(
      acqTime: '2026-07-29T10:15:00',
      blockId: '2',
      appendId: '1',
      isInitial: '0',
      scaleName: 'Tremor',
      scaleValue: '5',
      leftElectrodeModel: 'SenSight B33005',
      rightElectrodeModel: 'SenSight B33005',
      programId: 'B',
      leftStimFreq: '180',
      leftAnode: 'C',
      leftCathode: '2',
      leftAmplitude: '3',
      leftPulseWidth: '90',
      rightStimFreq: '180',
      rightAnode: 'C',
      rightCathode: '10',
      rightAmplitude: '3',
      rightPulseWidth: '90',
    ),
  ];

  test('buildSessionDocx returns a valid PK zip with the OOXML parts', () {
    final bytes = buildSessionDocx(
      data: buildSessionReportData(
        rows: rows,
        generatedAt: DateTime(2026, 7, 29),
      ),
      subjectId: '01',
    );
    expect(bytes, isNotEmpty);
    // ZIP local-file-header magic: "PK\x03\x04".
    expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);

    final names = ZipDecoder().decodeBytes(bytes).files.map((f) => f.name);
    expect(
      names,
      containsAll(<String>[
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
      ]),
    );
  });

  test('document.xml carries the report sections and escapes XML', () {
    final bytes = buildSessionDocx(
      data: buildSessionReportData(
        rows: rows,
        generatedAt: DateTime(2026, 7, 29),
      ),
      subjectId: '01',
    );
    final doc = _part(bytes, 'word/document.xml');

    // Section headings + data made it into the document.
    expect(doc, contains('Session report'));
    expect(doc, contains('Baseline assessment (pre-session)'));
    expect(doc, contains('UPDRS-III'));
    expect(doc, contains('Session data'));
    expect(doc, contains('Programming summary'));
    // Split amplitude 1.5_1 sums to 2.5 mA in the summary.
    expect(doc, contains('2.5'));
    // The note's & and < are escaped, not raw.
    expect(doc, contains('Paresthesia &amp; resolved &lt;30 s'));
    expect(doc, isNot(contains('Paresthesia & resolved')));
  });

  test('empty rows still yield a valid docx', () {
    final bytes = buildSessionDocx(
      data: buildSessionReportData(
        rows: const [],
        generatedAt: DateTime(2026, 7, 29),
      ),
      subjectId: 'unknown',
    );
    expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
    final doc = _part(bytes, 'word/document.xml');
    expect(doc, contains('No recording blocks in this session.'));
  });

  group('embedded graphics (OOXML drawing parts)', () {
    final tinyPng = _tinyPng();

    Uint8List build() => buildSessionDocx(
      data: rankedReportData(rows, generatedAt: DateTime(2026, 7, 29)),
      subjectId: '01',
      chartPng: tinyPng,
      electrodeImages: (
        initLeft: tinyPng,
        initRight: tinyPng,
        finalLeft: tinyPng,
        finalRight: tinyPng,
      ),
    );

    test('adds media parts, a rels part and a png content type', () {
      final bytes = build();
      final names = ZipDecoder()
          .decodeBytes(bytes)
          .files
          .map((f) => f.name)
          .toList();
      expect(names, contains('word/_rels/document.xml.rels'));
      // Chart + 4 leads = 5 images.
      final media = names.where((n) => n.startsWith('word/media/')).toList();
      expect(media, hasLength(5));
      expect(
        _part(bytes, '[Content_Types].xml'),
        contains('Extension="png" ContentType="image/png"'),
      );
    });

    test('every drawing relationship resolves to a media part that exists', () {
      final bytes = build();
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      final rels = _part(bytes, 'word/_rels/document.xml.rels');
      final doc = _part(bytes, 'word/document.xml');

      final relIds = RegExp(
        r'Id="(rId\d+)"\s+Type="[^"]*/image"\s+Target="([^"]+)"',
      ).allMatches(rels);
      expect(relIds, isNotEmpty);
      for (final m in relIds) {
        // Target must exist in the package...
        expect(
          names,
          contains('word/${m.group(2)}'),
          reason: 'dangling relationship target',
        );
        // ...and be referenced by a blip in the body.
        expect(
          doc,
          contains('r:embed="${m.group(1)}"'),
          reason: 'unused image relationship',
        );
      }
      // Conversely, every blip must have a relationship.
      for (final m in RegExp(r'r:embed="(rId\d+)"').allMatches(doc)) {
        expect(
          rels,
          contains('Id="${m.group(1)}"'),
          reason: 'blip references a missing relationship',
        );
      }
    });

    test('declares the drawing namespaces and non-zero extents', () {
      final doc = _part(build(), 'word/document.xml');
      for (final ns in ['xmlns:r=', 'xmlns:wp=', 'xmlns:a=', 'xmlns:pic=']) {
        expect(doc, contains(ns));
      }
      expect(doc, contains('<w:drawing>'));
      // wp:extent and a:ext must agree and be non-zero, or Word offers to
      // repair the file.
      final extents = RegExp(r'<wp:extent cx="(\d+)" cy="(\d+)"/>')
          .allMatches(doc)
          .toList();
      expect(extents, hasLength(5));
      for (final m in extents) {
        expect(int.parse(m.group(1)!), greaterThan(0));
        expect(int.parse(m.group(2)!), greaterThan(0));
        expect(doc, contains('<a:ext cx="${m.group(1)}" cy="${m.group(2)}"/>'));
      }
    });

    test('shades the best and second-best blocks, and rules block starts', () {
      final doc = _part(build(), 'word/document.xml');
      // Tremor is minimised by default, so block 1 (value 2) beats block 2 (5).
      // The hexes are spelled out because this is the only automated guard on
      // what colour reaches a filed clinical document.
      expect(
        doc,
        contains('w:fill="${docxHex(rankRowTint(kBestFill))}"'),
        reason: 'best-block tint',
      );
      expect(doc, contains('w:color="0DE69F"'), reason: 'best-block edge');
      expect(
        doc,
        contains('w:fill="${docxHex(rankRowTint(kSecondFill))}"'),
        reason: 'second-best tint',
      );
      expect(doc, contains('w:sz="24"'), reason: '3pt block separator rule');
      expect(doc, contains('Highest aggregate index in this session (rank 1)'));
      expect(doc, contains('Second highest in this session (rank 2)'));
      expect(
        doc,
        isNot(contains('Optimal')),
        reason: 'a clinical superlative for a rank statistic',
      );
      expect(doc, contains('Scale targets: Tremor: min'));
      expect(doc, contains('does not constitute'), reason: 'disclaimer');
    });

    test('carries docProps and an attestation block', () {
      final bytes = build();
      final names = ZipDecoder()
          .decodeBytes(bytes)
          .files
          .map((f) => f.name)
          .toList();
      // Without docProps the title, author and dates are blank in Word's info
      // pane and in anything that indexes the file.
      expect(names, contains('docProps/core.xml'));
      expect(_part(bytes, '_rels/.rels'), contains('docProps/core.xml'));
      expect(
        _part(bytes, '[Content_Types].xml'),
        contains('core-properties+xml'),
      );
      final core = _part(bytes, 'docProps/core.xml');
      expect(core, contains('DBS session report - sub-01'));
      expect(core, contains('Wyss DBS Annotator v'));

      // Nothing in the document was signed; a machine-produced clinical record
      // that nobody stands behind is what a documentation committee objects to.
      final doc = _part(bytes, 'word/document.xml');
      expect(doc, contains('Attestation'));
      expect(doc, contains('Recorded by'));
      expect(doc, contains('Rated by'));
      expect(doc, isNot(contains('Reviewed by')));
    });

    test('emits a page size and margins', () {
      final a4 = _part(build(), 'word/document.xml');
      expect(a4, contains('<w:pgSz w:w="11906" w:h="16838"/>'));
      expect(a4, contains('w:left="720"'));
      final letter = _part(
        buildSessionDocx(
          data: buildSessionReportData(rows: rows),
          subjectId: '01',
          pageSize: DocxPageSize.letter,
        ),
        'word/document.xml',
      );
      expect(letter, contains('<w:pgSz w:w="12240" w:h="15840"/>'));
    });

    test('without images there is no media and no drawing', () {
      final bytes = buildSessionDocx(
        data: buildSessionReportData(rows: rows),
        subjectId: '01',
      );
      final names = ZipDecoder()
          .decodeBytes(bytes)
          .files
          .map((f) => f.name)
          .toList();
      expect(names.where((n) => n.startsWith('word/media/')), isEmpty);
      expect(_part(bytes, 'word/document.xml'), isNot(contains('<w:drawing>')));
      // The rels part IS still present: the footer registers a relationship
      // whether or not anything was embedded.
      expect(names, contains('word/_rels/document.xml.rels'));
      expect(
        _part(bytes, 'word/_rels/document.xml.rels'),
        isNot(contains('/relationships/image')),
      );
    });

    test('every page is attributable: a real footer part, referenced', () {
      // A continuation page that escapes the staple must still name the
      // patient, the encounter and the tool. The .docx had no footer at all.
      final bytes = buildSessionDocx(
        data: buildSessionReportData(
          rows: rows,
          generatedAt: DateTime(2026, 6, 26),
        ),
        subjectId: '01',
      );
      final names = ZipDecoder()
          .decodeBytes(bytes)
          .files
          .map((f) => f.name)
          .toList();
      expect(names, contains('word/footer1.xml'));

      final footer = _part(bytes, 'word/footer1.xml');
      expect(footer, contains('sub-01'));
      expect(footer, contains('Wyss DBS Annotator v'));
      // Field codes, not baked-in numbers, so they survive a reflow.
      expect(footer, contains('PAGE'));
      expect(footer, contains('NUMPAGES'));

      // Declared in [Content_Types], related from the document, and referenced
      // by the section: miss any one and Word shows a repair prompt or an
      // inert footer.
      expect(
        _part(bytes, '[Content_Types].xml'),
        contains('wordprocessingml.footer+xml'),
      );
      final rels = _part(bytes, 'word/_rels/document.xml.rels');
      final match = RegExp(r'Id="(rId\d+)"[^>]*/relationships/footer"')
          .firstMatch(rels);
      expect(match, isNotNull, reason: 'the footer needs a relationship');
      expect(
        _part(bytes, 'word/document.xml'),
        contains(
          '<w:footerReference w:type="default" '
          'r:id="${match!.group(1)}"/>',
        ),
      );
    });
  });

  test('pngSize reads the IHDR, and rejects non-PNG bytes', () {
    final tiny = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEklEQVR4AWP8z8'
      'Dwn4GBgYEBAA1TAv0Q2FSJAAAAAElFTkSuQmCC',
    );
    expect(pngSize(tiny), (2, 1));
    expect(pngSize(Uint8List.fromList([1, 2, 3])), isNull);
    expect(pngSize(Uint8List.fromList(List.filled(40, 0))), isNull);
  });

  test(
    'drops XML-illegal control characters instead of corrupting the file',
    () {
      // U+000B and U+0000 have no legal XML 1.0 representation, and emitting
      // one makes Word reject the whole document as unreadable. They arrive
      // easily from pasted PDF or hospital-system text. Tab, newline and CR are
      // legal and must survive. Built with fromCharCode so no raw control byte
      // lives in this source file.
      final vt = String.fromCharCode(0x0B);
      final nul = String.fromCharCode(0x00);
      final tab = String.fromCharCode(0x09);
      final rows = [
        SessionRow(
          blockId: '1',
          isInitial: '0',
          notes: 'before${vt}after${nul}end${tab}kept',
        ),
      ];
      final bytes = buildSessionDocx(
        data: buildSessionReportData(
          rows: rows,
          generatedAt: DateTime(2026, 7, 29),
        ),
        subjectId: '01',
      );
      final doc = _part(bytes, 'word/document.xml');

      // The illegal codepoints are gone; surrounding text and the tab remain.
      expect(doc.contains(vt), isFalse, reason: 'U+000B leaked into XML');
      expect(doc.contains(nul), isFalse, reason: 'U+0000 leaked into XML');
      expect(doc, contains('beforeafterend${tab}kept'));

      // And the part is still well-formed enough to re-read.
      expect(doc, startsWith('<?xml version="1.0"'));
    },
  );

  group('sections gate the document', () {
    final data = buildSessionReportData(
      rows: rows,
      generatedAt: DateTime(2026, 7, 29),
    );
    // Two named headings per section, so a section's absence is greppable.
    const headings = {
      ReportSection.baseline: 'Baseline assessment (pre-session)',
      ReportSection.chart: 'Session data',
      ReportSection.electrodes: 'Electrode configuration',
      ReportSection.summary: 'Programming summary',
    };

    String docFor(Set<ReportSection> sections) => _part(
      buildSessionDocx(data: data, subjectId: '01', sections: sections),
      'word/document.xml',
    );

    test('everything on by default', () {
      final doc = docFor(kAllReportSections);
      for (final h in headings.values) {
        expect(doc, contains(h));
      }
    });

    test('dropping one section drops exactly its heading', () {
      for (final entry in headings.entries) {
        // 'Session data' covers chart AND table, so drop both for that one.
        final off = entry.key == ReportSection.chart
            ? {ReportSection.chart, ReportSection.table}
            : {entry.key};
        final doc = docFor(kAllReportSections.difference(off));
        expect(
          doc,
          isNot(contains(entry.value)),
          reason: '${entry.key.name} was excluded but its heading remains',
        );
        for (final other in headings.entries) {
          if (other.key == entry.key) continue;
          expect(
            doc,
            contains(other.value),
            reason:
                'excluding ${entry.key.name} also removed '
                '${other.key.name}',
          );
        }
      }
    });

    test('the patient header survives every selection', () {
      // A report with no attribution is worse than a report with no sections.
      final doc = docFor({ReportSection.summary});
      expect(doc, contains('Patient: sub-01'));
      expect(doc, contains('Wyss DBS Annotator - Session report'));
    });

    test('the table can be dropped while keeping the figure heading', () {
      final doc = docFor(kAllReportSections.difference({ReportSection.table}));
      expect(doc, contains('Session data'), reason: 'the chart is still on');
      // The table's own header row is what should be gone.
      expect(doc, isNot(contains('Freq (Hz)')));
    });
  });

  group('tables are fixed-layout and fill the page', () {
    // With no width hints Word auto-fits from content, and since most of these
    // cells hold 1-4 characters the ten columns collapsed to a fraction of the
    // page while the PDF's filled it.
    List<List<int>> gridsIn(String doc) =>
        RegExp(r'<w:tblGrid>(.*?)</w:tblGrid>')
            .allMatches(doc)
            .map(
              (m) =>
                  RegExp(r'w:w="(\d+)"')
                      .allMatches(m.group(1)!)
                      .map((g) => int.parse(g.group(1)!))
                      .toList(),
            )
            .toList();

    for (final size in DocxPageSize.values) {
      test('${size.name}: every grid sums to the content width', () {
        final data = buildSessionReportData(
          rows: rows,
          generatedAt: DateTime(2026, 7, 29),
        );
        final doc = _part(
          buildSessionDocx(
            data: data,
            subjectId: '01',
            chartPng: _tinyPng(),
            electrodeImages: (
              initLeft: _tinyPng(),
              initRight: _tinyPng(),
              finalLeft: _tinyPng(),
              finalRight: _tinyPng(),
            ),
            pageSize: size,
          ),
          'word/document.xml',
        );

        // The invariant Word cares about: each table's grid sums to that
        // table's own declared `tblW`, or Word rescales the whole table. Not
        // to the page width, and not to a fixed table count.
        final declared = RegExp(r'<w:tblW w:w="(\d+)" w:type="dxa"/>')
            .allMatches(doc)
            .map((m) => int.parse(m.group(1)!))
            .toList();
        final grids = gridsIn(doc);
        expect(grids, isNotEmpty);
        expect(declared, hasLength(grids.length));
        for (var i = 0; i < grids.length; i++) {
          expect(
            grids[i].fold(0, (a, b) => a + b),
            declared[i],
            reason: 'grid $i must sum to its own declared width',
          );
        }

        // The session data table, found by its column count rather than its
        // position, is full width and has one grid column per header.
        final dataIdx = grids.indexWhere(
          (g) => g.length == data.tableHeaders.length,
        );
        expect(
          dataIdx,
          greaterThanOrEqualTo(0),
          reason: 'the session data table must be present',
        );
        expect(declared[dataIdx], size.contentWidthTwips);

        // The electrode grid: two pairs of equal lead columns with a wider
        // gap column between Initial and Final.
        final leadIdx = grids.indexWhere(
          (g) =>
              g.length == 5 && {g[0], g[1], g[3], g[4]}.length == 1 && g[2] > 0,
        );
        expect(leadIdx, greaterThanOrEqualTo(0));
        expect(declared[leadIdx], size.contentWidthTwips);

        // Fixed layout on every table, and a width on every cell: the grid
        // alone is only a hint, so a row without per-cell widths auto-fits.
        expect(
          RegExp('w:tblLayout w:type="fixed"').allMatches(doc).length,
          grids.length,
        );
        expect(RegExp('<w:tcW ').allMatches(doc), isNotEmpty);
        expect(doc, isNot(contains('w:tblW w:w="0" w:type="auto"')));
      });
    }
  });
}
