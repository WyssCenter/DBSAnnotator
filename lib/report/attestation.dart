/// The attestation block that closes every report: who recorded the session
/// and, where scales were rated, who rated them. The names are typed at export
/// and never written to a TSV; a name left empty prints as a line to sign on.
library;

import 'package:pdf/widgets.dart' as pw;

import 'docx_ooxml.dart';
import 'report_palette.dart';
import 'report_text.dart';

/// The names typed at export. Either may be empty.
typedef ReportAttestation = ({String recordedBy, String ratedBy});

const ReportAttestation kNoAttestation = (recordedBy: '', ratedBy: '');

/// The fields a report prints: "Rated by" only where scales were rated.
List<(String, String)> attestationFields(
  ReportAttestation a, {
  required bool rated,
}) => [
  ('Documented by', a.recordedBy.trim()),
  if (rated) ('Rated by', a.ratedBy.trim()),
];

/// The block as PDF widgets: each name over a rule, its label under it.
List<pw.Widget> attestationPdf(
  List<(String, String)> fields,
  ReportTextSanitiser t,
) => [
  pw.SizedBox(height: 18),
  pw.Text(
    'Attestation',
    style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
  ),
  pw.SizedBox(height: 10),
  pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      for (final (label, name) in fields)
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  height: 14,
                  child: name.isEmpty ? null : pw.Text(t(name)),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.only(top: 2),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      top: pw.BorderSide(color: pdfInk, width: 0.8),
                    ),
                  ),
                  child: pw.Text(
                    label,
                    style: const pw.TextStyle(fontSize: 8, color: pdfInk),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  ),
];

/// The block as Word paragraphs. Underscores rather than a border, so an
/// empty field survives a copy-paste elsewhere.
String attestationDocx(List<(String, String)> fields) =>
    docxHeading2('Attestation') +
    docxPara(
      [
        for (final (label, name) in fields)
          '$label: ${name.isEmpty ? '_' * 26 : name}',
      ].join('    '),
    );
