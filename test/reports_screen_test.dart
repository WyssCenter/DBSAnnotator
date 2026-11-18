import 'dart:io';

import 'package:dbs_annotator/core/annotation.dart';
import 'package:dbs_annotator/report/upload_actions.dart';
import 'package:dbs_annotator/ui/import_export_panel.dart';
import 'package:dbs_annotator/ui/scales_chart_painter.dart';
import 'package:dbs_annotator/ui/session/entries_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(ImportExportPanel panel, {Key? key}) => MaterialApp(
  key: key,
  home: Scaffold(body: SingleChildScrollView(child: panel)),
);

void main() {
  testWidgets('with no patient chosen, the actions wait for a visit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(const ImportExportPanel(folder: 'C:/Studies/OCD-DBS')),
    );
    await tester.pump();

    expect(find.text('Choose a patient to see their visits.'), findsOneWidget);
    expect(find.text('Single session report'), findsNothing);

    await tester.pumpWidget(_host(const ImportExportPanel()));
    await tester.pump();
    expect(
      find.text('Choose a BIDS folder above to see its visits.'),
      findsOneWidget,
    );
  });

  testWidgets('every action explains itself once a session is imported', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const name = 'sub-01_ses-20260203_task-programming_run-01_beh.tsv';
    final upload = classifyUpload(
      name,
      File('test/fixtures/$name').readAsStringSync(),
    ).file!;
    await tester.pumpWidget(_host(ImportExportPanel(initialFiles: [upload])));
    await tester.pump();
    for (final label in const [
      'Single session report',
      'Report across visits',
      'Combined table (TSV)',
      'BIDS folder (zip)',
      'Add to a BIDS folder',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }

    expect(find.byTooltip('About this export'), findsNWidgets(5));
    await tester.tap(find.byTooltip('About this export').first);
    await tester.pumpAndSettle();
    for (final heading in const [
      'How it is exported',
      'What it needs',
      'What it creates',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
    expect(find.text(ReportAction.sessionReport.needs), findsOneWidget);
  });

  testWidgets('one session: the preview shows its table, and adding to a BIDS '
      'folder files only the session unless the report is ticked', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const name = 'sub-01_ses-20260203_task-programming_run-01_beh.tsv';
    final upload = classifyUpload(
      name,
      File('test/fixtures/$name').readAsStringSync(),
    ).file!;
    await tester.pumpWidget(_host(ImportExportPanel(initialFiles: [upload])));
    await tester.pump();

    expect(find.byType(SessionEntriesTable), findsOneWidget);

    final add = find.widgetWithText(OutlinedButton, 'Add to a BIDS folder');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final boxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .map((b) => b.value)
        .toList();
    expect(boxes, [true, false]);
    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );
    expect(inDialog('PDF'), findsNothing, reason: 'no format without report');
    await tester.tap(inDialog('Report'));
    await tester.pumpAndSettle();
    expect(inDialog('PDF'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('a notes file alone has no single session report', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final notes = classifyUpload(
      'sub-01_ses-20260203_task-notes_run-01_beh.tsv',
      writeAnnotations([
        const Annotation(
          acqTime: '2026-02-03T09:00:00+00:00',
          notes: 'planted note',
        ),
      ]),
    );
    expect(notes.file, isNotNull, reason: '${notes.rejected}');
    await tester.pumpWidget(
      _host(ImportExportPanel(initialFiles: [notes.file!])),
    );
    await tester.pump();

    expect(
      find.text(
        'A notes file from an earlier version has no report of its own.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'several sessions: one patient is charted, two patients are not',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final tsv = File(
        'test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv',
      ).readAsStringSync();
      Uploaded upload(String sub, String ses) => classifyUpload(
        'sub-${sub}_ses-${ses}_task-programming_run-01_beh.tsv',
        tsv,
      ).file!;
      bool charted() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .any((p) => p.painter is ScalesChartPainter);

      await tester.pumpWidget(
        _host(
          ImportExportPanel(
            initialFiles: [upload('01', '20260203'), upload('01', '20260310')],
          ),
        ),
      );
      await tester.pump();
      expect(charted(), isTrue);
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<ScalesChartPainter>()
          .toList();
      expect(painters, hasLength(2));
      expect(find.text('Clinical scales by visit'), findsOneWidget);
      expect(painters.first.spec.series, isNotEmpty);
      expect(painters.last.spec.bestXs, isNotEmpty);

      await tester.pumpWidget(
        _host(
          key: UniqueKey(),
          ImportExportPanel(
            initialFiles: [upload('01', '20260203'), upload('02', '20260310')],
          ),
        ),
      );
      await tester.pump();
      expect(charted(), isFalse);
      expect(
        find.text('No chart is drawn across different patients.'),
        findsOneWidget,
      );
    },
  );

  _enlargeAndZoom();
}

Uploaded _visit(String ses) => classifyUpload(
  'sub-01_ses-${ses}_task-programming_run-01_beh.tsv',
  File('test/fixtures/sub-01_ses-20260203_task-programming_run-01_beh.tsv')
      .readAsStringSync(),
).file!;

void _enlargeAndZoom() {
  testWidgets('zoom widens a figure across visits, and narrows it back', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        ImportExportPanel(
          initialFiles: [_visit('20260203'), _visit('20260310')],
        ),
      ),
    );
    await tester.pump();
    double width() => tester
        .getSize(
          find
              .ancestor(
                of: find.byType(CustomPaint).last,
                matching: find.byType(SizedBox),
              )
              .first,
        )
        .width;
    final before = width();

    await tester.tap(find.byTooltip('Zoom in').last);
    await tester.pump();
    expect(width(), closeTo(before * 2, 1));

    await tester.tap(find.byTooltip('Zoom out').last);
    await tester.pump();
    expect(width(), closeTo(before, 1));
  });

  testWidgets('one run zooms its own charts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(ImportExportPanel(initialFiles: [_visit('20260203')])),
    );
    await tester.pump();
    expect(find.textContaining('All 7 configurations'), findsOneWidget);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Show fewer configurations (zoom in)'));
      await tester.pump();
    }
    expect(find.textContaining('of 7'), findsOneWidget);
  });

  testWidgets('Enlarge fills the window, and Close returns to the same run', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(
        ImportExportPanel(
          initialFiles: [_visit('20260203'), _visit('20260310')],
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.textContaining('Run 01, ').last);
    await tester.pumpAndSettle();
    const title = 'sub-01, ses-20260310, Run 01';
    expect(find.textContaining(title), findsOneWidget);

    await tester.tap(find.text('Enlarge'));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(tester.getSize(dialog), const Size(1200, 1600));
    expect(
      find.descendant(of: dialog, matching: find.textContaining(title)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.byType(SessionEntriesTable)),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.textContaining(title), findsOneWidget);
  });
}
