/// Default scale targets for tests that need a ranked report.
library;

import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/report/report_data.dart';

SessionReportData rankedReportData(
  List<SessionRow> rows, {
  DateTime? generatedAt,
}) => buildSessionReportData(
  rows: rows,
  generatedAt: generatedAt,
  // Recording rows only: the baseline block's clinical scales are not session
  // scales, and listing them as targets put them in the legend.
  scalePrefs: defaultScalePrefsFor(
    rows.where((r) => coerceInt(r.isInitial) != 1),
    fallback: (0.0, 4.0),
  ),
);
