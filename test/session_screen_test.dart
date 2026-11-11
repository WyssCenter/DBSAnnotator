import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/app_info.dart' show kNotice, kNoticeShort;
import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/schema_columns.dart' show isInitialValue;
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:dbs_annotator/core/session/session_row.dart';
import 'package:dbs_annotator/ui/electrode_view.dart';
import 'package:dbs_annotator/ui/scale_slider.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:dbs_annotator/main.dart';
import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Headless tests for the programming session's five steps. Contracts are
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
    expect(find.textContaining('Enter or choose the patient ID'), findsWidgets);
    expect(find.text('Patient ID'), findsOneWidget);
    expect(find.text('Frequency'), findsNothing);
  });

  testWidgets('Session is where a visit starts and where files come in and go '
      'out', (tester) async {
    await pumpWizard(tester, open: false);
    expect(find.text('Annotate programming session'), findsOneWidget);
    expect(find.text('BIDS folder'), findsWidgets);
    expect(find.byTooltip('Add a BIDS folder'), findsOneWidget);
    expect(find.text('Other sessions'), findsOneWidget);
    expect(find.text('DBS indication'), findsNothing);
    expect(find.text('Import session files'), findsOneWidget);
    expect(find.text('Import from a BIDS folder'), findsOneWidget);
  });

  testWidgets('research file naming is folded away; an empty patient ID is '
      'marked on the field', (tester) async {
    await pumpWizard(tester, open: false);
    expect(find.text('Patient ID'), findsOneWidget);
    expect(find.text('Visit'), findsOneWidget);
    expect(find.text('Task'), findsNothing);
    expect(find.text('Run'), findsNothing);

    await tapNext(tester);
    expect(find.text('Enter or choose the patient ID'), findsOneWidget);

    await tester.tap(find.text('Research file naming'));
    await tester.pumpAndSettle();
    expect(find.text('Task'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
    expect(find.textContaining('File name: sub-'), findsOneWidget);
  });

  testWidgets('unsaved changes are flagged, and a saved configuration can be '
      'edited in place and deleted', (tester) async {
    final authoring = SessionAuthoring();
    await pumpWizard(tester, authoring: authoring);
    await tapNext(tester, 3);
    expect(find.text('Save configuration'), findsOneWidget);
    expect(find.text('Not saved yet'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Notes'), 'first');
    await tester.pump();
    expect(find.text('Not saved yet'), findsOneWidget);
    await tester.tap(find.text('Save configuration'));
    await tester.pumpAndSettle();
    expect(find.text('Not saved yet'), findsNothing);
    final id = authoring.rows
        .firstWhere((r) => !isInitialValue(r.isInitial))
        .blockId;

    final edit = find.widgetWithText(TextButton, 'Edit');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Editing configuration #$id'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Notes'), 'second');
    await tester.pump();
    expect(find.text('Editing configuration #$id, not saved'), findsOneWidget);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    final tested = [
      for (final r in authoring.rows)
        if (!isInitialValue(r.isInitial)) r,
    ];
    expect(tested.map((r) => r.blockId).toSet(), {id});
    expect(tested.every((r) => r.notes == 'second'), isTrue);

    final more = find.byTooltip('More for configuration #$id');
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete configuration #$id…'));
    await tester.pumpAndSettle();
    expect(find.text('Delete configuration #$id?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(authoring.rows.where((r) => !isInitialValue(r.isInitial)), isEmpty);
  });

  testWidgets('every step says the app is not a medical device', (
    tester,
  ) async {
    await pumpWizard(tester);
    for (var step = 0; step < 4; step++) {
      expect(find.text(kNoticeShort), findsOneWidget);
      await tapNext(tester);
    }
  });

  testWidgets('every launch shows the notice before the session', (
    tester,
  ) async {
    await tester.pumpWidget(const DbsAnnotatorApp());
    expect(find.text(kNotice), findsOneWidget);
    expect(find.text('Annotate programming session'), findsNothing);
    await tester.tap(find.text('I understand'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(kNotice), findsNothing);
    expect(find.text('Annotate programming session'), findsOneWidget);
  });

  testWidgets('the side menu holds the settings for every session', (
    tester,
  ) async {
    await pumpWizard(tester, open: false);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    for (final entry in [
      'Storage folders (BIDS)',
      'DBS indications',
      'Anatomical targets',
      'Leads and IPGs',
      'Stimulation defaults',
      'Programs',
      'Clinical scales',
      'Symptom and side effect ratings',
      'Scale targets',
      'Report sections',
      'Dark theme',
      'Text size',
      'Help and about',
    ]) {
      await tester.scrollUntilVisible(
        find.text(entry),
        100,
        scrollable: find.descendant(
          of: find.byType(Drawer),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text(entry), findsOneWidget, reason: entry);
    }
  });

  testWidgets('Next starts the first session; New appears once one is open', (
    tester,
  ) async {
    await pumpWizard(tester, open: false);
    expect(find.text('New session'), findsNothing);
    expect(find.text('Open saved session'), findsOneWidget);
  });

  testWidgets('wizard: setup, the initial assessment saves itself on Next, '
      'then programming and finish', (tester) async {
    final authoring = SessionAuthoring();
    await pumpWizard(tester, authoring: authoring);

    expect(find.text('Annotate programming session'), findsOneWidget);
    for (final step in [
      'Session',
      'Indication and devices',
      'Initial assessment',
      'Programming',
      'Finish',
    ]) {
      expect(find.text(step), findsWidgets);
    }
    expect(find.text('Ratings'), findsNothing);

    // Session: patient and run, New / Open; no devices, no stimulation.
    expect(find.text('Patient ID'), findsOneWidget);
    expect(find.text('New session'), findsOneWidget);
    expect(find.text('Open saved session'), findsOneWidget);
    expect(find.text('Same lead on both sides'), findsNothing);
    expect(find.text('Frequency'), findsNothing);

    // Indication and devices: the indication, target, leads and IPG.
    await tapNext(tester);
    expect(find.text('Same lead on both sides'), findsOneWidget);
    expect(
      find.widgetWithText(DropdownMenu<String>, 'DBS indication'),
      findsOneWidget,
    );
    expect(find.text('Patient ID'), findsNothing);
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
    expect(find.text('A4'), findsWidgets);
    expect(find.text('For research'), findsOneWidget);
    expect(find.text('BIDS folder (zip)'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('setup details reach every row, medications the initial '
      'assessment, and stars any configuration', (tester) async {
    final authoring = SessionAuthoring();
    await pumpWizard(tester, authoring: authoring);
    await tapNext(tester);

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
    final starInTable = find.byTooltip(RegExp('^Star configuration #'));
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

    // Corrected after the entries, the target is rewritten on every row.
    await tester.tap(find.text('Indication and devices'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownMenu<String>, 'Anatomical target'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPi').last);
    await tester.pumpAndSettle();
    expect(authoring.rows.every((r) => r.target == 'GPi'), isTrue);
  });

  testWidgets('stim - / + steppers move by the fine step, the coarse on a '
      'long press, and the clear X empties '
      'the field', (tester) async {
    await pumpWizard(tester);
    await tapNext(tester, 2);

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

    Future<void> tapButton(String tooltip, {bool long = false}) async {
      final button = find.byTooltip(tooltip).first;
      await tester.ensureVisible(button);
      long ? await tester.longPress(button) : await tester.tap(button);
      await tester.pump();
    }

    String plus(num base, double step) =>
        presetLabel(double.parse((base + step).toStringAsFixed(4)));

    // A tap moves by the fine step, a long press by the coarse one.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Frequency').first,
      '100',
    );
    await tapButton('Increase Frequency');
    expect(leftFreqText(), plus(100, limits.frequencyFineStep));
    await tapButton('Decrease Frequency');
    expect(leftFreqText(), '100');
    await tapButton('Increase Frequency', long: true);
    expect(leftFreqText(), plus(100, limits.frequencyStep));

    // Amplitude keeps the contract decimals.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amplitude').first,
      '1.5',
    );
    await tapButton('Increase Amplitude', long: true);
    expect(leftAmpText(), plus(1.5, limits.amplitudeStep));

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
    await tapNext(tester, 2);

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
    await tapNext(tester);
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

  testWidgets('the indication chosen sets the ratings; an omitted '
      'scale is inserted as "n/a"', (tester) async {
    final authoring = SessionAuthoring();
    await pumpWizard(tester, authoring: authoring);
    await tapNext(tester);
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
    expect(find.text('Test'), findsWidgets);
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
