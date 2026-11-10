/// The clinician-marked final block, a lead model per side, clinical scale
/// ranges and the export-time attestation: what each writes, what older files
/// read as, and what the reports then say.
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/core/prefs/user_prefs.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/core/session/tsv_kind.dart';
import 'package:dbs_annotator/report/longitudinal_data.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/session_docx.dart';
import 'package:dbs_annotator/report/upload_actions.dart';
import 'package:dbs_annotator/ui/import_export_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SessionAuthoring _session() {
  final a = SessionAuthoring();
  for (final amp in ['2.0', '3.0']) {
    a.addInsert(
      isInitial: false,
      stim: {'left_amplitude': amp, 'left_cathode': 'E1', 'left_anode': 'case'},
      scales: const [(name: 'Mood', value: '5')],
      leftElectrodeModel: 'Medtronic SenSight B33005',
      rightElectrodeModel: 'Boston Scientific Vercise Cartesia X',
      at: DateTime.utc(2026, 2, 3, 9, amp == '2.0' ? 0 : 5),
    );
  }
  return a;
}

String _docx(List<int> bytes) => utf8.decode(
  ZipDecoder().decodeBytes(bytes).findFile('word/document.xml')!.readBytes()!,
);

void main() {
  group('the block the patient leaves on', () {
    test('is unmarked until the clinician marks it, then round-trips', () {
      final a = _session();
      expect(finalBlockIn(a.rows), isNull);
      expect(a.rows.every((r) => r.isFinal == '0'), isTrue);

      a.markFinalBlock('0');
      final back = parseSessionTsv(a.serialize());
      expect(finalBlockIn(back), '0');
      expect(back.where((r) => r.isFinal == '1').length, 1);

      a.markFinalBlock(null);
      expect(finalBlockIn(a.rows), isNull);
    });

    test('a marked block is the final configuration, and says so', () {
      final a = _session()..markFinalBlock('0');
      final marked = buildSessionReportData(rows: a.rows);
      expect(marked.finalConfigTitle, kLeftOnTitle);
      expect(marked.lastConfig['Left'], contains('2 mA'));

      final unmarked = buildSessionReportData(rows: _session().rows);
      expect(unmarked.finalConfigTitle, kLastRecordedTitle);
      expect(unmarked.lastConfig['Left'], contains('3 mA'));
    });
  });

  group('a lead model per side', () {
    test('each side keeps its own model', () {
      final rows = parseSessionTsv(_session().serialize());
      expect(electrodeModelIn(rows), 'Medtronic SenSight B33005');
      expect(
        electrodeModelIn(rows, right: true),
        'Boston Scientific Vercise Cartesia X',
      );
      expect(
        buildSessionReportData(rows: rows).electrodeModel,
        'left Medtronic SenSight B33005, '
        'right Boston Scientific Vercise Cartesia X',
      );
    });

    test('an older file with one electrode_model reads it as both', () {
      const tsv =
          'acq_time\tblock_id\tis_initial\telectrode_model\n'
          '2026-02-03T09:00:00+00:00\t1\t0\tMedtronic SenSight B33005\n';
      final rows = parseSessionTsv(tsv);
      expect(rows.single.leftElectrodeModel, 'Medtronic SenSight B33005');
      expect(rows.single.rightElectrodeModel, 'Medtronic SenSight B33005');
      expect(rows.single.isFinal, isEmpty);
      expect(finalBlockIn(rows), isNull);
    });
  });

  group('clinical scale ranges', () {
    test('an older contract without ranges still parses', () {
      final p = ScalePresets.fromJson({
        'buttons': ['OCD'],
        'clinical': {
          'OCD': ['Y-BOCS'],
        },
        'session': <String, dynamic>{},
      });
      expect(p.clinicalRanges, isEmpty);
    });

    test('only complete, ordered ranges reach the chart', () {
      expect(
        numericRanges({
          'Y-BOCS': (min: '0', max: '40'),
          'HAM-D': (min: '', max: ''),
          'Odd': (min: '10', max: '2'),
        }),
        {'Y-BOCS': (0.0, 40.0)},
      );
    });

    test('saved ranges replace the bundled ones, a cleared range included', () {
      const base = ScalePresets(
        buttons: ['OCD'],
        clinical: {
          'OCD': ['Y-BOCS', 'MADRS'],
        },
        session: {},
        clinicalRanges: {
          'Y-BOCS': (min: '0', max: '40'),
          'MADRS': (min: '0', max: '60'),
        },
      );
      final prefs = UserPrefs.fromJson(
        UserPrefs(
          clinicalRanges: {
            'Y-BOCS': ['0', '40'],
          },
        ).toJson(),
      );
      expect(mergeScalePresets(base, prefs).clinicalRanges.keys, ['Y-BOCS']);
      expect(mergeScalePresets(base, UserPrefs()).clinicalRanges, hasLength(2));
    });

    test('a range widens the clinical axis to the scale', () {
      SessionRow baseline(String day, String v) => SessionRow(
        acqTime: '${day}T09:00:00+00:00',
        blockId: '0',
        isInitial: '1',
        scaleName: 'Y-BOCS',
        scaleValue: v,
      );
      final files = {
        'sub-01_ses-a_task-programming_run-01_beh.tsv': [
          baseline('2026-01-01', '28'),
        ],
        'sub-01_ses-b_task-programming_run-01_beh.tsv': [
          baseline('2026-06-01', '20'),
        ],
      };
      expect(buildLongitudinalReportData(files: files).clinicalChart.yMax, 28);
      expect(
        buildLongitudinalReportData(
          files: files,
          clinicalRanges: const {'Y-BOCS': (0, 40)},
        ).clinicalChart.yMax,
        40,
      );
    });
  });

  group('attestation', () {
    test('the names typed at export are printed; an empty one is a line', () {
      final data = buildSessionReportData(rows: _session().rows);
      final named = _docx(
        buildSessionDocx(
          data: data,
          subjectId: '01',
          attestation: (recordedBy: 'J. Doe', ratedBy: ''),
        ),
      );
      expect(named, contains('Recorded by: J. Doe'));
      expect(named, contains('Rated by: ${'_' * 26}'));
      expect(named, isNot(contains('Reviewed by')));
      expect(named, isNot(contains('Date: _')));
    });
  });

  testWidgets('with a notes file imported, the per-visit tables start ticked', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = _session();
    final files = <Uploaded>[
      (
        name: 'sub-01_ses-20260203_task-programming_run-01_beh.tsv',
        kind: TsvKind.programming,
        rows: session.rows,
        notes: const <Annotation>[],
      ),
      (
        name: 'sub-01_ses-20260203_task-notes_run-01_beh.tsv',
        kind: TsvKind.notes,
        rows: const <SessionRow>[],
        notes: const [
          Annotation(acqTime: '2026-02-03T09:02:00+00:00', notes: 'n'),
        ],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ImportExportPanel(initialFiles: files),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('PDF').at(1));
    await tester.pumpAndSettle();
    final tile = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Combined session data table'),
    );
    expect(tile.value, isTrue);
  });
}
