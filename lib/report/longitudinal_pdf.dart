/// Longitudinal report, in PDF and Word: the tablet counterpart of the
/// desktop's longitudinal exporter.
///
/// Pure functions over already-computed [LongitudinalReportData], so both
/// formats are built from one set of numbers and are headless-testable. The
/// two figures come in as PNG bytes the caller rasterised.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_info.dart' show appName, appVersion, kNotice;
import '../core/brand_palette.dart' show rankRowTint;
import 'attestation.dart';
import 'docx_ooxml.dart';
import 'longitudinal_data.dart';
import 'longitudinal_sections.dart';
import 'report_data.dart' show ReportBytes, kNumericTableHeaders;
import 'session_docx.dart' show datedNotesDocx;
import 'session_pdf.dart'
    show
        ElectrodeReportImages,
        LongNotes,
        datedNotesPdf,
        numericColumnAlignments,
        electrodeCellWidth,
        reportGrid,
        kElectrodeGroupGapPt,
        kElectrodePairGapPt;
import 'report_fonts.dart';
import 'report_palette.dart';
import 'report_text.dart';

/// Relative column widths for [longitudinalTableHeaders].
const _tableWeights = <double>[7, 11, 37, 8, 37];

/// Page margins, matching the session report so a clinician filing both does
/// not get two different geometries for one patient.
const _marginSide = 36.0;
const _marginEnd = 54.0;

/// A PNG at exactly [width] points, aspect preserved.
///
/// Never a bare `pw.Image`: dart_pdf lays one out at the PNG's PIXEL size, so
/// a print-resolution raster becomes a widget hundreds of points tall and the
/// page fails to generate.
pw.Widget _fitWidth(Uint8List png, double width) {
  final image = pw.MemoryImage(png);
  final w = image.width ?? 0;
  final h = image.height ?? 0;
  return pw.Image(image, width: width, height: w > 0 ? width * h / w : null);
}

/// Under the Visits table, in both formats.
const kProgrammeNote =
    'The programme shown is the one the clinician marked as left on, where '
    'marked; otherwise the last configuration recorded at that visit, which '
    'is not necessarily one a clinician confirmed.';

/// Figure 1's caption, the same in both formats.
const kClinicalFigureCaption =
    'Figure 1. Clinical scale scores, one assessment per visit. Visits are '
    'evenly spaced, not drawn to time scale.';

/// Figure 2's caption, the same in both formats.
const kSessionFigureCaption =
    'Figure 2. Session scale ratings by block, grouped by visit. Each visit '
    'contributes one point per configuration tested. Visits are evenly '
    'spaced, not drawn to time scale.';

/// Heading, figure and caption as one block, so a page break never leaves the
/// heading alone at the foot of a page.
pw.Widget _figure(
  String heading,
  Uint8List png,
  String caption,
  double width,
) => pw.Inseparable(
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Header(level: 1, text: heading),
      _fitWidth(png, width),
      pw.Text(caption, style: const pw.TextStyle(fontSize: 8, color: pdfInk)),
    ],
  ),
);

/// Build the longitudinal report PDF.
Future<ReportBytes> buildLongitudinalPdf({
  required LongitudinalReportData data,
  Uint8List? clinicalChartPng,
  Uint8List? sessionChartPng,
  Map<String, ElectrodeReportImages> electrodeImages = const {},
  PdfPageFormat pageFormat = PdfPageFormat.a4,
  Set<LongitudinalSection> sections = kAllLongitudinalSections,
  ReportAttestation attestation = kNoAttestation,
}) async {
  final fonts = await loadReportFonts();
  final theme = fonts.theme;
  final t = ReportTextSanitiser(coverage: fonts.coverage);
  final format = pageFormat.copyWith(
    marginLeft: _marginSide,
    marginRight: _marginSide,
    marginTop: _marginEnd,
    marginBottom: _marginEnd,
  );
  final span = data.visits.isEmpty
      ? ''
      : '${data.visits.first.date} to ${data.visits.last.date}';

  final doc = pw.Document(
    theme: theme,
    title: 'DBS longitudinal report - sub-${data.patientId}',
    author: kDocxCreator,
    creator: kDocxCreator,
    subject: 'Deep brain stimulation longitudinal review',
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      footer: (context) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'sub-${t(data.patientId)}  |  ${data.visits.length} visits'
          '${span.isEmpty ? '' : ', $span'}  |  $appName v$appVersion'
          '  |  Not a medical device'
          '  |  Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: pdfInk),
        ),
      ),
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Text(
            '$appName - Longitudinal report',
            style: const pw.TextStyle(
              fontSize: 17,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Text(
          'Patient: sub-${t(data.patientId)}    '
          'Visits: ${data.visits.length}${span.isEmpty ? '' : '    $span'}',
        ),
        pw.Text(
          'Generated on: ${data.generatedOn} by $appName v$appVersion',
          style: const pw.TextStyle(fontSize: 9, color: pdfInk),
        ),
        pw.Text(kNotice, style: const pw.TextStyle(fontSize: 9, color: pdfInk)),

        // Mixing two patients into one longitudinal report is a safety problem,
        // so it is stated at the top of page 1, not buried in a file list.
        if (data.mismatchedPatients.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: pdfPanelFill,
              border: pw.Border.all(color: PdfColors.black, width: 1),
            ),
            child: pw.Text(
              'WARNING: the imported files name more than one patient '
              '(${t(([data.patientId, ...data.mismatchedPatients]).join(', '))}). '
              'This report combines them.',
              style: const pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
        if (latestVisitSummary(data) case final summary?) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(6),
            decoration: const pw.BoxDecoration(color: pdfPanelFill),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  t(summary.heading),
                  style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                for (final line in summary.lines) pw.Text(t(line)),
              ],
            ),
          ),
        ],
        pw.SizedBox(height: 12),

        if (data.isEmpty) ...[
          pw.Text('No session file was imported.'),
          ...datedNotesPdf('Notes', data.notesWithoutVisit, t),
        ] else ...[
          // (a) Clinical scales by visit.
          if (sections.contains(LongitudinalSection.clinicalChart)) ...[
            if (clinicalChartPng != null)
              _figure(
                'Clinical scales by visit',
                clinicalChartPng,
                kClinicalFigureCaption,
                format.availableWidth,
              )
            else ...[
              pw.Header(level: 1, text: 'Clinical scales by visit'),
              if (data.clinicalChart.isEmpty)
                pw.Text('No baseline clinical scale scores were recorded.')
              else
                pw.Text('(figure unavailable)'),
            ],
            pw.SizedBox(height: 10),
          ],

          // (b) The per-visit table.
          if (sections.contains(LongitudinalSection.visits)) ...[
            pw.Header(level: 1, text: 'Visits'),
            pw.TableHelper.fromTextArray(
              headers: longitudinalTableHeaders,
              data: t.rows(data.visitTable),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerStyle: const pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: const pw.BoxDecoration(color: pdfHeaderFill),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                for (final (i, w) in _tableWeights.indexed)
                  i: pw.FlexColumnWidth(w),
              },
            ),
            pw.Text(kProgrammeNote, style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 10),
          ],

          // (c) Session scales by visit and block.
          if (sections.contains(LongitudinalSection.sessionChart)) ...[
            if (sessionChartPng != null)
              _figure(
                'Session scales by visit and block',
                sessionChartPng,
                kSessionFigureCaption,
                format.availableWidth,
              )
            else ...[
              pw.Header(level: 1, text: 'Session scales by visit and block'),
              if (data.sessionChart.isEmpty)
                pw.Text('No session scale ratings were recorded.')
              else
                pw.Text('(figure unavailable)'),
            ],
            if (data.rankingTargets.isNotEmpty)
              pw.Text(
                t(data.rankingTargets),
                style: const pw.TextStyle(fontSize: 8),
              ),
            pw.SizedBox(height: 10),
          ],

          // (d) Every configuration of every visit, grouped by visit rather
          // than given a visit COLUMN: the session table's twelve widths are
          // sized to their headers, and a thirteenth broke them mid-word.
          if (sections.contains(LongitudinalSection.sessionTable))
            ..._sessionTable(data, t),

          // (e) Per-visit lead diagrams, the section that adds pages.
          // No heading over nothing: the drawings are only rendered on request.
          if (sections.contains(LongitudinalSection.electrodes) &&
              electrodeImages.isNotEmpty)
            ..._electrodes(data, electrodeImages, format, t),

          // (f) Per-visit parameter ranges.
          if (sections.contains(LongitudinalSection.summary))
            ..._summary(data, t),

          // (g) Sources, demoted to an appendix: provenance, not content.
          if (sections.contains(LongitudinalSection.sources)) ...[
            pw.SizedBox(height: 12),
            pw.Header(level: 1, text: 'Source files'),
            for (final line in _sourceLines(data))
              pw.Bullet(
                text: t(line),
                style: const pw.TextStyle(fontSize: 8),
                bulletSize: 1.5,
              ),
          ],
        ],
        ...attestationPdf(attestationFields(attestation, rated: true), t),
      ],
    ),
  );
  return (bytes: await doc.save(), lostCharacters: t.lostCharacters);
}

/// The same report as a .docx, saying the same things in the same words.
Uint8List buildLongitudinalDocx({
  required LongitudinalReportData data,
  Uint8List? clinicalChartPng,
  Uint8List? sessionChartPng,
  Map<String, ElectrodeReportImages> electrodeImages = const {},
  DocxPageSize pageSize = DocxPageSize.a4,
  Set<LongitudinalSection> sections = kAllLongitudinalSections,
  ReportAttestation attestation = kNoAttestation,
}) {
  final media = DocxMediaBag();
  final span = data.visits.isEmpty
      ? ''
      : '${data.visits.first.date} to ${data.visits.last.date}';

  final body = StringBuffer()
    ..write(docxPara('$appName - Longitudinal report', bold: true, size: 34))
    ..write(
      docxPara(
        'Patient: sub-${data.patientId}    '
        'Visits: ${data.visits.length}${span.isEmpty ? '' : '    $span'}',
      ),
    )
    ..write(
      docxPara(
        'Generated on: ${data.generatedOn} by $appName v$appVersion',
        size: 18,
      ),
    )
    ..write(docxPara(kNotice, size: 18));

  if (data.mismatchedPatients.isNotEmpty) {
    body.write(
      docxPara(
        'WARNING: the imported files name more than one patient '
        '(${([data.patientId, ...data.mismatchedPatients]).join(', ')}). '
        'This report combines them.',
        bold: true,
      ),
    );
  }
  if (latestVisitSummary(data) case final summary?) {
    body.write(docxPara(summary.heading, bold: true));
    for (final line in summary.lines) {
      body.write(docxPara(line));
    }
  }

  if (data.isEmpty) {
    body
      ..write(docxPara('No session file was imported.'))
      ..write(
        datedNotesDocx(
          'Notes',
          data.notesWithoutVisit,
          contentTwips: pageSize.contentWidthTwips,
        ),
      );
  } else {
    if (sections.contains(LongitudinalSection.clinicalChart)) {
      body.write(docxHeading('Clinical scales by visit'));
      if (clinicalChartPng != null) {
        body
          ..write(
            '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
            '${media.drawing(clinicalChartPng, widthPx: pageSize.contentWidthPx, description: 'Clinical scale scores by visit')}</w:p>',
          )
          ..write(docxPara(kClinicalFigureCaption, size: 16));
      } else if (data.clinicalChart.isEmpty) {
        body.write(
          docxPara('No baseline clinical scale scores were recorded.'),
        );
      }
    }

    if (sections.contains(LongitudinalSection.visits)) {
      body
        ..write(docxHeading('Visits'))
        ..write(
          docxTable(
            longitudinalTableHeaders,
            data.visitTable,
            weights: _tableWeights,
            contentTwips: pageSize.contentWidthTwips,
          ),
        )
        ..write(docxPara(kProgrammeNote, size: 16));
    }

    if (sections.contains(LongitudinalSection.sessionChart)) {
      body.write(docxHeading('Session scales by visit and block'));
      if (sessionChartPng != null) {
        body
          ..write(
            '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
            '${media.drawing(sessionChartPng, widthPx: pageSize.contentWidthPx, description: 'Session scale ratings by visit and block')}</w:p>',
          )
          ..write(docxPara(kSessionFigureCaption, size: 16));
      } else if (data.sessionChart.isEmpty) {
        body.write(docxPara('No session scale ratings were recorded.'));
      }
      if (data.rankingTargets.isNotEmpty) {
        body.write(docxPara(data.rankingTargets, size: 16));
      }
    }

    if (sections.contains(LongitudinalSection.sessionTable)) {
      body.write(docxHeading('Session data'));
      final ref = data.visits.first;
      for (final entry in data.timeline) {
        if (entry.noteDay case final day?) {
          body
            ..write(docxHeading2(day.date))
            ..write(
              docxTable(
                data.tableHeadersFor(ref),
                day.rows,
                weights: ref.session.tableWeights,
                contentTwips: pageSize.contentWidthTwips,
              ),
            );
          continue;
        }
        final v = entry.visit!;
        if (v.session.tableData.isEmpty) continue;
        body
          ..write(docxHeading2(_visitLabel(v)))
          ..write(
            docxTable(
              data.tableHeadersFor(v),
              data.tableRowsFor(v),
              weights: v.session.tableWeights,
              lightInsideH: true,
              rowRules: _blockStarts(v.session.tableRows),
              rowFills: data.rowFillsFor(v),
              rightColumns: {
                for (final (i, h) in data.tableHeadersFor(v).indexed)
                  if (kNumericTableHeaders.contains(h)) i,
              },
              contentTwips: pageSize.contentWidthTwips,
            ),
          );
      }
      if (_anyShaded(data)) {
        body
          ..write(docxPara(kVisitRankingLegend, size: 16))
          ..write(docxPara(data.rankingTargets, size: 16));
      }
    }

    if (sections.contains(LongitudinalSection.electrodes) &&
        electrodeImages.isNotEmpty) {
      body.write(docxHeading('Electrode configuration'));
      for (final v in data.visits) {
        final gfx = electrodeImages[v.filename];
        if (gfx == null) continue;
        body.write(docxHeading2(_visitLabel(v)));
        for (final (label, png) in [
          ('Initial L', gfx.initLeft),
          ('Initial R', gfx.initRight),
          ('Last L', gfx.finalLeft),
          ('Last R', gfx.finalRight),
        ]) {
          if (png == null) continue;
          body.write(
            '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
            '${media.drawing(png, widthPx: pageSize.contentWidthPx / 4, description: '$label lead')}</w:p>',
          );
        }
      }
    }

    if (sections.contains(LongitudinalSection.summary)) {
      body.write(docxHeading('Programming summary'));
      for (final v in data.visits) {
        body.write(docxHeading2(_visitLabel(v)));
        body
          ..write(
            docxTable(
              null,
              v.session.extentRows,
              weights: const [3, 2],
              contentTwips: pageSize.contentWidthTwips * 3 ~/ 5,
            ),
          )
          ..write(docxPara(''))
          ..write(
            docxTable(
              const ['', 'Left', 'Right'],
              v.session.parameterRows,
              weights: const [1, 3, 3],
              contentTwips: pageSize.contentWidthTwips,
            ),
          );
      }
    }

    if (sections.contains(LongitudinalSection.sources)) {
      body.write(docxHeading('Source files'));
      for (final line in _sourceLines(data)) {
        body.write(docxPara('  • $line', size: 16));
      }
    }
  }
  body.write(attestationDocx(attestationFields(attestation, rated: true)));

  return packDocx(
    body: body.toString(),
    pageSize: pageSize,
    media: media,
    title: 'DBS longitudinal report - sub-${data.patientId}',
    subject: 'Deep brain stimulation longitudinal review',
    createdDate: data.generatedOn,
    footerPrefix:
        'sub-${data.patientId}  |  ${data.visits.length} visits'
        '${span.isEmpty ? '' : ', $span'}  |  $appName v$appVersion'
        '  |  Not a medical device  |  Page ',
  );
}

/// "2026-02-03 run 01", the per-visit subheading both formats use.
String _visitLabel(LongitudinalVisit v) =>
    '${v.date}${v.run.isEmpty ? '' : ' run ${v.run}'}';

/// Every uploaded file, sessions then notes, for the Source files list.
List<String> _sourceLines(LongitudinalReportData data) => [
  for (final v in data.visits) '${v.filename}  (${v.blocks.length} blocks)',
  for (final f in data.noteFiles) '$f  (notes)',
];

/// (d) Every configuration of every visit, under a per-visit subheading rather
/// than with a visit column: the twelve column widths are sized to their own
/// headers, and a thirteenth broke them mid-word.
List<pw.Widget> _sessionTable(
  LongitudinalReportData data,
  ReportTextSanitiser t,
) {
  final long = LongNotes();
  return [
    pw.SizedBox(height: 12),
    pw.Header(level: 1, text: 'Session data'),
    for (final entry in data.timeline)
      if (entry.noteDay case final day?) ...[
        pw.SizedBox(height: 6),
        pw.Text(
          t(day.date),
          style: const pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.TableHelper.fromTextArray(
          headers: data.tableHeadersFor(data.visits.first),
          data: t.rows(long.rows(day.rows, prefix: day.date)),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: const pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          headerDecoration: const pw.BoxDecoration(color: pdfHeaderFill),
          cellAlignment: pw.Alignment.centerLeft,
          columnWidths: {
            for (final (i, w) in data.visits.first.session.tableWeights.indexed)
              i: pw.FlexColumnWidth(w),
          },
        ),
      ] else if (entry.visit case final v?
          when v.session.tableData.isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.Text(
          t('${v.date}${v.run.isEmpty ? '' : ' run ${v.run}'}'),
          style: const pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.TableHelper.fromTextArray(
          headers: data.tableHeadersFor(v),
          data: t.rows(long.rows(data.tableRowsFor(v), prefix: _visitLabel(v))),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerStyle: const pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
          headerDecoration: const pw.BoxDecoration(color: pdfHeaderFill),
          cellAlignment: pw.Alignment.centerLeft,
          cellAlignments: numericColumnAlignments(data.tableHeadersFor(v)),
          columnWidths: {
            for (final (i, w) in v.session.tableWeights.indexed)
              i: pw.FlexColumnWidth(w),
          },
          border: const pw.TableBorder(
            left: pw.BorderSide(),
            right: pw.BorderSide(),
            top: pw.BorderSide(),
            bottom: pw.BorderSide(),
            verticalInside: pw.BorderSide(),
            horizontalInside: pw.BorderSide(color: pdfRule, width: 0.4),
          ),
          // Header is row 0, so data row i is table row i + 1.
          cellDecoration: (col, dynamic cell, row) {
            final fill = data.rowFillsFor(v)[row - 1];
            return pw.BoxDecoration(
              color: fill == null ? null : PdfColor.fromInt(rankRowTint(fill)),
              border: pw.Border(
                top: _blockStarts(v.session.tableRows).contains(row - 1)
                    ? const pw.BorderSide(width: 1.2)
                    : pw.BorderSide.none,
                left: fill != null && col == 0
                    ? pw.BorderSide(width: 2, color: PdfColor.fromInt(fill))
                    : pw.BorderSide.none,
              ),
            );
          },
        ),
      ],
    if (_anyShaded(data)) ...[
      pw.SizedBox(height: 4),
      pw.Text(kVisitRankingLegend, style: const pw.TextStyle(fontSize: 8)),
      pw.Text(t(data.rankingTargets), style: const pw.TextStyle(fontSize: 8)),
    ],
    ...long.section(t),
  ];
}

bool _anyShaded(LongitudinalReportData data) => data.rankedBlocks.isNotEmpty;

/// Data-row indices where a new block starts, after the first: a block is
/// its L and R rows, so only the boundary between blocks gets a heavy rule.
Set<int> _blockStarts(List<List<String>> rows) => {
  for (var i = 1; i < rows.length; i++)
    if (rows[i].first != rows[i - 1].first) i,
};

/// (e) Per-visit lead diagrams. Four images a visit, so this is the section
/// that turns a three-page report into a ten-page one.
List<pw.Widget> _electrodes(
  LongitudinalReportData data,
  Map<String, ElectrodeReportImages> images,
  PdfPageFormat format,
  ReportTextSanitiser t,
) {
  final leadWidth = electrodeCellWidth(format.availableWidth);
  return [
    pw.SizedBox(height: 12),
    pw.Header(level: 1, text: 'Electrode configuration'),
    for (final v in data.visits)
      if (images[v.filename] case final gfx?)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 6),
            pw.Text(
              t('${v.date}${v.run.isEmpty ? '' : ' run ${v.run}'}'),
              style: const pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Row(
              children: [
                for (final (i, (label, png)) in [
                  ('Initial L', gfx.initLeft),
                  ('Initial R', gfx.initRight),
                  ('Last L', gfx.finalLeft),
                  ('Last R', gfx.finalRight),
                ].indexed)
                  pw.Container(
                    width: leadWidth,
                    margin: pw.EdgeInsets.only(
                      right: i == 1
                          ? kElectrodeGroupGapPt
                          : i == 3
                          ? 0
                          : kElectrodePairGapPt,
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
                        if (png != null)
                          _fitWidth(png, leadWidth)
                        else
                          pw.Text(
                            '(not recorded)',
                            style: const pw.TextStyle(
                              fontSize: 8,
                              color: pdfInk,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
  ];
}

/// (f) Per-visit parameter ranges and how many configurations were tried.
List<pw.Widget> _summary(LongitudinalReportData data, ReportTextSanitiser t) =>
    [
      pw.SizedBox(height: 12),
      pw.Header(level: 1, text: 'Programming summary'),
      for (final v in data.visits)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 6),
            pw.Text(
              t('${v.date}${v.run.isEmpty ? '' : ' run ${v.run}'}'),
              style: const pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 2),
            // Same tables as the session report's summary.
            reportGrid(v.session.extentRows, t, header: false, fontSize: 8),
            pw.SizedBox(height: 3),
            reportGrid(
              [
                ['', 'Left', 'Right'],
                ...v.session.parameterRows,
              ],
              t,
              fontSize: 8,
              widths: const {
                0: pw.FixedColumnWidth(62),
                1: pw.FlexColumnWidth(),
                2: pw.FlexColumnWidth(),
              },
            ),
          ],
        ),
    ];
