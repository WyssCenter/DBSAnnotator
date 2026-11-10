// Regression cover for how the screen wires the report builders, the seams
// where correct components were being combined incorrectly: the report was
// built from a second, independently-computed data object (so an export at
// midnight could print two dates); the Step-2 scale bounds never reached the
// chart, so the axis and the ranking silently used a 0..10 default; and the
// sanitiser's "characters were replaced" flag had nowhere to go.
import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/session_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_ranking_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rows = [
    SessionRow(
      blockId: '1',
      isInitial: '0',
      scaleName: 'Tremor',
      scaleValue: '20',
    ),
    SessionRow(
      blockId: '2',
      isInitial: '0',
      scaleName: 'Tremor',
      scaleValue: '80',
    ),
  ];

  test('a single data object means one clock read for the whole document', () {
    final data = buildSessionReportData(rows: rows);
    // Same object drives both builders, so the date cannot differ between them.
    expect(data.generatedOn, isNotEmpty);
    final again = buildSessionReportData(rows: rows);
    expect(
      data.generatedOn,
      again.generatedOn,
      reason: 'sanity: same-day builds agree',
    );
  });

  test(
    'user scale bounds reach the chart y-axis (0..100, not the 0..10 default)',
    () {
      final withPrefs = buildSessionReportData(
        rows: rows,
        scalePrefs: const [
          (
            name: 'Tremor',
            min: 0.0,
            max: 100.0,
            mode: ScaleMode.min,
            custom: null,
          ),
        ],
      );
      expect(
        withPrefs.chart.yMax,
        100,
        reason: 'Step-2 max must clamp the axis; it was ignored before',
      );

      final defaulted = rankedReportData(rows);
      expect(
        defaulted.chart.yMax,
        80,
        reason: 'the 0..10 fallback widens to include the recorded 80',
      );
    },
  );

  test('buildSessionPdf reports whether characters were lost', () async {
    final clean = await buildSessionPdf(
      data: buildSessionReportData(rows: rows),
      subjectId: '01',
    );
    expect(clean.lostCharacters, isFalse);

    // A CJK note cannot be encoded by the Latin-1 fallback font.
    final lossy = await buildSessionPdf(
      data: buildSessionReportData(
        rows: const [
          SessionRow(
            blockId: '1',
            isInitial: '0',
            notes: '注意 transient warmth',
          ),
        ],
      ),
      subjectId: '01',
    );
    expect(
      lossy.lostCharacters,
      isTrue,
      reason: 'the flag must surface so the UI can warn',
    );
    expect(lossy.bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
  });
}
