/// Session (Complete-Workflow) Word (.docx) report, the tablet counterpart of
/// the desktop's DOCX exporter (dbs_annotator/utils/session_exporter.py).
///
/// A pure function over already-parsed [SessionRow]s, so it is
/// headless-testable. Sections and row math are shared with the PDF via
/// report_data.dart, and the graphics are the same PNG bytes the PDF embeds,
/// passed in by the caller, so the two formats cannot drift.
///
/// Unlike the PDF there is no font concern: the XML is UTF-8 and Word uses
/// system fonts, so any character renders without sanitising.
library;

import 'dart:typed_data';

import '../app_info.dart' show appName, appVersion, kNotice;
import 'attestation.dart';
import 'docx_ooxml.dart';
import '../core/brand_palette.dart';
import 'report_data.dart';
import 'report_sections.dart';
import 'session_pdf.dart'
    show ElectrodeReportImages, electrodeCellWidth, kElectrodePairGapPt;

// Callers ask this library for the page size and the PNG reader, so keep them
// reachable here rather than making every call site learn where they moved.
export 'docx_ooxml.dart' show DocxPageSize, pngSize;

/// [notes] under [heading] as a Date / Time / Note table; '' when empty.
String datedNotesDocx(
  String heading,
  List<DatedNote> notes, {
  required int contentTwips,
}) => notes.isEmpty
    ? ''
    : docxHeading2(heading) +
          docxTable(
            const ['Date', 'Time', 'Note'],
            [
              for (final n in notes) [n.date, n.time, n.text],
            ],
            weights: const [2, 1.5, 8],
            contentTwips: contentTwips,
          );

/// A borderless table for the electrode-image grid, so the images sit in a
/// clean 4-column layout with no visible cell edges.
String _borderlessTable(
  List<String> rowsXml, {
  required List<int> widths,
  required int contentTwips,
}) {
  final b = StringBuffer(
    '<w:tbl><w:tblPr><w:tblW w:w="$contentTwips" w:type="dxa"/>'
    '<w:tblBorders>',
  );
  for (final side in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
    b.write('<w:$side w:val="none" w:sz="0" w:space="0" w:color="auto"/>');
  }
  b.write('</w:tblBorders>');
  b.write(docxTblGrid(widths));
  b.writeAll(rowsXml);
  b.write('</w:tbl>');
  return b.toString();
}

/// A centred cell holding arbitrary run XML, optionally spanning [span]
/// columns; [widthTwips] is the width of everything it spans.
String _xmlCell(String runsXml, {int span = 1, int? widthTwips}) {
  final grid = span > 1 ? '<w:gridSpan w:val="$span"/>' : '';
  final w = widthTwips == null ? '' : '<w:tcW w:w="$widthTwips" w:type="dxa"/>';
  return '<w:tc><w:tcPr>$w$grid</w:tcPr>'
      '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>$runsXml</w:p></w:tc>';
}

/// A centred text cell for the electrode grid's caption rows.
String _captionCell(
  String text, {
  bool bold = false,
  int span = 1,
  int? widthTwips,
}) => _xmlCell(
  docxRun(text, bold: bold, size: 16),
  span: span,
  widthTwips: widthTwips,
);

/// Per-lead caption under an electrode image: "+ case" / "- 2b(3.3) 2c(2.2)".
/// Goes through the shared vendor-nomenclature helper: `E2b_E2c` is an
/// internal identifier, and an underscore-joined current reads as a dose.
String _tokenCaption(LateralTokens? tokens, {required bool left}) =>
    tokens == null ? '' : lateralText(tokens, left: left);

/// The response grid, one column per scale, as the PDF prints it.
String _responseTable(SessionReportData data, DocxPageSize pageSize) {
  final grid = data.responseGrid;
  return docxTable(
    grid.first,
    grid.skip(1).toList(),
    weights: [1.4, for (var i = 1; i < grid.first.length; i++) 1],
    contentTwips: pageSize.contentWidthTwips,
  );
}

/// Twin of the PDF's rated-per-block note, so both documents say it.
String? _ratedNote(SessionReportData data) {
  final counts = data.scalesRated.values.toSet();
  if (counts.length < 2) return null;
  final lo = counts.reduce((a, b) => a < b ? a : b);
  final hi = counts.reduce((a, b) => a > b ? a : b);
  return 'Ratings per configuration: $lo-$hi. The index averages only the '
      'scales rated at each configuration, so configurations with different '
      'rated sets are not directly comparable.';
}

/// Legend + scale targets + disclaimer under the session-data table, mirroring
/// `report_common.add_table_legend`. Returns '' when nothing was ranked.
String _legendBlock(SessionReportData data) {
  // No targets, no ranking, and the document says so.
  if (!data.hasTargets) return docxPara(data.targetsText, size: 18);
  if (data.bestBlocks.isEmpty && data.secondBlocks.isEmpty) return docxPara('');
  // A coloured square run, standing in for the desktop's coloured "■" glyph.
  String swatch(int argb) =>
      '<w:r><w:rPr><w:sz w:val="18"/><w:shd w:val="clear" w:color="auto" '
      'w:fill="${docxHex(argb)}"/></w:rPr><w:t xml:space="preserve">    </w:t></w:r>';
  final b = StringBuffer()
    ..write('<w:p>')
    ..write(docxRun('Legend: ', bold: true, size: 18))
    ..write(swatch(kBestFill))
    ..write(
      docxRun(
        ' Highest aggregate index in this session (rank 1)    ',
        size: 18,
      ),
    )
    ..write(swatch(kSecondFill))
    ..write(docxRun(' Second highest in this session (rank 2)', size: 18))
    ..write('</w:p>');
  if (data.targetsText.isNotEmpty) {
    b.write(docxPara('Scale targets: ${data.targetsText}', size: 18));
  }
  // Same items, same order as the PDF, disclaimer last.
  final rated = _ratedNote(data);
  final resolution = data.rankingResolutionNote;
  for (final line in [
    ?rated,
    if (data.bestSettingText.isNotEmpty) data.bestSettingText,
    ?resolution,
    data.indexMethod,
  ]) {
    b.write(docxPara(line, size: 16));
  }
  b.write(docxPara(kRankingDisclaimer, size: 18));
  return b.toString();
}

/// Build the session-report .docx and return its bytes. [subjectId] is the
/// BIDS subject label (without the "sub-" prefix). Mirrors the PDF's section
/// order and honours the same [sections] selection, so the two formats of one
/// export can never contain different sections.
Uint8List buildSessionDocx({
  required SessionReportData data,
  required String subjectId,
  ElectrodeReportImages? electrodeImages,
  Uint8List? chartPng,
  DocxPageSize pageSize = DocxPageSize.a4,
  Set<ReportSection> sections = kAllReportSections,
  ReportAttestation attestation = kNoAttestation,
}) {
  final media = DocxMediaBag();
  final body = StringBuffer();

  // (a) Title + patient + generated-on.
  body.write(docxPara('$appName - Session report', bold: true, size: 34));
  body.write(
    docxPara(
      'Patient: sub-$subjectId    Session: ${data.sessionStamp}'
      '${data.laterRun.isEmpty ? '' : '    Run: ${data.laterRun}'}',
    ),
  );
  if (data.sessionDetails.isNotEmpty) {
    body.write(docxPara(data.sessionDetails));
  }
  body.write(
    docxPara(
      'Generated on: ${data.generatedOn} by $appName v$appVersion'
      '${data.sourceFile.isEmpty ? '' : '  |  Source: ${data.sourceFile} '
                '(${data.rowCount} rows)'}',
      size: 18,
    ),
  );
  body.write(docxPara(kNotice, size: 18));
  if (data.lastConfig.isNotEmpty) {
    // Same page-1 summary as the PDF, in the same words.
    body.write(
      docxTable(
        ['At start of session', data.finalConfigTitle],
        [
          [
            data.firstConfig.entries
                .map((e) => '${e.key}: ${e.value}')
                .join('\n'),
            data.lastConfig.entries
                .map((e) => '${e.key}: ${e.value}')
                .join('\n'),
          ],
        ],
        weights: const [1, 1],
        contentTwips: pageSize.contentWidthTwips,
      ),
    );
    if (data.responseGrid.isNotEmpty) {
      body
        ..write(_responseTable(data, pageSize))
        ..write(docxPara(kResponseNote, size: 16));
    }
  }

  // (b) Baseline assessment. Headings and labels must match the PDF word for
  // word: two documents of one session that differ are a discovery problem.
  if (sections.contains(ReportSection.baseline)) {
    body.write(docxHeading('Initial assessment (before programming)'));
    if (!data.hasInitial) {
      body.write(docxPara('No initial assessment recorded.'));
    } else {
      if (data.initScales.isNotEmpty) {
        // A two-column table, not bullets: Y-BOCS bulleted alike with its own
        // two subscales reads as three separate findings.
        body.write(
          docxTable(
            const ['Scale', 'Score'],
            [
              for (final pair in data.initScales) [pair.name, pair.value],
            ],
            weights: const [3, 1],
            contentTwips: pageSize.contentWidthTwips ~/ 3,
          ),
        );
      } else {
        body.write(docxPara('(no clinical scales)'));
      }
      if (data.medications.isNotEmpty) {
        body.write(docxPara('Medications: ${data.medications}', size: 18));
      }
      if (data.initNotes.isNotEmpty) {
        body.write(docxPara('Notes: ${data.initNotes}', size: 18));
      }
    }
  }

  // (c) Session data: chart, then lateral table. Graph and table are
  // independent sections, so the heading appears only when at least one does.
  final wantsChart = sections.contains(ReportSection.chart);
  final wantsTable = sections.contains(ReportSection.table);
  if (wantsChart || wantsTable) {
    body.write(docxHeading('Session data'));
    if (wantsChart && chartPng != null) {
      body.write(
        '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
        '${media.drawing(chartPng, widthPx: pageSize.contentWidthPx, description: data.figureCaption)}</w:p>',
      );
      // Same caption as the PDF, word for word.
      body.write(docxPara(data.figureCaption, size: 16));
    }
    if (wantsTable && !data.hasRecording) {
      body.write(docxPara('No configurations tested in this session.'));
    } else if (wantsTable) {
      // Green shading for the best / second-best blocks, and a 3 pt rule on
      // the first row of each block (tableData holds L then R per block).
      final fills = <int, int>{};
      final rules = <int>{};
      var previousBlock = '';
      for (var i = 0; i < data.tableData.length; i++) {
        final label = data.tableData[i].first;
        if (label != previousBlock) {
          if (i > 0) rules.add(i);
          previousBlock = label;
        }
        if (data.rowFills[i] case final fill?) fills[i] = fill;
      }
      body.write(
        docxTable(
          data.tableHeaders,
          data.tableRows,
          rowFills: fills,
          rightColumns: {
            for (final (i, h) in data.tableHeaders.indexed)
              if (kNumericTableHeaders.contains(h)) i,
          },
          rowRules: rules,
          // Scales and Notes: one tall cell per block, not one per side.
          mergeDownColumns: {
            data.tableHeaders.indexOf('Scales'),
            data.tableHeaders.indexOf('Notes'),
          },
          weights: data.tableWeights,
          lightInsideH: true,
          contentTwips: pageSize.contentWidthTwips,
        ),
      );
      body.write(_legendBlock(data));
      if (data.hasStars) body.write(docxPara(kStarredLegend, size: 16));
    }
  }

  // (d) Electrode configuration: the four rendered leads in a borderless grid
  // when the caller supplied them, else anode/cathode token text.
  if (sections.contains(ReportSection.electrodes)) {
    body.write(docxHeading('Electrode configuration'));
    final ei = electrodeImages;
    final hasImages =
        ei != null &&
        (ei.initLeft != null ||
            ei.initRight != null ||
            ei.finalLeft != null ||
            ei.finalRight != null);
    if (!data.hasElectrodeConfig) {
      body.write(docxPara('No electrode configuration recorded.'));
    } else {
      if (data.electrodeModel.isNotEmpty) {
        body.write(docxPara('Electrode model: ${data.electrodeModel}'));
      }
      final it = data.initialTokens;
      final ft = data.finalTokens;
      if (hasImages) {
        // Five grid columns, the middle one empty, so the grid reads as two
        // pairs: Left and Right of one configuration close together.
        final lead = electrodeCellWidth(pageSize.contentWidthTwips / 20) * 20;
        final gap = pageSize.contentWidthTwips - 4 * lead.round();
        final cols = [
          lead.round(),
          lead.round(),
          gap,
          lead.round(),
          lead.round(),
        ];
        final cellPx = lead / 15 - kElectrodePairGapPt * 96 / 72;
        String img(Uint8List? png) =>
            png == null ? '' : media.drawing(png, widthPx: cellPx);
        String cap(String text, {bool bold = false, int span = 1}) =>
            _captionCell(
              text,
              bold: bold,
              span: span,
              widthTwips: cols[0] * span,
            );
        String cell(Uint8List? png) => _xmlCell(img(png), widthTwips: cols[0]);
        final spacer = _xmlCell('', widthTwips: gap);
        body.write(
          _borderlessTable(
            widths: cols,
            contentTwips: pageSize.contentWidthTwips,
            [
              '<w:tr>${cap('At start of session', bold: true, span: 2)}$spacer'
                  '${cap(data.finalConfigTitle, bold: true, span: 2)}</w:tr>',
              '<w:tr>${cap('Left')}${cap('Right')}$spacer'
                  '${cap('Left')}${cap('Right')}</w:tr>',
              '<w:tr>'
                  '${cap(_tokenCaption(it, left: true))}'
                  '${cap(_tokenCaption(it, left: false))}$spacer'
                  '${cap(_tokenCaption(ft, left: true))}'
                  '${cap(_tokenCaption(ft, left: false))}'
                  '</w:tr>',
              '<w:tr>${cell(ei.initLeft)}${cell(ei.initRight)}$spacer'
                  '${cell(ei.finalLeft)}${cell(ei.finalRight)}</w:tr>',
            ],
          ),
        );
        // Same key as the PDF: the drawing encodes polarity by COLOUR alone,
        // which is useless on a mono printer or to a colour-blind reader.
        body.write(
          docxPara(
            'Orange = anode (+)   Blue = cathode (-)   Grey = inactive.   '
            "A percentage is that contact's share of the total current.",
            size: 16,
          ),
        );
        body.write(docxPara(''));
      } else {
        // Vendor nomenclature here too, through the SAME helper the PDF's
        // fallback uses; report_parity_test catches a divergence.
        for (final pair in [
          ('At start of session', it),
          (data.finalConfigTitle, ft),
        ]) {
          final tokens = pair.$2;
          if (tokens == null) continue;
          body.write(docxPara(pair.$1, bold: true));
          body.write(docxPara('  Left:   ${lateralText(tokens, left: true)}'));
          body.write(docxPara('  Right:  ${lateralText(tokens, left: false)}'));
        }
      }
    }
  }

  // (e) Programming summary.
  if (sections.contains(ReportSection.summary)) {
    body.write(docxHeading('Programming summary'));
    if (!data.hasRows) {
      body.write(docxPara('No session data available.'));
    } else {
      body.write(
        docxTable(
          null,
          data.extentRows,
          weights: const [3, 2],
          contentTwips: pageSize.contentWidthTwips * 3 ~/ 5,
        ),
      );
      body.write(docxPara(''));
      body.write(
        docxTable(
          const ['', 'Left', 'Right'],
          data.parameterRows,
          weights: const [1, 3, 3],
          contentTwips: pageSize.contentWidthTwips,
        ),
      );
    }
  }

  // Attestation, so the document does not stand on a machine's word alone.
  body.write(attestationDocx(attestationFields(attestation, rated: true)));

  // Packaging is shared with the annotations report: one implementation of the
  // content-types and relationships Word would otherwise offer to repair.
  return packDocx(
    body: body.toString(),
    pageSize: pageSize,
    media: media,
    title: 'DBS session report - sub-$subjectId - ${data.sessionDate}',
    subject: 'Deep brain stimulation programming session',
    createdDate: data.generatedOn,
    footerPrefix:
        'sub-$subjectId  |  ${data.sessionStamp}  |  '
        '$appName v$appVersion  |  Not a medical device  |  Page ',
  );
}
