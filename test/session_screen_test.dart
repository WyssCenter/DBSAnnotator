import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:dbs_annotator/ui/electrode_view.dart';
import 'package:dbs_annotator/ui/scale_slider.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:flutter/material.dart';
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
    expect(find.text('Patient ID (sub-)'), findsOneWidget);
    expect(find.text('Frequency'), findsNothing);
  });

  testWidgets('New asks for the patient ID before anything else', (
    tester,
  ) async {
    await pumpWizard(tester, open: false);
    await tester.tap(find.text('New'));
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
      'Ratings',
      'Programming',
      'Finish',
    ]) {
      expect(find.text(step), findsWidgets);
    }

    // Setup: patient and run, New / Open, and the electrode; no stimulation.
    expect(find.text('Patient ID (sub-)'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Open existing TSV'), findsOneWidget);
    expect(find.text('Same model on both sides'), findsOneWidget);
    expect(find.text('Frequency'), findsNothing);

    // Initial assessment: L/R stimulation, clinical pills, no insert button.
    await tapNext(tester);
    // The default model (Medtronic SenSight B33005) is preselected, so both
    // canvases render immediately instead of the "select a model" placeholder.
    expect(find.byType(ElectrodeView), findsNWidgets(2));
    expect(find.text('Select an electrode model'), findsNothing);
    expect(find.text('Frequency'), findsNWidgets(2));
    expect(find.text('Amplitude'), findsNWidgets(2));
    expect(find.text('Pulse width'), findsNWidgets(2));
    expect(find.text('Insert baseline'), findsNothing);
    for (final name in scalePresets.buttons) {
      expect(find.widgetWithText(ChoiceChip, name), findsOneWidget);
    }

    // A pill adds that preset's scales; names already listed are skipped.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'OCD'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'OCD'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Y-BOCS'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'MDD'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'MDD'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Y-BOCS'), findsOneWidget);
    expect(
      find.text('Score'),
      findsNWidgets(
        {
          ...scalePresets.clinical['OCD']!,
          ...scalePresets.clinical['MDD']!,
        }.length,
      ),
    );

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
    await tapNext(tester);
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

  testWidgets('tapping a stimulation quick-pick chip fills the field', (
    tester,
  ) async {
    await pumpWizard(tester);
    await tapNext(tester); // Step 1.

    // One 125 Hz chip per side; tap the Left one.
    final chip = find.widgetWithText(ActionChip, '125').first;
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();

    final leftFreq = tester.widget<TextField>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Frequency').first,
        matching: find.byType(TextField),
      ),
    );
    expect(leftFreq.controller!.text, '125');
    // In range, so the insert is not blocked by validation.
    expect(find.text('Not a number'), findsNothing);
  });

  testWidgets('session scales defined in Step 2 become Step-3 rating rows; '
      'an omitted scale is inserted as "n/a"', (tester) async {
    final authoring = SessionAuthoring();
    await pumpWizard(tester, authoring: authoring);
    await tapNext(tester, 2); // Step 2.

    // A session pill adds that preset's (name, min, max) rows.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'PD'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'PD'));
    await tester.pump();
    final pdRows = scalePresets.session['PD']!;
    const first = 'MDS-UPDRS 3.3 Rigidity RUE';
    expect(find.widgetWithText(TextField, first), findsOneWidget);
    expect(find.text('Min'), findsNWidgets(pdRows.length));
    expect(find.text('Max'), findsNWidgets(pdRows.length));

    // Programming: one rating row per scale, each with a bar and an omit
    // ("not assessed") toggle.
    await tapNext(tester);
    // One custom ScaleSlider (bar + chevrons + X-omit) per Step-2 scale.
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

    // One is_initial=0 block, one row per scale: omitted ones carry the
    // limits.json omitted literal, untouched continuous bars their min.
    expect(authoring.rows, hasLength(pdRows.length));
    expect(authoring.rows.first.isInitial, '0');
    expect(authoring.rows.first.scaleName, first);
    expect(authoring.rows.first.scaleValue, limits.sessionScaleOmittedTsv);
    expect(authoring.rows.first.scaleValue, 'n/a');
    final byName = {for (final r in authoring.rows) r.scaleName: r.scaleValue};
    expect(byName['Dyskinesia'], 'n/a');
    expect(byName['Paresthesia'], '0');

    // The recording rows appear in the inserted-entries review table.
    expect(find.text('Rec'), findsWidgets);
    expect(find.text('No entries inserted yet.'), findsNothing);
  });
}
