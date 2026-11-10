/// A note too tall for a table cell must not stop the PDF from building, and
/// its full text must still reach the document.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/longitudinal_data.dart';
import 'package:dbs_annotator/report/longitudinal_pdf.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/report_text.dart';
import 'package:dbs_annotator/report/session_pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

final _fixture = File(
  'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv',
).readAsStringSync();

final _rows = parseSessionTsv(_fixture);

const _file = 'sub-01_ses-20260203_task-programming_run-01_beh.tsv';

String _longNote(String tail) =>
    '${List.generate(400, (i) => 'line $i ${'x' * 40}').join('\n')}\n$tail';

List<String> _texts(List<pw.Widget> widgets) => [
  for (final w in widgets)
    if (w is pw.RichText) (w.text as pw.TextSpan).text ?? '',
];

int _pages(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length;

void _expectPdf(Uint8List bytes) =>
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');

void _expectFullNoteAdded(Uint8List short, Uint8List long) {
  _expectPdf(long);
  expect(_pages(long), greaterThan(_pages(short) + 4));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a short note passes through a cell untouched', () {
    final long = LongNotes();
    expect(long.cell('ok\nfine', 'x', kNarrowNoteBudget), 'ok\nfine');
    expect(long.section(ReportTextSanitiser()), isEmpty);
  });

  test('a long note is clipped in the cell and kept whole for the section', () {
    final long = LongNotes();
    final note = _longNote('LASTWORD');
    final cell = long.cell(note, 'Block 1', kNarrowNoteBudget);
    expect(cell.length, lessThan(400));
    expect(cell, endsWith('(full note below)'));
    expect(cell, startsWith('line 0 '));
    expect(long.section(ReportTextSanitiser()), isNotEmpty);
  });

  test('the section prints the whole note under its label', () {
    final long = LongNotes();
    final note = _longNote('LASTWORD');
    long.cell(note, 'Block 1, 09:06:00', kNarrowNoteBudget);
    final texts = _texts(long.section(ReportTextSanitiser()));
    expect(texts, contains(note));
    expect(texts, contains('Block 1, 09:06:00'));
  });

  test('dated notes keep the full text beside a clipped cell', () {
    final note = _longNote('DATEDEND');
    final widgets = datedNotesPdf('Notes', [
      (date: '2026-03-10', time: '09:06', text: note),
    ], ReportTextSanitiser());
    expect(_texts(widgets), contains(note));
  });

  test('session report builds with a 400-line note', () async {
    final data = buildSessionReportData(
      rows: _rows,
      notes: [
        Annotation(
          acqTime: '2026-02-03T09:06:00+00:00',
          notes: _longNote('SESSIONEND'),
        ),
      ],
    );
    final pdf = await buildSessionPdf(data: data, subjectId: '01');
    final shortPdf = await buildSessionPdf(
      data: buildSessionReportData(
        rows: _rows,
        notes: const [
          Annotation(acqTime: '2026-02-03T09:06:00+00:00', notes: 'short'),
        ],
      ),
      subjectId: '01',
    );
    _expectFullNoteAdded(shortPdf.bytes, pdf.bytes);
  });

  test('block note of 1500 characters in the narrow column builds', () async {
    final text = List.filled(300, 'abcd').join(' ');
    final rows = [
      for (final (i, id) in ['1', '2', '3'].indexed)
        SessionRow(
          acqTime: '2026-07-29T09:${30 + i * 10}:00',
          blockId: id,
          appendId: '1',
          isInitial: '0',
          scaleName: 'Tremor',
          scaleValue: '2',
          programId: 'A',
          leftStimFreq: '130',
          leftAnode: 'C',
          leftCathode: '1',
          leftAmplitude: '1',
          leftPulseWidth: '60',
          notes: id == '2' ? '$text BLOCKEND' : 'short',
        ),
    ];
    final pdf = await buildSessionPdf(
      data: buildSessionReportData(rows: rows),
      subjectId: '01',
    );
    _expectPdf(pdf.bytes);

    final long = LongNotes();
    long.cell('$text BLOCKEND', 'Block 2', kNarrowNoteBudget);
    expect(
      _texts(long.section(ReportTextSanitiser())),
      contains(endsWith('BLOCKEND')),
    );
  });

  test('longitudinal report builds with a long note', () async {
    final data = buildLongitudinalReportData(
      files: {_file: _rows},
      notes: [
        Annotation(
          acqTime: '2026-02-03T09:06:00+00:00',
          notes: _longNote('VISITEND'),
        ),
      ],
    );
    final pdf = await buildLongitudinalPdf(data: data);
    final shortPdf = await buildLongitudinalPdf(
      data: buildLongitudinalReportData(
        files: {_file: _rows},
        notes: const [
          Annotation(acqTime: '2026-02-03T09:06:00+00:00', notes: 'short'),
        ],
      ),
    );
    _expectFullNoteAdded(shortPdf.bytes, pdf.bytes);
  });

  test('longitudinal notes without a visit build', () async {
    final data = buildLongitudinalReportData(
      files: const {},
      notes: [
        Annotation(
          acqTime: '2026-03-10T09:06:00+00:00',
          notes: _longNote('UNPLACEDEND'),
        ),
      ],
      noteFilenames: const ['sub-07_ses-20260203_task-notes_run-01_beh.tsv'],
    );
    final pdf = await buildLongitudinalPdf(data: data);
    final shortPdf = await buildLongitudinalPdf(
      data: buildLongitudinalReportData(
        files: const {},
        notes: const [
          Annotation(acqTime: '2026-03-10T09:06:00+00:00', notes: 'short'),
        ],
        noteFilenames: const ['sub-07_ses-20260203_task-notes_run-01_beh.tsv'],
      ),
    );
    _expectFullNoteAdded(shortPdf.bytes, pdf.bytes);
  });

  test('trailing blank lines do not clip a note', () {
    final long = LongNotes();
    final note = 'fits\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n';
    expect(long.cell(note, 'x', kNarrowNoteBudget), note);
    expect(long.section(ReportTextSanitiser()), isEmpty);
  });

  test('a clipped time cell labels its note with date and time', () {
    final long = LongNotes();
    long.cell(_longNote('X'), 'unused', kNarrowNoteBudget);
    final rows = long.rows([
      ['2', '2026-07-30\n00:30:00\n(1h later)', 'L', _longNote('Y')],
    ]);
    expect(rows.single.last, endsWith('(full note below)'));
    expect(
      _texts(long.section(ReportTextSanitiser())),
      contains('Block 2, 2026-07-30 00:30:00'),
    );
  });
}
