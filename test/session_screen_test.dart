import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/ui/electrode_view.dart';
import 'package:dbs_annotator/ui/scale_slider.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Headless tests for the Complete-Workflow 4-step wizard. Contracts are
/// injected from the repo-root schema files (like electrode_catalog_test),
/// so no asset bundle or platform channel is touched; Open/Export are never
/// tapped. A [SessionAuthoring] is injected so inserted rows can be
/// asserted directly.
void main() {
  Map<String, dynamic> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  final catalog = ElectrodeCatalog.fromJson(
    readJson('schema/electrode_models.json'),
  );
  final limits = StimLimits.fromJson(readJson('schema/limits.json'));
  final scalePresets = ScalePresets.fromJson(
    readJson('schema/scale_presets.json'),
  );

  /// Tall surface so the current step's content is mostly on-screen (the
  /// Stepper is scrollable; taps still use ensureVisible), then pump the
  /// wizard with all contracts injected.
  Future<void> pumpWizard(
    WidgetTester tester, {
    SessionAuthoring? authoring,
    bool open = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: SessionScreen(
          catalog: catalog,
          limits: limits,
          scalePresets: scalePresets,
          authoring: open ? authoring ?? SessionAuthoring() : null,
        ),
      ),
    );
    // Let the injected-contracts future resolve.
    await tester.pump();
    await tester.pump();
  }

  Future<void> choosePathology(WidgetTester tester, String pathology) async {
    await tester.tap(
      find.widgetWithText(DropdownMenu<String>, 'DBS indication'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(pathology).last);
    await tester.pumpAndSettle();
  }

  Future<void> openScales(
    WidgetTester tester,
    String tooltip,
    String group,
  ) async {
    await tester.ensureVisible(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scales for $group'));
    await tester.pumpAndSettle();
  }

  bool? ticked(WidgetTester tester, String name) => tester
      .widget<CheckboxMenuButton>(find.widgetWithText(CheckboxMenuButton, name))
      .value;

  Future<void> closeMenu(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
  }

  Future<void> tickScale(
    WidgetTester tester,
    String tooltip,
    String group,
    String name,
  ) async {
    await openScales(tester, tooltip, group);
    await tester.tap(find.widgetWithText(CheckboxMenuButton, name));
    await tester.pumpAndSettle();
    await closeMenu(tester);
  }

  /// Advance the wizard [steps] times with the bottom bar's Next button.
  Future<void> tapNext(WidgetTester tester, [int steps = 1]) async {
    for (var i = 0; i < steps; i++) {
      final next = find.text('Next');
      expect(next, findsOneWidget);
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('setup cannot be left before a session is started, and says '
      'why', (tester) async {
    await pumpWizard(tester, open: false);
    await tapNext(tester);
    expect(
      find.textContaining('press New, or open a saved session'),
      findsOneWidget,
    );
    expect(find.text('Patient ID'), findsOneWidget);
    expect(find.text('Frequency'), findsNothing);
  });

  testWidgets('New asks for the patient ID before anything else', (
    tester,
  ) async {
    await pumpWizard(tester, open: false);
    await tester.tap(find.text('New session'));
    await tester.pump();
    expect(find.text('Enter the patient ID first.'), findsOneWidget);
    expect(find.textContaining('Where should'), findsNothing);
  });

  testWidgets('wizard: setup, the initial assessment saves itself on Next, '
      'then programming and finish', (tester) async {
    final authoring = SessionAuthoring();
    await pumpWizard(tester, authoring: authoring);

    expect(find.text('Complete workflow'), findsOneWidget);
    for (final step in [
      'Setup',
      'Initial assessment',
      'Programming',
      'Finish',
    ]) {
      expect(find.text(step), findsWidgets);
    }
    expect(find.text('Ratings'), findsNothing);

    // Setup: patient and run, New / Open, and the electrode; no stimulation.
    expect(find.text('Patient ID'), findsOneWidget);
    expect(find.text('New session'), findsOneWidget);
    expect(find.text('Open saved session'), findsOneWidget);
    expect(find.text('Same lead on both sides'), findsOneWidget);
    expect(find.text('Frequency'), findsNothing);

    // Initial assessment: L/R stimulation and clinical scales, no buttons
    // per pathology and no insert button.
    await tapNext(tester);
    // The default model (Medtronic SenSight B33005) is preselected, so both
    // canvases render immediately instead of the "select a model" placeholder.
    expect(find.byType(ElectrodeView), findsNWidgets(2));
    expect(find.text('Select an electrode model'), findsNothing);
    expect(find.text('Frequency'), findsNWidgets(2));
    expect(find.text('Amplitude'), findsNWidgets(2));
    expect(find.text('Pulse width'), findsNWidgets(2));
    expect(find.text('Insert baseline'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);

    // + opens each pathology's scales as tick boxes; ticking adds a scale,
    // and a listed scale shows ticked wherever it appears.
    await tickScale(tester, 'Add clinical scales', 'OCD', 'Y-BOCS');
    expect(find.widgetWithText(TextField, 'Y-BOCS'), findsOneWidget);
    await openScales(tester, 'Add clinical scales', 'OCD');
    expect(ticked(tester, 'Y-BOCS'), isTrue);
    expect(ticked(tester, 'Y-BOCS-o'), isFalse);
    await closeMenu(tester);
    await tickScale(tester, 'Add clinical scales', 'MDD', 'HAM-D');
    expect(find.text('Score'), findsNWidgets(2));

    // Next writes ONE is_initial=1 block, one row per scored scale.
    await tester.enterText(find.widgetWithText(TextField, 'Score').first, '12');
    await tapNext(tester);
    expect(authoring.rows, hasLength(1));
    expect(authoring.rows.single.isInitial, '1');
    expect(authoring.rows.single.scaleName, 'Y-BOCS');
    expect(authoring.rows.single.scaleValue, '12');
    expect(authoring.rows.single.blockId, '0');

    // Going back and changing a score rewrites that block, never a second.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Score').first, '14');
    await tapNext(tester);
    expect(authoring.rows, hasLength(1));
    expect(authoring.rows.single.scaleValue, '14');
    expect(authoring.rows.single.blockId, '0');
    expect(authoring.blockId, 1);

    // Programming lists the initial assessment in the review table.
    expect(find.text('Initial'), findsWidgets);
    expect(find.text('Y-BOCS'), findsWidgets);
    expect(find.text('Save configuration'), findsOneWidget);

    // Finish: a summary, then the exports grouped by who reads them.
    await tapNext(tester);
    expect(find.text('Configurations tested: 0'), findsOneWidget);
    expect(find.text('For the patient record'), findsOneWidget);
    expect(find.text('Report (PDF)'), findsOneWidget);
    expect(find.text('Report (Word)'), findsOneWidget);
    expect(find.text('A4'), findsOneWidget);
    expect(find.text('For research'), findsOneWidget);
    expect(find.text('Raw data file'), findsOneWidget);
    expect(find.text('Research dataset (BIDS, zip)'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('setup details reach every row, medications the initial '
      'assessment, and stars any configuration', (tester) async {
    final authoring = SessionAuthoring();
    await pumpWizard(tester, authoring: authoring);

    await tester.tap(
      find.widgetWithText(DropdownMenu<String>, 'DBS indication'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('PD').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownMenu<String>, 'Anatomical target'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('STN').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownMenu<String>, 'IPG model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Medtronic Percept PC').last);
    await tester.pumpAndSettle();

    // Choosing the pathology loaded its clinical scales.
    await tapNext(tester);
    expect(find.widgetWithText(TextField, 'MDS-UPDRS'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Medications'),
      'Levodopa 100 mg',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Score').first, '30');
    await tapNext(tester);

    final starSwitch = find.text('Star this configuration');
    await tester.ensureVisible(starSwitch);
    await tester.tap(starSwitch);
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      final save = find.text('Save configuration');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
    }
    expect(starredBlocksIn(authoring.rows), {'1'});

    // An earlier configuration is starred from the table.
    final starInTable = find.byTooltip('Star this configuration');
    await tester.ensureVisible(starInTable);
    await tester.pumpAndSettle();
    await tester.tap(starInTable);
    await tester.pump();
    expect(starredBlocksIn(authoring.rows), {'1', '2'});

    final rows = authoring.rows;
    expect(
      rows.every(
        (r) =>
            r.pathology == 'PD' &&
            r.target == 'STN' &&
            r.leftIpgModel == 'Medtronic Percept PC' &&
            r.rightIpgModel == 'Medtronic Percept PC',
      ),
      isTrue,
    );
    expect(rows.first.medications, 'Levodopa 100 mg');
    expect(
      rows.where((r) => r.isInitial == '0').every((r) => r.medications == ''),
      isTrue,
    );

    // Once recorded, the session's pathology can no longer be changed.
    await tester.tap(find.textContaining('PD  ·  STN'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownMenu<String>>(
            find.widgetWithText(DropdownMenu<String>, 'DBS indication'),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets('stim - / + steppers move by step1 and the clear X empties '
      'the field', (tester) async {
    await pumpWizard(tester);
    await tapNext(tester); // Step 1.

    String leftFreqText() => tester
        .widget<TextField>(
          find.descendant(
            of: find.widgetWithText(TextFormField, 'Frequency').first,
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;
    String leftAmpText() => tester
        .widget<TextField>(
          find.descendant(
            of: find.widgetWithText(TextFormField, 'Amplitude').first,
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;

    Future<void> tapButton(String tooltip) async {
      final button = find.byTooltip(tooltip).first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
    }

    // Frequency: step1 = 10.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Frequency').first,
      '100',
    );
    await tapButton('Increase Frequency');
    expect(leftFreqText(), '110');
    await tapButton('Decrease Frequency');
    expect(leftFreqText(), '100');

    // Amplitude: step1 = 1, keeping the contract decimals (1.5 -> 2.5).
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amplitude').first,
      '1.5',
    );
    await tapButton('Increase Amplitude');
    expect(leftAmpText(), '2.5');

    // Clear X empties the field; stepping from blank starts at min.
    await tapButton('Clear Frequency');
    expect(leftFreqText(), '');
    await tapButton('Increase Frequency');
    expect(leftFreqText(), presetLabel(limits.frequency.min));

    // Clamped at max: repeated + never exceeds the limit.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Frequency').first,
      presetLabel(limits.frequency.max),
    );
    await tapButton('Increase Frequency');
    expect(leftFreqText(), presetLabel(limits.frequency.max));
  });

  testWidgets('out-of-range stimulation value keeps the initial assessment '
      'open and unsaved', (tester) async {
    final authoring = SessionAuthoring();
    await pumpWizard(tester, authoring: authoring);
    await tapNext(tester); // Step 1.

    // First TextFormField with the "Hz" suffix is the Left frequency.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Frequency').first,
      '${limits.frequency.max + 1}',
    );
    await tester.pump();
    await tapNext(tester);

    expect(
      find.text('Fix out-of-range stimulation values before inserting.'),
      findsOneWidget,
    );
    expect(authoring.rows, isEmpty);
    expect(find.text('Frequency'), findsNWidgets(2));
  });

  testWidgets('the initial assessment starts from the indication defaults', (
    tester,
  ) async {
    await pumpWizard(tester);
    await choosePathology(tester, 'PD');
    await tapNext(tester);

    String text(String label, int side) => tester
        .widget<TextField>(
          find.descendant(
            of: find.widgetWithText(TextFormField, label).at(side),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text;
    for (final side in [0, 1]) {
      expect(text('Frequency', side), '130');
      expect(text('Amplitude', side), '1.5');
      expect(text('Pulse width', side), '60');
    }
    expect(find.byType(ActionChip), findsNothing);

    // A changed value is kept when coming back, not reset to the default.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amplitude').first,
      '2',
    );
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tapNext(tester);
    expect(text('Amplitude', 0), '2');
  });

  testWidgets('the pathology chosen in Setup sets the ratings; an omitted '
      'scale is inserted as "n/a"', (tester) async {
    final authoring = SessionAuthoring();
    await pumpWizard(tester, authoring: authoring);
    await choosePathology(tester, 'PD');
    await tapNext(tester, 2);

    // Programming: one rating row per PD scale, each with a bar and an omit
    // ("not assessed") toggle.
    final pdRows = scalePresets.session['PD']!;
    const first = 'MDS-UPDRS 3.3 Rigidity RUE';
    expect(find.byType(ScaleSlider), findsNWidgets(pdRows.length));
    expect(find.text(first), findsOneWidget);

    // Official items start not assessed; omit Dyskinesia, keep Paresthesia.
    expect(find.byTooltip('Include (assessed)'), findsNWidgets(10));
    final omitDyskinesia = find.byTooltip('Omit (not assessed)').first;
    await tester.ensureVisible(omitDyskinesia);
    await tester.tap(omitDyskinesia);
    await tester.pump();

    final insert = find.text('Save configuration');
    await tester.ensureVisible(insert);
    await tester.tap(insert);
    await tester.pump();

    // The PD defaults made the initial assessment worth saving, then one
    // is_initial=0 block, one row per scale: omitted ones carry the
    // limits.json omitted literal, untouched continuous bars their min.
    final recorded = [
      for (final r in authoring.rows)
        if (r.isInitial == '0') r,
    ];
    expect(authoring.rows.first.isInitial, '1');
    expect(recorded, hasLength(pdRows.length));
    expect(recorded.first.scaleName, first);
    expect(recorded.first.scaleValue, limits.sessionScaleOmittedTsv);
    expect(recorded.first.scaleValue, 'n/a');
    final byName = {for (final r in recorded) r.scaleName: r.scaleValue};
    expect(byName['Dyskinesia'], 'n/a');
    expect(byName['Paresthesia'], '0');

    // The recording rows appear in the inserted-entries review table.
    expect(find.text('Rec'), findsWidgets);
    expect(find.text('No entries inserted yet.'), findsNothing);

    // The session's own pathology shows its ratings ticked; ticking another
    // pathology's rating adds it, unticking one removes it.
    await openScales(tester, 'Add ratings', 'PD');
    expect(ticked(tester, first), isTrue);
    await closeMenu(tester);
    await tickScale(tester, 'Add ratings', 'ET', 'Action tremor');
    expect(find.byType(ScaleSlider), findsNWidgets(pdRows.length + 1));
    await tickScale(tester, 'Add ratings', 'PD', 'MDS-UPDRS 3.1 Speech');
    expect(find.byType(ScaleSlider), findsNWidgets(pdRows.length));
  });
}
