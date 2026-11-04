/// Recording into a dataset from either workflow: the Task field, filing
/// notes beside a visit, and the session label check.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:dbs_annotator/core/tsv.dart';
import 'package:dbs_annotator/ui/annotations_screen.dart';
import 'package:dbs_annotator/ui/bids_merge_ui.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BidsName _name(String task) =>
    BidsName(subject: '01', session: 'preop', task: task, run: '01');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fileIntoDataset', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('dbs_target'));
    tearDown(() => root.deleteSync(recursive: true));

    Future<String?> put(BidsName name, String kind, {String tsv = 'a'}) async =>
        (await fileIntoDataset(
          root: root.path,
          name: name,
          tsv: tsv,
          kind: kind,
          acqTime: '2026-02-03T09:00:00+00:00',
        ))?.path;

    test('notes are filed beside the visit, under their own task', () async {
      await put(_name('programming'), 'session_tsv');
      final path = await put(_name('notes'), 'annotation_tsv');

      final dir = '${root.path}/sub-01/ses-preop/beh';
      expect(path, '$dir/sub-01_ses-preop_task-notes_run-01_beh.tsv');
      expect(File(path!).existsSync(), isTrue);
      expect(
        File('$dir/sub-01_ses-preop_task-programming_run-01_beh.tsv')
            .existsSync(),
        isTrue,
      );
      final scans = parseTsvRecords(
        File('${root.path}/sub-01/ses-preop/sub-01_ses-preop_scans.tsv')
            .readAsStringSync(),
      );
      expect(scans.map((r) => r['filename']), hasLength(2));
    });

    test('a renamed task names the file and its sidecar', () async {
      final path = await put(_name('followup'), 'annotation_tsv');
      expect(path, endsWith('_task-followup_run-01_beh.tsv'));
      final sidecar = jsonDecode(
        File(path!.replaceFirst(RegExp(r'\.tsv$'), '.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(sidecar['TaskName'], 'followup');
    });

    test('a file already there is refused, not overwritten', () async {
      await put(_name('notes'), 'annotation_tsv');
      expect(
        await put(_name('notes'), 'annotation_tsv', tsv: 'different'),
        isNull,
      );
    });
  });

  group('session label', () {
    Future<void> open(
      WidgetTester tester,
      String proposed, {
      String? Function(String)? note,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => askSessionLabel(context, proposed, note: note),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    bool useEnabled(WidgetTester tester) => tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Use'))
        .enabled;

    testWidgets('says how a typed label will be filed', (tester) async {
      await open(tester, '3-mo');
      expect(find.textContaining('Filed as ses-3mo'), findsOneWidget);
      expect(useEnabled(tester), isTrue);
    });

    testWidgets('an empty label cannot be used', (tester) async {
      await open(tester, '20260203');
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(useEnabled(tester), isFalse);
    });

    testWidgets('a name already filed is explained, not refused', (
      tester,
    ) async {
      await open(
        tester,
        'preop',
        note: (label) => label == 'preop' ? 'filed as run-02' : null,
      );
      expect(find.textContaining('filed as run-02'), findsOneWidget);
      expect(useEnabled(tester), isTrue);
    });
  });

  group('the Task field', () {
    String taskText(WidgetTester tester) => tester
        .widget<TextField>(find.widgetWithText(TextField, 'Task (task-)'))
        .controller!
        .text;

    testWidgets('defaults to programming in the complete workflow', (
      tester,
    ) async {
      Map<String, dynamic> readJson(String path) =>
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      await tester.binding.setSurfaceSize(const Size(1400, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: SessionScreen(
            catalog: ElectrodeCatalog.fromJson(
              readJson('schema/electrode_models.json'),
            ),
            limits: StimLimits.fromJson(readJson('schema/limits.json')),
            scalePresets: ScalePresets.fromJson(
              readJson('schema/scale_presets.json'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(taskText(tester), 'programming');
    });

    testWidgets('defaults to notes in annotation-only mode', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AnnotationsScreen()));
      await tester.pump();
      expect(taskText(tester), 'notes');
    });
  });
}
