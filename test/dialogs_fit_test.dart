/// Every dataset, export and recovery dialog shows all of its text: at a
/// desktop window, a small one and a phone, at the default and the largest
/// text size, nothing overflows, nothing is cut at a line limit, and the
/// dialog stays on screen and no wider than it needs.
library;

import 'dart:io';

import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/core/session/scale_scoring.dart';
import 'package:dbs_annotator/report/longitudinal_sections.dart';
import 'package:dbs_annotator/report/report_sections.dart';
import 'package:dbs_annotator/report/upload_actions.dart';
import 'package:dbs_annotator/ui/bids_merge_ui.dart';
import 'package:dbs_annotator/ui/close_guard.dart';
import 'package:dbs_annotator/ui/import_export_panel.dart';
import 'package:dbs_annotator/ui/report_sections_dialog.dart';
import 'package:dbs_annotator/ui/scale_targets_dialog.dart';
import 'package:dbs_annotator/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

const _fixture = 'sub-01_ses-20260203_task-programming_run-01_beh.tsv';

Uploaded _session() => classifyUpload(
  _fixture,
  File('test/fixtures/$_fixture').readAsStringSync(),
).file!;

const _root =
    r'C:\Users\clinician\Documents\Studies\DBS-OCD-multicentre\bids_dataset';

const _name = BidsName(
  subject: 'OCD017',
  session: '20261005',
  task: 'programming',
  run: '01',
);

final _manyPaths = [
  for (var i = 0; i < 15; i++)
    'sub-OCD017/ses-2026100$i/beh/sub-OCD017_ses-2026100${i}_task-programming_run-01_beh.tsv',
];

typedef _Case = ({
  String name,
  void Function(BuildContext context) open,
  Future<void> Function(WidgetTester tester)? then,
});

final List<_Case> _cases = [
  (
    name: 'dataset folder check, empty folder',
    open: (c) => checkDatasetFolder(c, _root, const []),
    then: null,
  ),
  (
    name: 'dataset folder check, not a dataset',
    open: (c) =>
        checkDatasetFolder(c, _root, const [(path: 'notes.txt', content: 'x')]),
    then: null,
  ),
  (
    name: 'confirm merge, every list',
    open: (c) => confirmMerge(
      c,
      (
        write: const [
          (path: 'a', content: 'b'),
          (
            path: 'derivatives/dbs-annotator-aggregate/desc-aggregate_beh.tsv',
            content: 'b',
          ),
          (
            path: 'derivatives/dbs-annotator-aggregate/desc-aggregate_beh.json',
            content: 'b',
          ),
        ],
        added: _manyPaths,
        rowMerged: const ['participants.tsv'],
        rebuilt: const [
          'derivatives/dbs-annotator-aggregate/desc-aggregate_beh.tsv',
          'derivatives/dbs-annotator-aggregate/desc-aggregate_beh.json',
        ],
        keptAsIs: const ['README', 'dataset_description.json'],
        unread: const [],
        refused: [
          ..._manyPaths.take(2),
          'derivatives/dbs-annotator-aggregate/desc-aggregate_beh.tsv',
        ],
        leftOut: const [
          (
            path: 'sub-03/ses-20260203/beh/sub-03_ses-20260203_task-notes_beh.tsv',
            reason: 'not readable as a session or notes TSV',
          ),
        ],
      ),
      _root,
      renumbered: [_manyPaths.first],
    ),
    then: null,
  ),
  (
    name: 'single session add, report ticked',
    open: askSingleSessionAdd,
    then: (t) => t.tap(find.text('Report')),
  ),
  (
    name: 'reopen unfinished',
    open: (c) => askReopenUnfinished(
      c,
      title: 'Reopen the unfinished session?',
      message:
          'The app closed while ${_name.filename} was open, with 14 blocks '
          'recorded since it was last saved. Reopen it to carry on, or '
          'discard the recovery copy.',
    ),
    then: null,
  ),
  (
    name: 'keep recovery copy',
    open: (c) => askKeepRecoveryCopy(c, onlyCopy: false),
    then: null,
  ),
  (
    name: 'keep recovery copy, only copy and stale',
    open: (c) => askKeepRecoveryCopy(c, onlyCopy: true, copyMayBeStale: true),
    then: null,
  ),
  (name: 'entries could not be saved', open: askLeaveUnsaved, then: null),
  (
    name: 'session report sections',
    open: (c) => showReportSectionsDialog(
      c,
      kAllReportSections,
      onEditTargets: () async {},
    ),
    then: null,
  ),
  (
    name: 'longitudinal report sections',
    open: (c) => showLongitudinalSectionsDialog(
      c,
      kDefaultLongitudinalSections,
      onEditTargets: () async {},
    ),
    then: null,
  ),
  (
    name: 'attestation, rated',
    open: (c) => askAttestation(c, rated: true),
    then: null,
  ),
  (
    name: 'attestation, notes only',
    open: (c) => askAttestation(c, rated: false),
    then: null,
  ),
  (
    name: 'scale targets, long names',
    open: (c) => showScaleTargetsDialog(c, [
      for (final n in [
        'Y-BOCS obsessions subscale, clinician rated',
        'Mood',
        'Energy',
        'Anxiety (patient reported, visual analogue)',
        'Tremor',
        'Rigidity',
        'Speech',
        'Dyskinesia',
      ])
        (name: n, min: 0, max: 10, mode: ScaleMode.min, custom: null),
    ]),
    then: null,
  ),
];

/// Window size and text scale: desktop, desktop at A+ max, a small window at
/// A+ max, a phone, and a tablet in portrait.
const _screens = [
  (Size(1280, 800), 1.0),
  (Size(1280, 800), 1.6),
  (Size(800, 600), 1.6),
  (Size(360, 640), 1.0),
  (Size(768, 1024), 1.3),
];

/// The app's theme in a real text font. The test binding's default font draws
/// every glyph as a full square, about twice as wide as a real font, which
/// would fail labels that fit on screen.
ThemeData _theme() {
  final base = dbsTheme(Brightness.light);
  return base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'TestText'));
}

Future<BuildContext> _pumpHost(WidgetTester tester, Size size, double scale) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late BuildContext host;
  return tester
      .pumpWidget(
        MaterialApp(
          theme: _theme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                host = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      )
      .then((_) => host);
}

/// The open dialog overflows nowhere, cuts no text, sits on screen, and is
/// no wider than the theme's cap.
void _expectFits(WidgetTester tester, Size size, String what) {
  expect(tester.takeException(), isNull, reason: '$what: overflow');
  final dialog = find.byType(Dialog);
  expect(dialog, findsOneWidget, reason: what);
  // The Dialog widget spans the screen; its Material is the visible card.
  final rect = tester.getRect(
    find.descendant(of: dialog, matching: find.byType(Material)).first,
  );
  expect(
    (Offset.zero & size).contains(rect.topLeft) &&
        rect.right <= size.width &&
        rect.bottom <= size.height,
    isTrue,
    reason: '$what: off screen ($rect in $size)',
  );
  expect(rect.width, lessThanOrEqualTo(600), reason: '$what: too wide');
  for (final p in tester.renderObjectList<RenderParagraph>(
    find.descendant(of: dialog, matching: find.byType(RichText)),
  )) {
    expect(
      p.didExceedMaxLines,
      isFalse,
      reason: '$what: cut text "${p.text.toPlainText()}"',
    );
  }
}

String _label(Size size, double scale) =>
    '${size.width.toInt()}x${size.height.toInt()}, text x$scale';

void main() {
  setUpAll(() async {
    final loader = FontLoader('TestText')
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSans-Bold.ttf'));
    await loader.load();
  });

  for (final (size, scale) in _screens) {
    for (final c in _cases) {
      testWidgets('${c.name} fits at ${_label(size, scale)}', (tester) async {
        final host = await _pumpHost(tester, size, scale);
        c.open(host);
        await tester.pumpAndSettle();
        if (c.then case final then?) {
          await then(tester);
          await tester.pumpAndSettle();
        }
        _expectFits(tester, size, c.name);
      });
    }

    testWidgets('saved into the dataset fits at ${_label(size, scale)}', (
      tester,
    ) async {
      final host = await _pumpHost(tester, size, scale);
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('dialogs_fit'),
      );
      addTearDown(() => dir!.deleteSync(recursive: true));
      // The table is written before the dialog opens, which is real file I/O,
      // so wait for the dialog rather than for a fixed time: a slow CI runner
      // takes longer than any guess.
      final saved = saveAggregateInto(
        host,
        dir!.path,
        tsv: 'a\tb\n',
        sidecar: '{}',
        summary: 'The combined table of 12 sessions from 3 participants',
      );
      for (var i = 0; i < 200 && find.byType(Dialog).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      _expectFits(tester, size, 'saved into the dataset');
      // Close it and let the save finish inside the test, so nothing is still
      // running when tearDown deletes the folder.
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => saved);
    });

    if (size.width < 600) continue;
    testWidgets('every export info dialog fits at ${_label(size, scale)}', (
      tester,
    ) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ImportExportPanel(initialFiles: [_session()]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < ReportAction.values.length; i++) {
        final info = find.byTooltip('About this export').at(i);
        await tester.ensureVisible(info);
        await tester.tap(info);
        await tester.pumpAndSettle();
        _expectFits(tester, size, ReportAction.values[i].label);
        await tester.tap(find.widgetWithText(TextButton, 'Close').last);
        await tester.pumpAndSettle();
      }
    });
  }
}
