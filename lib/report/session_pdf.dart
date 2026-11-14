/// Session (Complete-Workflow) PDF report, tablet counterpart of the
/// desktop's DOCX/PDF session exporter
/// (dbs_annotator/utils/session_exporter.py, `_export_to_word_path`).
/// Pure function over already-parsed [SessionRow]s so it is testable
/// headless (no widgets, no platform channels beyond the optional font
/// asset, which falls back to Helvetica when absent).
///
/// Section order mirrors the desktop report: title/patient header, initial
/// clinical notes, session data table, electrode configuration, programming
/// summary. All row math lives in report_data.dart, shared with the Word
/// (.docx) builder so the two formats never drift.
///
/// Graphics come in as PNG bytes the caller rasterised: the scales-timeline
/// chart (ui/scales_chart_painter.dart) and the electrode leads
/// (ui/report_images.dart). The PDF and Word reports therefore show the
/// identical graphic, and the builder stays a pure function that needs no
/// Flutter engine.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_info.dart' show appName, appVersion, kNotice;
import 'attestation.dart';
import 'report_data.dart';
import 'report_fonts.dart';
import 'report_palette.dart';
import 'report_sections.dart';
import 'report_text.dart';

/// Page margins, matching the desktop report's document (0.5 in sides,
/// 0.75 in top/bottom) rather than dart_pdf's 2 cm default.
///
/// Not cosmetic: the Word builder uses the desktop's margins, so with
/// dart_pdf's the same "a quarter of the content width" formula produced
/// 114.5 pt leads in the PDF and 126.3 pt in Word for identical data. Matching
/// the geometry is what makes the two documents agree, and it gives the
/// ten-column table 523 pt instead of 482 pt.
const _marginSide = 36.0; // 0.5 in
const _marginEnd = 54.0; // 0.75 in

/// Gaps in the four-lead grid, in POINTS: narrow between Left and Right of one
/// configuration, wide between Initial and Final, so the grid reads as two
/// pairs rather than four leads. The Word builder uses the same proportions.
const kElectrodePairGapPt = 4.0;
const kElectrodeGroupGapPt = 36.0;

/// One lead's width when four share [available] points.
double electrodeCellWidth(double available) =>
    (available - kElectrodeGroupGapPt - 2 * kElectrodePairGapPt) / 4;

/// Right alignment for the numeric columns among [headers].
Map<int, pw.Alignment> numericColumnAlignments(List<String> headers) => {
  for (final (i, h) in headers.indexed)
    if (kNumericTableHeaders.contains(h)) i: pw.Alignment.centerRight,
};

/// A compact bordered grid; the first row is the header when [header] is set.
/// Without [widths] the table is only as wide as its content.
pw.Widget reportGrid(
  List<List<String>> rows,
  ReportTextSanitiser t, {
  bool header = true,
  Map<int, pw.TableColumnWidth>? widths,
  double fontSize = 9,
}) => pw.TableHelper.fromTextArray(
  headers: header ? [for (final c in rows.first) t(c)] : null,
  headerCount: header ? 1 : 0,
  data: [
    for (final r in rows.skip(header ? 1 : 0)) [for (final c in r) t(c)],
  ],
  cellStyle: pw.TextStyle(fontSize: fontSize),
  headerStyle: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold),
  headerDecoration: const pw.BoxDecoration(color: pdfHeaderFill),
  cellAlignment: pw.Alignment.centerLeft,
  cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
  border: pw.TableBorder.all(color: pdfRule, width: 0.5),
  columnWidths: widths,
  tableWidth: widths == null ? pw.TableWidth.min : pw.TableWidth.max,
);

/// Cell budgets for a note, as (lines, characters). dart_pdf cannot split a
/// table row across pages, so a cell taller than a page never lays out. The
/// narrow budget fits the session table's Notes column (about 10 characters a
/// line), the wide one a column that spans most of the page. Both keep
/// all-capitals and wrapping-line worst cases within one page, with the bundled
/// font, and leave headroom for a taller page header.
typedef NoteBudget = ({int lines, int chars});
const kNarrowNoteBudget = (lines: 16, chars: 300);
const kWideNoteBudget = (lines: 24, chars: 1500);

/// Notes too long for a table cell: [cell] keeps the start in the table and
/// [section] prints the full text after it, so nothing is cut from the report.
class LongNotes {
  final _entries = <({String label, String text})>[];

  /// [text] unchanged when it fits [budget], else its start and a pointer.
  String cell(String text, String label, NoteBudget budget) {
    final body = text.trimRight();
    final lines = '\n'.allMatches(body).length + 1;
    if (lines <= budget.lines && body.length <= budget.chars) return text;
    _entries.add((label: label, text: body));
    final head = body.split('\n').take(budget.lines).join('\n');
    final clipped = String.fromCharCodes(head.runes.take(budget.chars));
    return '${clipped.trimRight()}\n(full note below)';
  }

  /// [rows] with the last cell, the Notes column, passed through [cell]. A row
  /// is named by its block and time, after [prefix].
  List<List<String>> rows(List<List<String>> rows, {String prefix = ''}) => [
    for (final r in rows)
      [
        ...r.take(r.length - 1),
        cell(r.last, _rowLabel(r, prefix), kNarrowNoteBudget),
      ],
  ];

  String _rowLabel(List<String> row, String prefix) {
    final time = row[1]
        .split('\n')
        .where((line) => !line.startsWith('('))
        .join(' ');
    return [
      if (prefix.isNotEmpty) prefix,
      if (row.first.isNotEmpty) 'Configuration ${row.first}',
      if (time.isNotEmpty) time,
    ].join(', ');
  }

  /// The full text of every clipped note; nothing when none was clipped.
  List<pw.Widget> section(ReportTextSanitiser t) => _entries.isEmpty
      ? const []
      : [
          pw.SizedBox(height: 8),
          pw.Header(level: 2, text: 'Full notes'),
          for (final e in _entries) ...[
            pw.Text(
              t(e.label.isEmpty ? 'Note' : e.label),
              style: const pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              t(e.text),
              style: const pw.TextStyle(fontSize: 9),
              overflow: pw.TextOverflow.span,
            ),
            pw.SizedBox(height: 6),
          ],
        ];
}

/// [notes] under [heading] as a Date / Time / Note grid; nothing when empty.
List<pw.Widget> datedNotesPdf(
  String heading,
  List<DatedNote> notes,
  ReportTextSanitiser t,
) {
  if (notes.isEmpty) return const [];
  final long = LongNotes();
  return [
    pw.SizedBox(height: 8),
    pw.Header(level: 2, text: heading),
    reportGrid(
      [
        ['Date', 'Time', 'Note'],
        for (final n in notes)
          [
            n.date,
            n.time,
            long.cell(n.text, '${n.date} ${n.time}'.trim(), kWideNoteBudget),
          ],
      ],
      t,
      widths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1.5),
        2: pw.FlexColumnWidth(8),
      },
    ),
    ...long.section(t),
  ];
}

/// "Scales rated per block: 3-5, so blocks are not directly comparable."
/// Null when every block rated the same number of scales.
String? _ratedNote(SessionReportData data) {
  final counts = data.scalesRated.values.toSet();
  if (counts.length < 2) return null;
  final lo = counts.reduce((a, b) => a < b ? a : b);
  final hi = counts.reduce((a, b) => a > b ? a : b);
  return 'Ratings per configuration: $lo-$hi. The index averages only the '
      'scales rated at each configuration, so configurations with different '
      'rated sets are not directly comparable.';
}

/// One lead's configuration in words, for the caption under its drawing.
String _leadDetail(LateralTokens? tokens, bool left) =>
    tokens == null ? '' : lateralText(tokens, left: left);

/// A PNG scaled to exactly [width] points, height following its aspect ratio.
///
/// Always size an embedded image explicitly: dart_pdf lays a bare `pw.Image`
/// out at the PNG's PIXEL dimensions, so a print-resolution raster silently
/// becomes a widget hundreds of points tall and the whole page fails to
/// generate.
pw.Widget _fitWidth(Uint8List png, double width) {
  final image = pw.MemoryImage(png);
  final w = image.width ?? 0;
  final h = image.height ?? 0;
  return pw.Image(image, width: width, height: w > 0 ? width * h / w : null);
}

/// One column of the electrode grid: a caption and, under it, that lead.
///
/// [width] is a fixed quarter of the content area, so all four leads come out
/// the same size as each other and as the Word document's, which quarters the
/// content area too. Sizing by HEIGHT instead makes the drawn width depend on
/// the raster's aspect ratio, which put the PDF's leads at 80 pt against Word's
/// 126 pt for identical data.
///
/// A missing lead still occupies its full cell: a zero-height placeholder lets
/// one absent lead shift the others sideways and shorten the row.
pw.Widget _electrodeCell(
  String caption,
  Uint8List? png,
  double width, {
  double? imageHeight,
  String detail = '',
}) {
  return pw.SizedBox(
    width: width,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(caption, style: const pw.TextStyle(fontSize: 8)),
        // The drawing shows WHICH contacts are active but not how the current
        // is shared between them, so `2b 60% / 2c 40%` and its reverse are the
        // same picture; for current steering that split IS the configuration.
        if (detail.isNotEmpty)
          pw.Text(
            detail,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8),
          ),
        pw.SizedBox(height: 2),
        if (png != null)
          _fitWidth(png, width)
        else
          pw.SizedBox(
            height: imageHeight,
            child: pw.Center(
              child: pw.Text(
                '(not recorded)',
                style: const pw.TextStyle(fontSize: 8, color: pdfInk),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Optional pre-rendered electrode PNGs, initial and final by side, from the
/// screen's `renderElectrodePng`. When absent (headless tests) the electrode
/// section falls back to anode/cathode token text.
typedef ElectrodeReportImages = ({
  Uint8List? initLeft,
  Uint8List? initRight,
  Uint8List? finalLeft,
  Uint8List? finalRight,
});

/// Legend + scale targets + disclaimer, shown under the table whenever a
/// ranking was applied. Mirrors `report_common.add_table_legend`.
List<pw.Widget> _legendBlock(SessionReportData data, ReportTextSanitiser t) {
  // No targets, no ranking, and the document says so rather than leaving the
  // reader to wonder why nothing is green.
  if (!data.hasTargets) {
    return [
      pw.SizedBox(height: 4),
      pw.Text(
        t(data.targetsText),
        style: const pw.TextStyle(fontSize: 9, color: pdfInk),
      ),
    ];
  }
  if (data.bestBlocks.isEmpty && data.secondBlocks.isEmpty) return const [];
  pw.Widget swatch(PdfColor fill, String label) => pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Container(width: 10, height: 8, color: fill),
      pw.SizedBox(width: 4),
      pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
    ],
  );
  // One widget, so a page break cannot separate the disclaimer from the
  // shading it qualifies: the block moves to the next page whole.
  return [
    pw.SizedBox(height: 4),
    pw.Inseparable(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: _legendLines(data, t, swatch),
      ),
    ),
  ];
}

List<pw.Widget> _legendLines(
  SessionReportData data,
  ReportTextSanitiser t,
  pw.Widget Function(PdfColor, String) swatch,
) {
  return [
    pw.Row(
      children: [
        pw.Text(
          'Legend: ',
          style: const pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        swatch(pdfBestFill, 'Highest aggregate index in this session (rank 1)'),
        pw.SizedBox(width: 14),
        swatch(pdfSecondFill, 'Second highest in this session (rank 2)'),
      ],
    ),
    if (data.targetsText.isNotEmpty)
      pw.Text(
        'Scale targets: ${t(data.targetsText)}',
        style: const pw.TextStyle(fontSize: 9),
      ),
    // The index averages only the scales rated AT that block, so blocks with
    // different rated sets are not comparable: one where a single low scale was
    // rated can outrank a fully-rated block.
    if (_ratedNote(data) != null)
      pw.Text(_ratedNote(data)!, style: const pw.TextStyle(fontSize: 8)),
    // Which blocks the top setting covers, and what a margin on this index is
    // actually worth in this session.
    if (data.bestSettingText.isNotEmpty)
      pw.Text(data.bestSettingText, style: const pw.TextStyle(fontSize: 8)),
    if (data.rankingResolutionNote != null)
      pw.Text(
        data.rankingResolutionNote!,
        style: const pw.TextStyle(fontSize: 8),
      ),
    // State the method, not just the modes: the equal weighting across every
    // scale is a clinical judgement and was invisible.
    pw.Text(data.indexMethod, style: const pw.TextStyle(fontSize: 8)),
    pw.SizedBox(height: 2),
    pw.Text(
      kRankingDisclaimer,
      style: const pw.TextStyle(fontSize: 9, color: pdfInk),
    ),
  ];
}

/// Build the session-report PDF.
///
/// Takes the already-computed [data] rather than raw rows. The caller needs it
/// anyway, to rasterise the chart and pick the electrode rows, and computing it
/// twice ran `DateTime.now()` twice, so an export at 23:59:59.999 could print
/// two different dates in one document. Passing it in also guarantees the PDF
/// and the Word document are built from identical numbers and targets.
///
/// [subjectId] is the BIDS subject label (without the "sub-" prefix).
/// [electrodeImages] and [chartPng], when supplied, render the electrode
/// section as lead images and the session data as the shared timeline chart.
///
/// [sections] gates each section. The title and patient header are always
/// present, so the document is never anonymous.
Future<ReportBytes> buildSessionPdf({
  required SessionReportData data,
  required String subjectId,
  ElectrodeReportImages? electrodeImages,
  Uint8List? chartPng,
  PdfPageFormat pageFormat = PdfPageFormat.a4,
  Set<ReportSection> sections = kAllReportSections,
  ReportAttestation attestation = kNoAttestation,
}) async {
  // Prefer rendered electrode images when the screen supplied them.
  final ei = electrodeImages;
  final hasElectrodeImages =
      ei != null &&
      (ei.initLeft != null ||
          ei.initRight != null ||
          ei.finalLeft != null ||
          ei.finalRight != null);

  // Data-row indices that begin a new block. TableHelper counts the header as
  // row 0, and `cellDecoration` is called with the same numbering.
  final blockStartRows = <int>{};
  var previousLabel = '';
  for (var i = 0; i < data.tableData.length; i++) {
    final label = data.tableData[i].first;
    if (label != previousLabel) {
      if (i > 0) blockStartRows.add(i + 1);
      previousLabel = label;
    }
  }

  // Header is table row 0, so data row i is table row i + 1.
  final rowFills = {for (final e in data.rowFills.entries) e.key + 1: e.value};

  // Unicode theme when the IBM Plex assets are bundled; null means built-in
  // Helvetica, which can only encode Latin-1. dart_pdf does not throw on an
  // unsupported rune, it silently draws an empty placeholder box, so without
  // the sanitiser a smart apostrophe from an iPad note would leave a blank
  // rectangle in a clinical document with no error. See report_text.dart.
  final fonts = await loadReportFonts();
  final theme = fonts.theme;
  final t = ReportTextSanitiser(coverage: fonts.coverage);
  final longNotes = LongNotes();
  final tableData = t.rows(longNotes.rows(data.tableRows));
  // An /Info dictionary, so the file says what it is, who made it and when
  // once it reaches a document system and its name is no longer the only clue.
  final title = 'DBS session report - sub-$subjectId - ${data.sessionDate}';
  final doc = pw.Document(
    theme: theme,
    title: title,
    author: '$appName v$appVersion',
    creator: '$appName v$appVersion',
    subject: 'Deep brain stimulation programming session',
  );
  const cellStyle = pw.TextStyle(fontSize: 8);
  final wantsChart = sections.contains(ReportSection.chart);
  final wantsTable = sections.contains(ReportSection.table);

  // Same margins as the Word document, so "a quarter of the content width"
  // means the same number of points in both.
  final format = pageFormat.copyWith(
    marginLeft: _marginSide,
    marginRight: _marginSide,
    marginTop: _marginEnd,
    marginBottom: _marginEnd,
  );

  // A quarter of the content width per lead, less a little breathing room: the
  // same budget the Word builder uses. The height is only needed for the
  // missing-lead placeholder, and follows the renderer's 900x1920 aspect.
  final leadWidth = electrodeCellWidth(format.availableWidth);
  final leadHeight = leadWidth * 1920 / 900;
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      // Every page attributable on its own: with page numbers alone, a
      // continuation page that escapes the staple carries no patient, no date
      // and no provenance. Both formats carry the same line.
      footer: (context) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          'sub-${t(subjectId)}  |  ${data.sessionStamp}  |  '
          '$appName v$appVersion  |  Not a medical device  |  '
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: pdfInk),
        ),
      ),
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Text(
            '$appName - Session report',
            style: const pw.TextStyle(
              fontSize: 17,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Text(
          'Patient: sub-${t(subjectId)}    '
          'Session: ${data.sessionStamp}'
          '${data.laterRun.isEmpty ? '' : '    Run: ${data.laterRun}'}',
        ),
        if (data.sessionDetails.isNotEmpty) pw.Text(t(data.sessionDetails)),
        pw.Text(
          'Generated on: ${data.generatedOn} by $appName v$appVersion'
          '${data.sourceFile.isEmpty ? '' : '  |  Source: '
                    '${t(data.sourceFile)} (${data.rowCount} rows)'}',
          style: const pw.TextStyle(fontSize: 9, color: pdfInk),
        ),
        pw.Text(kNotice, style: const pw.TextStyle(fontSize: 9, color: pdfInk)),
        pw.SizedBox(height: 8),

        // What the patient left on. Labelled "last recorded", not "final":
        // nothing in the TSV says a clinician confirmed it.
        if (data.lastConfig.isNotEmpty) ...[
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              color: pdfPanelFill,
              border: pw.Border.all(color: pdfRule, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Arrived on and left on, side by side, so what changed
                    // does not have to be diffed out of the table by eye.
                    if (data.firstConfig.isNotEmpty)
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'At start of session',
                              style: const pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: pdfInk,
                              ),
                            ),
                            for (final e in data.firstConfig.entries)
                              pw.Text(
                                '${e.key}:  ${t(e.value)}',
                                style: const pw.TextStyle(fontSize: 9),
                              ),
                          ],
                        ),
                      ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            data.finalConfigTitle,
                            style: const pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          for (final e in data.lastConfig.entries)
                            pw.Text(
                              '${e.key}:  ${t(e.value)}',
                              style: const pw.TextStyle(fontSize: 10),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (data.responseGrid.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  reportGrid(data.responseGrid, t, fontSize: 8),
                  pw.Text(
                    kResponseNote,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 12),
        ],

        // Initial clinical notes, from the latest baseline session only.
        if (sections.contains(ReportSection.baseline)) ...[
          pw.Header(level: 1, text: 'Initial assessment (before programming)'),
          if (!data.hasInitial)
            pw.Text('No initial assessment recorded.')
          else ...[
            if (data.initScales.isNotEmpty)
              reportGrid([
                ['Scale', 'Score'],
                for (final pair in data.initScales) [pair.name, pair.value],
              ], t)
            else
              pw.Text('(no clinical scales)'),
            if (data.medications.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                'Medications: ${t(data.medications)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
            if (data.initNotes.isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                'Notes: ${t(data.initNotes)}',
                style: const pw.TextStyle(fontSize: 9),
                overflow: pw.TextOverflow.span,
              ),
            ],
          ],
          pw.SizedBox(height: 8),
        ],

        // Graph and table are independent sections, so the heading appears only
        // when at least one of them does.
        if (wantsChart || wantsTable) ...[
          if (wantsChart && chartPng != null)
            // Heading, figure and caption as one block, so a page break can
            // never leave the heading alone at the foot of a page. A bare
            // Column may span pages; Inseparable is what keeps it whole.
            pw.Inseparable(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Header(level: 1, text: 'Session data'),
                  // Size explicitly to the content width, preserving the aspect
                  // ratio. A bare pw.Image lays the PNG out at its PIXEL size,
                  // and the chart is rasterised at 3x for print, so that is
                  // ~1128 pt tall and dart_pdf throws "Widget won't fit".
                  _fitWidth(chartPng, format.availableWidth),
                  // Extracted from a .docx the figure travels alone, so the
                  // caption carries subject, session, n and what the green means.
                  pw.Text(
                    t(data.figureCaption),
                    style: const pw.TextStyle(fontSize: 8, color: pdfInk),
                  ),
                  pw.SizedBox(height: 8),
                ],
              ),
            )
          else
            pw.Header(level: 1, text: 'Session data'),
          if (wantsChart && chartPng == null && !data.chart.isEmpty)
            // The screen didn't rasterise one (headless caller); say so rather
            // than silently omitting the section's main graphic.
            pw.Text(
              '(scales timeline chart unavailable)',
              style: const pw.TextStyle(fontSize: 8, color: pdfInk),
            ),
          if (wantsTable && !data.hasRecording)
            pw.Text('No configurations tested in this session.')
          else if (wantsTable) ...[
            pw.TableHelper.fromTextArray(
              headerStyle: const pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
              headerDecoration: const pw.BoxDecoration(color: pdfHeaderFill),
              cellStyle: cellStyle,
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: numericColumnAlignments(data.tableHeaders),
              headers: data.tableHeaders,
              data: tableData,
              // The line between a block's own L and R rows is light; the
              // block boundary is the heavy rule drawn by cellDecoration.
              border: const pw.TableBorder(
                left: pw.BorderSide(),
                right: pw.BorderSide(),
                top: pw.BorderSide(),
                bottom: pw.BorderSide(),
                verticalInside: pw.BorderSide(),
                horizontalInside: pw.BorderSide(color: pdfRule, width: 0.4),
              ),
              columnWidths: {
                for (final (i, w) in data.tableWeights.indexed)
                  i: pw.FlexColumnWidth(w),
              },
              // Green shading for the best / second-best blocks, plus a heavy
              // rule where one BLOCK ends and the next begins. Without that
              // rule the inside borders draw the same line between a block's
              // own L and R rows as between two different blocks, so nothing
              // says where a configuration starts.
              cellDecoration: (col, dynamic cell, row) {
                final fill = rowFills[row];
                final isBoundary = blockStartRows.contains(row);
                if (fill == null && !isBoundary) {
                  return const pw.BoxDecoration();
                }
                return pw.BoxDecoration(
                  color: fill == null ? null : PdfColor.fromInt(fill),
                  border: pw.Border(
                    top: isBoundary
                        ? const pw.BorderSide(
                            width: 1.6,
                            color: PdfColors.black,
                          )
                        : pw.BorderSide.none,
                    left: fill != null && col == 0
                        ? pw.BorderSide(width: 2, color: PdfColor.fromInt(fill))
                        : pw.BorderSide.none,
                  ),
                );
              },
            ),
            ..._legendBlock(data, t),
            ...longNotes.section(t),
            if (data.hasStars)
              pw.Text(kStarredLegend, style: const pw.TextStyle(fontSize: 8)),
          ],
          pw.SizedBox(height: 8),
        ],

        // Electrode configuration: rendered lead images (Initial/Final ×
        // L/R) when the screen supplied them, else anode/cathode token text.
        // Wrapped so the heading, the model line, the column captions and the
        // four leads cannot be split: a merged Initial/Final header at the foot
        // of one page with its figures on the next reads as a printing fault.
        if (sections.contains(ReportSection.electrodes))
          pw.Inseparable(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(level: 1, text: 'Electrode configuration'),
                if (!data.hasElectrodeConfig)
                  pw.Text('No electrode configuration recorded.')
                else ...[
                  if (data.electrodeModel.isNotEmpty)
                    pw.Text('Electrode model: ${t(data.electrodeModel)}'),
                  pw.SizedBox(height: 4),
                  if (hasElectrodeImages) ...[
                    // ONE row of four leads under a merged Initial/Final
                    // header, as Word lays it out. Two stacked rows cost ~380 pt
                    // of height and break the section across pages; 4 x ~114 pt
                    // of width fits in 482 pt.
                    pw.Row(
                      children: [
                        for (final (i, title) in [
                          'At start of session',
                          data.finalConfigTitle,
                        ].indexed) ...[
                          if (i > 0) pw.SizedBox(width: kElectrodeGroupGapPt),
                          pw.SizedBox(
                            width: leadWidth * 2 + kElectrodePairGapPt,
                            child: pw.Text(
                              title,
                              textAlign: pw.TextAlign.center,
                              style: const pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    pw.SizedBox(height: 2),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _electrodeCell(
                          'Left',
                          ei.initLeft,
                          leadWidth,
                          imageHeight: leadHeight,
                          detail: t(_leadDetail(data.initialTokens, true)),
                        ),
                        pw.SizedBox(width: kElectrodePairGapPt),
                        _electrodeCell(
                          'Right',
                          ei.initRight,
                          leadWidth,
                          imageHeight: leadHeight,
                          detail: t(_leadDetail(data.initialTokens, false)),
                        ),
                        pw.SizedBox(width: kElectrodeGroupGapPt),
                        _electrodeCell(
                          'Left',
                          ei.finalLeft,
                          leadWidth,
                          imageHeight: leadHeight,
                          detail: t(_leadDetail(data.finalTokens, true)),
                        ),
                        pw.SizedBox(width: kElectrodePairGapPt),
                        _electrodeCell(
                          'Right',
                          ei.finalRight,
                          leadWidth,
                          imageHeight: leadHeight,
                          detail: t(_leadDetail(data.finalTokens, false)),
                        ),
                      ],
                    ),
                    // A key, because the drawing encodes polarity by COLOUR
                    // alone: useless on a mono printer or to a colour-blind
                    // reader.
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Orange = anode (+)   Blue = cathode (-)   Grey = inactive.   '
                      "A percentage is that contact's share of the total current.",
                      style: const pw.TextStyle(fontSize: 8, color: pdfInk),
                    ),
                  ] else ...[
                    // Text fallback, no rasteriser available. Vendor nomenclature
                    // here too: `E2b_E2c` is an internal identifier, and printing
                    // it here and `2b(3.3)` elsewhere describes one lead two
                    // ways.
                    for (final pair in [
                      ('At start of session', data.initialTokens),
                      (data.finalConfigTitle, data.finalTokens),
                    ])
                      if (pair.$2 != null) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(
                          pair.$1,
                          style: const pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          '  Left:   ${t(lateralText(pair.$2!, left: true))}',
                        ),
                        pw.Text(
                          '  Right:  ${t(lateralText(pair.$2!, left: false))}',
                        ),
                      ],
                  ],
                ],
                pw.SizedBox(height: 8),
              ],
            ),
          ),

        if (sections.contains(ReportSection.summary)) ...[
          pw.Header(level: 1, text: 'Programming summary'),
          if (!data.hasRows)
            pw.Text('No session data available.')
          else ...[
            reportGrid(data.extentRows, t, header: false),
            pw.SizedBox(height: 6),
            reportGrid(
              [
                ['', 'Left', 'Right'],
                ...data.parameterRows,
              ],
              t,
              widths: const {
                0: pw.FixedColumnWidth(70),
                1: pw.FlexColumnWidth(),
                2: pw.FlexColumnWidth(),
              },
            ),
          ],
        ],
        // Without this the document asserts that a machine produced it and that
        // no human stands behind it.
        ...attestationPdf(attestationFields(attestation, rated: true), t),
      ],
    ),
  );
  return (bytes: await doc.save(), lostCharacters: t.lostCharacters);
}
