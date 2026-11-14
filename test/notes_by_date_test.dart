/// Notes from an accompanying file are placed by their DATE as well as their
/// time: a note from another day interleaved by clock time would be reported
/// as part of a visit it did not happen in.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/core/session/tsv_kind.dart';
import 'package:dbs_annotator/report/longitudinal_data.dart';
import 'package:dbs_annotator/report/longitudinal_pdf.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/session_docx.dart';
import 'package:dbs_annotator/report/upload_actions.dart';
import 'package:flutter_test/flutter_test.dart';

final _fixture = File(
  'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv',
).readAsStringSync();

final _rows = parseSessionTsv(_fixture);

/// The fixture's rows moved to [day], keeping their clock times.
List<SessionRow> _on(String day) =>
    parseSessionTsv(_fixture.replaceAll('2026-02-03', day));

Annotation _note(String at, String text) =>
    Annotation(acqTime: at, notes: text);

bool _inTable(SessionReportData d, String text) =>
    d.tableData.any((r) => r.last == text);

void main() {
  group('single session report', () {
    final data = buildSessionReportData(
      rows: _rows,
      notes: [
        _note('2026-02-03T09:06:00+00:00', 'same day'),
        _note('2026-03-10T09:06:00+00:00', 'later visit'),
        _note('2026-01-20T14:00:00+00:00', 'earlier call'),
      ],
    );

    test('a note from the session day stays in the session table', () {
      expect(_inTable(data, 'same day'), isTrue);
    });

    test('notes from other days stay out of the session table', () {
      expect(_inTable(data, 'later visit'), isFalse);
      expect(_inTable(data, 'earlier call'), isFalse);
    });

    test('the Word notes table carries its heading and full dates', () {
      final xml = datedNotesDocx(
        'Notes on days without a session',
        datedNotes([_note('2026-03-10T09:06:00+00:00', 'later visit')]),
        contentTwips: 9000,
      );
      expect(xml, contains('Notes on days without a session'));
      expect(xml, contains('2026-03-10'));
      expect(
        datedNotesDocx('x', const [], contentTwips: 9000),
        isEmpty,
        reason: 'no heading over nothing',
      );
    });
  });

  test('notes naming another patient keep the longitudinal report off', () {
    Uploaded file(String name, TsvKind kind) => (
      name: name,
      kind: kind,
      rows: kind == TsvKind.programming ? _rows : const [],
      notes: kind == TsvKind.notes
          ? [_note('2026-02-03T09:06:00+00:00', 'n')]
          : const [],
    );
    final files = [
      file(
        'sub-01_ses-20260203_task-programming_run-01_beh.tsv',
        TsvKind.programming,
      ),
      file('sub-02_ses-20260203_task-notes_run-01_beh.tsv', TsvKind.notes),
    ];
    expect(
      unavailableReason(ReportAction.longitudinalReport, files),
      'These files name different patients.',
    );
  });

  test('notes alone: every note listed by date, the patient named', () async {
    const notesFile = 'sub-07_ses-20260203_task-notes_run-01_beh.tsv';
    final data = buildLongitudinalReportData(
      files: const {},
      notes: [
        _note('2026-03-10T09:06:00+00:00', 'second'),
        _note('2026-02-03T09:06:00+00:00', 'first'),
      ],
      noteFilenames: const [notesFile],
    );
    expect(data.isEmpty, isTrue);
    expect(data.patientId, '07');
    expect(data.notesWithoutVisit.map((n) => n.text), ['first', 'second']);
    final pdf = await buildLongitudinalPdf(data: data);
    expect(pdf.bytes.sublist(0, 4), '%PDF'.codeUnits);
    final doc = utf8.decode(
      ZipDecoder()
          .decodeBytes(buildLongitudinalDocx(data: data))
          .findFile('word/document.xml')!
          .readBytes()!,
    );
    expect(doc, contains('No session file was imported.'));
    expect(doc, contains('second'));
  });

  group('longitudinal report', () {
    const first = 'sub-01_ses-20260203_task-programming_run-01_beh.tsv';
    const second = 'sub-01_ses-20260310_task-programming_run-01_beh.tsv';
    final data = buildLongitudinalReportData(
      files: {first: _rows, second: _on('2026-03-10')},
      notes: [
        _note('2026-02-03T09:06:00+00:00', 'first visit'),
        _note('2026-03-10T09:06:00+00:00', 'second visit'),
        _note('2026-02-20T11:00:00+00:00', 'phone call'),
      ],
    );
    SessionReportData visit(String f) =>
        data.visits.firstWhere((v) => v.filename == f).session;

    test('each note joins the visit of its own day only', () {
      expect(_inTable(visit(first), 'first visit'), isTrue);
      expect(_inTable(visit(first), 'second visit'), isFalse);
      expect(_inTable(visit(second), 'second visit'), isTrue);
    });

    test('a day with notes and no session is a Visits row of its own', () {
      expect(
        [for (final r in data.visitTable) r[1]],
        ['2026-02-03', '2026-02-20', '2026-03-10'],
      );
      expect([for (final r in data.visitTable) r[0]], ['1', '2', '3']);
      expect(data.visitTable[1].skip(2), everyElement(isEmpty));
    });

    test('that day gets its own session-data table, in date order', () {
      final day = data.timeline[1].noteDay!;
      expect(data.timeline[0].visit?.filename, first);
      expect(data.timeline[2].visit?.filename, second);
      expect(day.date, '2026-02-20');
      final headers = data.visits.first.session.tableHeaders;
      final row = day.rows.single;
      expect(row, hasLength(headers.length));
      expect(row[headers.indexOf('Time')], isNotEmpty);
      expect(row.last, 'phone call');
      for (final v in data.visits) {
        expect(_inTable(v.session, 'phone call'), isFalse);
      }
    });

    test('Source files names every upload, notes included', () async {
      const notesFile = 'sub-01_ses-20260220_task-notes_run-01_beh.tsv';
      final withFile = buildLongitudinalReportData(
        files: {first: _rows, second: _on('2026-03-10')},
        notes: [_note('2026-02-20T11:00:00+00:00', 'phone call')],
        noteFilenames: const [notesFile],
      );
      final doc = utf8.decode(
        ZipDecoder()
            .decodeBytes(buildLongitudinalDocx(data: withFile))
            .findFile('word/document.xml')!
            .readBytes()!,
      );
      expect(doc, contains(first));
      expect(doc, contains('$notesFile  (notes)'));
      expect(doc, isNot(contains('Notes on days without a session')));
      // Visits sits between the two figures' headings.
      final clinical = doc.indexOf('Clinical scales by visit');
      final visits = doc.indexOf('Visits</w:t>');
      final session = doc.indexOf(
        'Symptom and side effect ratings by visit and configuration',
      );
      expect(clinical < visits && visits < session, isTrue);
    });

    test('two sessions on one day: a note goes to the one under way', () {
      const morning = 'sub-01_ses-20260203_task-programming_run-01_beh.tsv';
      const afternoon = 'sub-01_ses-20260203_task-programming_run-02_beh.tsv';
      final pm = [
        for (final r in _rows)
          SessionRow.fromMap({
            ...r.toMap(),
            'acq_time': r.acqTime.replaceFirst('T09:', 'T15:'),
          }),
      ];
      final both = buildLongitudinalReportData(
        files: {morning: _rows, afternoon: pm},
        notes: [_note('2026-02-03T15:10:00+00:00', 'afternoon note')],
      );
      SessionReportData of(String f) =>
          both.visits.firstWhere((v) => v.filename == f).session;
      expect(_inTable(of(afternoon), 'afternoon note'), isTrue);
      expect(_inTable(of(morning), 'afternoon note'), isFalse);
    });
  });
}
