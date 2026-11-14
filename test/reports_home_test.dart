/// The import and export panel shown on the session screen's Setup step.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/ui/import_export_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ElectrodeCatalog> _catalog() async => ElectrodeCatalog.fromJson(
  jsonDecode(File('schema/electrode_models.json').readAsStringSync())
      as Map<String, dynamic>,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opens on a prompt, with every action disabled', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ImportExportPanel(catalog: await _catalog()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Import session files'), findsNothing);
    expect(
      find.text('Choose a BIDS folder above to import from it.'),
      findsOneWidget,
    );
  });

  test('the panel composes rather than reimplements', () {
    final src = File('lib/ui/import_export_panel.dart').readAsLinesSync();
    final code = src.where((l) {
      final t = l.trim();
      return t.isNotEmpty && !t.startsWith('//') && !t.startsWith('///');
    }).length;
    expect(
      code,
      lessThan(900),
      reason: 'code lines excluding comments and blanks: $code',
    );

    final text = src.join(String.fromCharCode(10));
    for (final shared in [
      'SessionEntriesTable(',
      'EntryChartsView(',
      'showScaleTargetsDialog(',
      'showReportSectionsDialog(',
      'renderReportGraphics(',
      'exportFile(',
      'buildSessionReportData(',
      'buildLongitudinalReportData(',
      'buildAggregate(',
      'exportBidsDataset(',
      'unavailableReason(',
      'planBidsMerge(',
      'pickCheckedDatasetFolder(',
      'confirmMerge(',
    ]) {
      expect(text, contains(shared), reason: shared);
    }
  });
}
