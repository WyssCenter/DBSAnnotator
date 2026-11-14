/// Hand-built OOXML primitives shared by every .docx this app writes.
///
/// A .docx is a zip of parts that reference each other: a `w:pStyle` with no
/// styles part, an image with no content-type default, a footer with no
/// relationship, a table grid that does not sum to its declared width. Word
/// answers each of those with a repair prompt and no diagnostic, so the
/// packaging is implemented once, here.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../app_info.dart' show appName, appVersion;
import '../core/brand_palette.dart';

/// ARGB int to the RRGGBB hex Word expects in `w:fill`.
String docxHex(int argb) =>
    (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

/// XML-escape text content, and drop the characters XML 1.0 cannot represent:
/// most C0 controls (U+0000-U+0008, U+000B, U+000C, U+000E-U+001F) have no
/// legal representation at all, not even as a numeric entity, and one reaching
/// `document.xml` makes Word reject the whole report. They arrive easily in
/// pasted text. Tab, newline and carriage return are legal and are kept.
String docxEsc(String s) {
  final out = StringBuffer();
  for (final rune in s.runes) {
    final legal =
        rune == 0x09 ||
        rune == 0x0A ||
        rune == 0x0D ||
        (rune >= 0x20 && rune != 0xFFFE && rune != 0xFFFF);
    if (!legal) continue;
    out.write(switch (rune) {
      0x26 => '&amp;',
      0x3C => '&lt;',
      0x3E => '&gt;',
      0x22 => '&quot;',
      _ => String.fromCharCode(rune),
    });
  }
  return out.toString();
}

/// A run of text (size in half-points), with embedded newlines turned into
/// `<w:br/>` so multi-line table cells / notes wrap inside one paragraph.
String docxRun(String text, {bool bold = false, int size = 18}) {
  final rPr =
      '<w:rPr>${bold ? '<w:b/>' : ''}'
      '<w:sz w:val="$size"/><w:szCs w:val="$size"/></w:rPr>';
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final parts = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (i > 0) parts.add('<w:br/>');
    parts.add('<w:t xml:space="preserve">${docxEsc(lines[i])}</w:t>');
  }
  return '<w:r>$rPr${parts.join()}</w:r>';
}

String docxPara(String text, {bool bold = false, int size = 18}) =>
    '<w:p>${docxRun(text, bold: bold, size: size)}</w:p>';

/// A section heading, as a real `Heading1` paragraph. The `w:pStyle` is what
/// fills Word's navigation pane, allows a table of contents and stops
/// assistive technology seeing flat body text; the direct bold and size are
/// kept so it still looks right if the consumer's template lacks the style.
String docxHeading(String text) =>
    '<w:p><w:pPr><w:pStyle w:val="Heading1"/>'
    '<w:spacing w:before="240" w:after="60"/></w:pPr>'
    '${docxRun(text, bold: true, size: 26)}</w:p>';

String docxHeading2(String text) =>
    '<w:p><w:pPr><w:pStyle w:val="Heading2"/>'
    '<w:spacing w:before="120" w:after="40"/></w:pPr>'
    '${docxRun(text, bold: true, size: 20)}</w:p>';

/// Vertical-merge state, for cells spanning a block's two lateral rows.
enum DocxVMerge { none, start, rest }

/// One table cell (8pt to match the PDF), optionally bold / shaded / ruled.
/// [widthTwips] emits `<w:tcW w:type="dxa">`, which Word's fixed layout needs
/// on EVERY cell: the grid alone is a hint, and a row without per-cell widths
/// falls back to auto-fitting.
String docxCell(
  String text, {
  bool bold = false,
  String? fill,
  bool topRule = false,
  String? leftRule,
  bool right = false,
  int? widthTwips,
  DocxVMerge vMerge = DocxVMerge.none,
}) {
  final shd = fill == null
      ? ''
      : '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>';
  // 3 pt (sz=24) top border, the desktop's block separator; [leftRule] is a
  // 2 pt edge in that colour, marking a ranked row.
  final top = topRule
      ? '<w:top w:val="single" w:sz="24" w:space="0" w:color="auto"/>'
      : '';
  final left = leftRule == null
      ? ''
      : '<w:left w:val="single" w:sz="16" w:space="0" w:color="$leftRule"/>';
  final borders = top.isEmpty && left.isEmpty
      ? ''
      : '<w:tcBorders>$top$left</w:tcBorders>';
  final w = widthTwips == null ? '' : '<w:tcW w:w="$widthTwips" w:type="dxa"/>';
  final merge = switch (vMerge) {
    DocxVMerge.none => '',
    DocxVMerge.start => '<w:vMerge w:val="restart"/>',
    DocxVMerge.rest => '<w:vMerge/>',
  };
  return '<w:tc><w:tcPr>$w$merge$borders$shd</w:tcPr>'
      '<w:p>${right ? '<w:pPr><w:jc w:val="right"/></w:pPr>' : ''}'
      '${docxRun(text, bold: bold, size: 16)}</w:p></w:tc>';
}

/// Split [contentTwips] across columns by [weights], the last column absorbing
/// the rounding remainder so the grid sums EXACTLY to the content width; Word
/// rescales the whole table if it does not.
List<int> docxGridWidths(List<double> weights, int contentTwips) {
  final sum = weights.fold<double>(0, (a, b) => a + b);
  final out = <int>[];
  var used = 0;
  for (var i = 0; i < weights.length; i++) {
    if (i == weights.length - 1) {
      out.add(contentTwips - used);
    } else {
      final w = (contentTwips * weights[i] / sum).round();
      out.add(w);
      used += w;
    }
  }
  return out;
}

/// `<w:tblGrid>` plus the fixed-layout declaration that makes it binding.
/// Closes `<w:tblPr>`, so callers write it straight after the borders.
String docxTblGrid(List<int> widths) =>
    '<w:tblLayout w:type="fixed"/></w:tblPr><w:tblGrid>'
    '${widths.map((w) => '<w:gridCol w:w="$w"/>').join()}</w:tblGrid>';

/// One table row. [rank] is a rank colour: every cell gets its light tint and
/// the first cell its full-colour left edge. [topRule] draws the 3 pt rule
/// the desktop uses to separate blocks.
String docxRow(
  List<String> cells, {
  bool header = false,
  int? rank,
  bool topRule = false,
  List<int> widths = const [],
  Map<int, DocxVMerge> vMerges = const {},
  Set<int> rightColumns = const {},
}) {
  final fill = header
      ? docxHex(kHeaderFill)
      : rank == null
      ? null
      : docxHex(rank);
  return '<w:tr>${cells.indexed.map((e) => docxCell(e.$2, bold: header, fill: fill, topRule: topRule, leftRule: rank != null && e.$1 == 0 ? docxHex(rank) : null, right: rightColumns.contains(e.$1), widthTwips: e.$1 < widths.length ? widths[e.$1] : null, vMerge: vMerges[e.$1] ?? DocxVMerge.none)).join()}</w:tr>';
}

/// A bordered table with a shaded header row, or none when [headers] is null.
/// [rowFills] (rank colours) and [rowRules] are keyed by data-row index. [lightInsideH] draws
/// the lines between rows thin and grey, leaving [rowRules] as the only heavy
/// horizontal rules.
String docxTable(
  List<String>? headers,
  List<List<String>> rows, {
  Map<int, int> rowFills = const {},
  Set<int> rowRules = const {},
  Set<int> mergeDownColumns = const {},
  Set<int> rightColumns = const {},
  bool lightInsideH = false,
  required List<double> weights,
  required int contentTwips,
}) {
  final widths = docxGridWidths(weights, contentTwips);
  final b = StringBuffer(
    '<w:tbl><w:tblPr><w:tblW w:w="$contentTwips" w:type="dxa"/>'
    '<w:tblBorders>',
  );
  for (final side in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
    final light = lightInsideH && side == 'insideH';
    b.write(
      '<w:$side w:val="single" w:sz="${light ? 2 : 4}" w:space="0" '
      'w:color="${light ? docxHex(kRuleColor) : 'auto'}"/>',
    );
  }
  b.write('</w:tblBorders>');
  b.write(docxTblGrid(widths));
  if (headers != null) {
    b.write(
      docxRow(
        headers,
        header: true,
        widths: widths,
        rightColumns: rightColumns,
      ),
    );
  }
  for (var i = 0; i < rows.length; i++) {
    // Merge a column downwards while column 0 (the block id, which must be
    // non-empty) is unchanged: a block's scales and notes are written on its
    // first lateral row only, and without the merge Word shows an empty cell
    // instead of one tall one.
    final continues =
        i > 0 && rows[i].first.isNotEmpty && rows[i].first == rows[i - 1].first;
    b.write(
      docxRow(
        rows[i],
        rank: rowFills[i],
        topRule: rowRules.contains(i),
        widths: widths,
        rightColumns: rightColumns,
        vMerges: {
          for (final c in mergeDownColumns)
            c: continues ? DocxVMerge.rest : DocxVMerge.start,
        },
      ),
    );
  }
  b.write('</w:tbl>');
  return b.toString();
}

const kDocxContentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    // The footer needs its own Override: a part that is present and related
    // but undeclared here is what draws a repair prompt.
    '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
    // Without docProps the title, author and dates are blank in Word's info
    // pane and in any system that indexes the file.
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    // A `w:pStyle` that resolves to nothing is ignored, so the styles part
    // must define the two heading styles the body references.
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '</Types>';

const kDocxPackageRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    '</Relationships>';

/// `word/styles.xml` defining the heading styles the body uses. Minimal on
/// purpose: `Heading1`/`Heading2` linked to Word's built-in outline levels,
/// which is what populates the navigation pane. More would fight the
/// consumer's template.
const kDocxStyles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles '
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:style w:type="paragraph" w:styleId="Heading1">'
    '<w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:outlineLvl w:val="0"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="26"/></w:rPr>'
    '</w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading2">'
    '<w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:outlineLvl w:val="1"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="20"/></w:rPr>'
    '</w:style>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
    '<w:name w:val="Normal"/>'
    '</w:style>'
    '</w:styles>';

/// English Metric Units per pixel at 96 dpi, the unit every OOXML drawing
/// extent is expressed in (1 inch = 914 400 EMU).
const int kEmuPerPx = 9525;

/// Page size for the Word report, in twentieths of a point (twips), with the
/// desktop's margins (0.5 in sides, 0.75 in top/bottom).
enum DocxPageSize {
  a4(11906, 16838),
  letter(12240, 15840);

  const DocxPageSize(this.widthTwips, this.heightTwips);

  final int widthTwips, heightTwips;

  static const _sideMarginTwips = 720; // 0.5 in
  static const _endMarginTwips = 1080; // 0.75 in

  /// Usable width in twips: what a fixed-layout table's columns must sum to.
  int get contentWidthTwips => widthTwips - 2 * _sideMarginTwips;

  /// Usable width in px at 96 dpi, for sizing embedded images.
  double get contentWidthPx => contentWidthTwips / 1440.0 * 96.0;

  /// The section properties, referencing [footerRelId] so every page carries
  /// the footer. Without a `<w:footerReference>` the footer part is inert.
  String sectPr(String footerRelId) =>
      '<w:sectPr>'
      '<w:footerReference w:type="default" r:id="$footerRelId"/>'
      '<w:pgSz w:w="$widthTwips" w:h="$heightTwips"/>'
      '<w:pgMar w:top="$_endMarginTwips" w:right="$_sideMarginTwips" '
      'w:bottom="$_endMarginTwips" w:left="$_sideMarginTwips" '
      'w:header="708" w:footer="708" w:gutter="0"/>'
      '</w:sectPr>';
}

/// Collects the images a document embeds and emits the OOXML they need: the
/// `word/media/*` parts, the `document.xml.rels` entries and the `<w:drawing>`
/// run for each placement. Word requires every one of a media part, a
/// relationship, a `png` content-type default, the `r`/`wp`/`a`/`pic`
/// namespaces on `<w:document>`, and matching `cx`/`cy` extents in both
/// `wp:extent` and `a:ext`.
class DocxMediaBag {
  final _bytes = <String, Uint8List>{};
  int _next = 1;

  /// rId -> (relationship type suffix, target). Images and the footer share
  /// one registry so `document.xml.rels` has a single writer.
  final _relTargets = <String, (String, String)>{};

  bool get isEmpty => _bytes.isEmpty;

  /// Register a non-image part and return its rId.
  String addRel(String typeSuffix, String target) {
    final id = 'rId${_next++}';
    _relTargets[id] = (typeSuffix, target);
    return id;
  }

  /// An inline image run, drawn [widthPx] wide with the PNG's own aspect ratio
  /// preserved (read from its IHDR, so nothing is stretched).
  String drawing(
    Uint8List png, {
    required double widthPx,
    String description = '',
  }) {
    final n = _next++;
    final id = 'rId$n';
    _bytes['image$n.png'] = png;
    _relTargets[id] = ('image', 'media/image$n.png');

    final size = pngSize(png);
    final aspect = size == null ? 1.0 : size.$2 / size.$1;
    final cx = (widthPx * kEmuPerPx).round();
    final cy = (widthPx * aspect * kEmuPerPx).round();
    final docPrId = n;
    return '<w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/>'
        // `descr` is the alt text: without it a screen reader announces only
        // "Picture 1", leaving the central figure unreadable non-visually.
        '<wp:docPr id="$docPrId" name="Picture $docPrId"'
        '${description.isEmpty ? '' : ' descr="${docxEsc(description)}"'}/>'
        '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
        '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:nvPicPr>'
        '<pic:cNvPr id="$docPrId" name="Picture $docPrId"/>'
        '<pic:cNvPicPr/>'
        '</pic:nvPicPr>'
        '<pic:blipFill>'
        '<a:blip r:embed="$id"/>'
        '<a:stretch><a:fillRect/></a:stretch>'
        '</pic:blipFill>'
        '<pic:spPr>'
        '<a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
        '</pic:spPr>'
        '</pic:pic>'
        '</a:graphicData>'
        '</a:graphic>'
        '</wp:inline>'
        '</w:drawing></w:r>';
  }

  /// `word/_rels/document.xml.rels`, or null when nothing was registered.
  String? get relsXml {
    if (_relTargets.isEmpty) return null;
    final b = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    );
    for (final e in _relTargets.entries) {
      b.write(
        '<Relationship Id="${e.key}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006'
        '/relationships/${e.value.$1}" '
        'Target="${e.value.$2}"/>',
      );
    }
    b.write('</Relationships>');
    return b.toString();
  }

  Map<String, Uint8List> get media => _bytes;
}

/// Read a PNG's pixel dimensions from its IHDR chunk, so an embedded image
/// keeps its aspect ratio instead of being stretched to a guessed box. Layout:
/// 8-byte signature, then IHDR data from byte 16, big-endian width and height.
(int, int)? pngSize(Uint8List bytes) {
  if (bytes.length < 24) return null;
  // Signature check, so a non-PNG can't be silently mis-sized.
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < sig.length; i++) {
    if (bytes[i] != sig[i]) return null;
  }
  int be32(int o) =>
      (bytes[o] << 24) |
      (bytes[o + 1] << 16) |
      (bytes[o + 2] << 8) |
      bytes[o + 3];
  final w = be32(16);
  final h = be32(20);
  if (w <= 0 || h <= 0) return null;
  return (w, h);
}

/// Assemble a complete .docx from a rendered `<w:body>` fragment.
///
/// [footerPrefix] is the text before the page numbers; `PAGE`/`NUMPAGES` field
/// codes are appended so Word recomputes them on reflow. [media] carries any
/// images the body referenced, so pass the same bag the drawings were built
/// from, or omit it for a text-only document.
Uint8List packDocx({
  required String body,
  required DocxPageSize pageSize,
  required String title,
  required String subject,
  required String footerPrefix,
  required String createdDate,
  DocxMediaBag? media,
}) {
  final bag = media ?? DocxMediaBag();
  final footerRelId = bag.addRel('footer', 'footer1.xml');
  bag.addRel('styles', 'styles.xml');

  final footer =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:ftr '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:p><w:pPr><w:jc w:val="center"/></w:pPr>'
      '${docxRun(footerPrefix, size: 16)}'
      '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
      '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
      '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
      '${docxRun(' of ', size: 16)}'
      '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
      '<w:r><w:instrText xml:space="preserve"> NUMPAGES </w:instrText></w:r>'
      '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
      '</w:p></w:ftr>';

  // The drawing namespaces are declared even with no image embedded: harmless
  // then, required the moment one appears, and one code path instead of two.
  final document =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<w:body>$body${pageSize.sectPr(footerRelId)}</w:body></w:document>';

  // docProps/core.xml: the Word twin of the PDF's /Info dictionary.
  final coreProps =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties '
      'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${docxEsc(title)}</dc:title>'
      '<dc:subject>${docxEsc(subject)}</dc:subject>'
      '<dc:creator>${docxEsc(kDocxCreator)}</dc:creator>'
      '<cp:lastModifiedBy>${docxEsc(kDocxCreator)}</cp:lastModifiedBy>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">'
      '${createdDate}T00:00:00Z</dcterms:created>'
      '</cp:coreProperties>';

  final archive = Archive()
    ..addFile(
      ArchiveFile.bytes('[Content_Types].xml', utf8.encode(kDocxContentTypes)),
    )
    ..addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode(kDocxPackageRels)))
    ..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(document)))
    ..addFile(ArchiveFile.bytes('word/footer1.xml', utf8.encode(footer)))
    ..addFile(ArchiveFile.bytes('docProps/core.xml', utf8.encode(coreProps)))
    ..addFile(ArchiveFile.bytes('word/styles.xml', utf8.encode(kDocxStyles)));

  // One rels part for the footer, the styles and any images. Never null: the
  // footer always registers a relationship.
  final rels = bag.relsXml;
  if (rels != null) {
    archive.addFile(
      ArchiveFile.bytes('word/_rels/document.xml.rels', utf8.encode(rels)),
    );
  }
  for (final e in bag.media.entries) {
    archive.addFile(ArchiveFile.bytes('word/media/${e.key}', e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Who the documents say made them, version included. Set once so the PDF's
/// /Info and the docx's docProps cannot drift apart.
const kDocxCreator = '$appName v$appVersion';
