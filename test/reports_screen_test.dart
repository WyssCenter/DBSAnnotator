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
  testWidgets('with nothing imported, the actions wait for a session', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _host(const ImportExportPanel(folder: 'C:/Studies/OCD-DBS')),
    );
    await tester.pump();

    expect(find.text('No files imported.'), findsOneWidget);
    expect(find.textContaining('appear once a session is imported'), findsOne);
    expect(find.text('Single session report'), findsNothing);
    ButtonStyleButton load() => tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Import'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(load().onPressed, isNotNull);

    await tester.pumpWidget(_host(const ImportExportPanel()));
    await tester.pump();
    expect(load().onPressed, isNull, reason: 'no BIDS folder chosen above');
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
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<ScalesChartPainter>()
          .single;
      expect(painter.spec.bestXs, isNotEmpty);

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
}
