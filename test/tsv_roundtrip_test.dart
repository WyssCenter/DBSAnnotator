import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/bids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('annotations TSV', () {
    test('round-trips, preserving embedded newlines in notes', () {
      final items = <Annotation>[
        const Annotation(acqTime: '2026-07-24T10:00:00', notes: 'first note'),
        const Annotation(
          acqTime: '2026-07-24T10:05:00',
          notes: 'multi\nline note with a\ttab',
        ),
      ];

      final tsv = writeAnnotations(items);
      final parsed = parseAnnotations(tsv);

      expect(parsed.length, 2);
      expect(parsed[0].acqTime, startsWith('2026-07-24T'));
      expect(parsed[1].notes, 'multi\nline note with a\ttab');
    });

    test('header is the canonical column order', () {
      final tsv = writeAnnotations(const []);
      expect(tsv.trimRight(), 'acq_time\tnotes');
    });

    test('an empty cell is written as n/a and read back as empty', () {
      // BIDS: "Missing and non-applicable values MUST be coded as n/a", and a
      // blank cell is not allowed. The marker must not leak into the UI, so the
      // reader has to undo it.
      final tsv = writeAnnotations(const [
        Annotation(acqTime: '2026-07-24T10:00:00+02:00', notes: ''),
      ]);
      expect(tsv, contains('\tn/a'));
      expect(parseAnnotations(tsv).single.notes, '');
    });

    test('is written with LF, and CRLF is still read', () {
      final tsv = writeAnnotations(const [
        Annotation(acqTime: '2026-07-24T10:00:00+02:00', notes: 'a note'),
      ]);
      expect(tsv, isNot(contains('\r')));
      expect(
        parseAnnotations(tsv.replaceAll('\n', '\r\n')).single.notes,
        'a note',
      );
    });
  });

  group('BIDS', () {
    test('builds and parses the beh filename', () {
      const name = BidsName(
        subject: '01',
        session: '20260724',
        task: 'notes',
        run: '01',
      );
      // `_beh`, not `_events`: the spec reserves the latter for files with
      // onset/duration columns. See lib/core/bids.dart.
      expect(name.filename, 'sub-01_ses-20260724_task-notes_run-01_beh.tsv');
      expect(
        name.sidecarFilename,
        'sub-01_ses-20260724_task-notes_run-01_beh.json',
      );
      expect(name.relativeDir, 'sub-01/ses-20260724/beh');

      final parsed = BidsName.parse(name.filename)!;
      expect(parsed.subject, '01');
      expect(parsed.task, 'notes');
      expect(parsed.run, '01');
    });

    test('acq sits between task and run, and only when filled in', () {
      const name = BidsName(
        subject: '01',
        session: '20260724',
        task: 'programming',
        run: '01',
        acquisition: 'med-on',
      );
      expect(
        name.filename,
        'sub-01_ses-20260724_task-programming_acq-medon_run-01_beh.tsv',
      );
      expect(BidsName.parse(name.filename)!.acquisition, 'medon');
      expect(name.withSuffix('report').filename, contains('_acq-medon_'));
    });

    test('still parses a pre-0.5.0 _events name, and says so', () {
      final parsed = BidsName.parse(
        'sub-P07_ses-20250101_task-programming_run-02_events.tsv',
      )!;
      expect(parsed.subject, 'P07');
      expect(parsed.run, '02');
      expect(parsed.suffix, BidsName.legacySuffix);
    });

    test('run is an index: zero-padded, and write agrees with parse', () {
      // `label()` would happily emit `run-pre`, which `parse` reads back as
      // `01` because its pattern is digits-only: a silent round-trip loss.
      expect(BidsName.index('1'), '01');
      expect(BidsName.index('7'), '07');
      expect(BidsName.index('12'), '12');
      expect(BidsName.index('pre'), '01');
      expect(BidsName.index(''), '01');

      const name = BidsName(
        subject: '01',
        session: '20260724',
        task: 'programming',
        run: '3',
      );
      expect(name.filename, contains('_run-03_'));
      expect(BidsName.parse(name.filename)!.run, '03');
    });

    test('a report is a derivative, named from the same entities', () {
      const name = BidsName(
        subject: '01',
        session: '20260724',
        task: 'programming',
        run: '01',
      );
      expect(
        name.withSuffix('report', extension: 'pdf').filename,
        'sub-01_ses-20260724_task-programming_run-01_report.pdf',
      );
    });
  });
}
