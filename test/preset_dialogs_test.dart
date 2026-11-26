import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:dbs_annotator/ui/devices_dialog.dart';
import 'package:dbs_annotator/ui/list_editor_dialog.dart';
import 'package:dbs_annotator/ui/scale_presets_dialog.dart';
import 'package:dbs_annotator/ui/stim_defaults_dialog.dart';
import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _none = ScalePresets(buttons: [], clinical: {}, session: {});

/// Headless coverage for the desktop-style preset editor dialogs.
/// They use only `showDialog` (no platform channels), so the seed -> edit ->
/// save round trip is verifiable without a device.
void main() {
  /// Pump a host with a button that opens [open] and stores its result.
  Future<void> pumpHost(
    WidgetTester tester,
    Future<void> Function(BuildContext) open,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('stim defaults dialog keeps filled rows and checks ranges', (
    tester,
  ) async {
    const limits = StimLimits(
      frequency: (min: 10, max: 200),
      amplitude: (min: 0, max: 15),
      pulseWidth: (min: 10, max: 200),
      sessionScale: (min: 0, max: 10),
      defaults: {
        'PD': [130, 1.5, 60],
      },
    );
    Map<String, List<num>>? result;
    await pumpHost(tester, (context) async {
      result = await showStimDefaultsDialog(
        context,
        limits: limits,
        indications: const ['PD', 'ET'],
        defaults: const {},
      );
    });

    expect(find.text('Stimulation defaults'), findsOneWidget);
    final etFrequency = find.widgetWithText(TextField, 'Frequency').at(1);
    await tester.enterText(etFrequency, '500');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('Frequency must be 10 to 200 Hz'), findsOneWidget);

    await tester.enterText(etFrequency, '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, {
      'PD': [130, 1.5, 60],
    });
  });

  testWidgets('devices dialog edits leads and IPGs per manufacturer', (
    tester,
  ) async {
    const m3389 = ElectrodeModel(
      name: 'Medtronic 3389',
      numContacts: 4,
      contactHeight: 1.5,
      contactSpacing: 0.5,
      leadDiameter: 1.27,
      isDirectional: false,
      tipContact: false,
      segmentsPerLevel: 1,
      directionalLevels: null,
      levelDirectional: [false, false, false, false],
    );
    Devices? result;
    await pumpHost(tester, (context) async {
      result = await showDevicesDialog(
        context,
        devices: {
          'Medtronic': (
            leads: {'Medtronic 3389': m3389},
            ipgs: ['Medtronic Percept RC'],
          ),
        },
        defaults: const {},
      );
    });

    // Models show without their manufacturer, and are saved with it.
    expect(find.widgetWithText(TextField, '3389'), findsOneWidget);
    await tester.tap(find.text('Add manufacturer'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Manufacturer'),
      'Newronika',
    );
    // A new lead opens its design: five levels, the top one directional.
    await tester.tap(find.text('Add lead'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close lead design'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Lead model'), 'A');
    await tester.ensureVisible(find.byTooltip('More levels'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More levels'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'E4'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'E4'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Close lead design'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close lead design'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close lead design'), findsNothing);
    await tester.tap(find.text('Add IPG'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'IPG model'),
      'AlphaDBS',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result!.keys, ['Medtronic', 'Newronika']);
    expect(result!['Medtronic']!.leads.keys, ['Medtronic 3389']);
    final lead = result!['Newronika']!.leads['Newronika A']!;
    expect(lead.name, 'Newronika A');
    expect(lead.levelDirectional, [false, true, true, false, true]);
    expect(result!['Newronika']!.ipgs, ['Newronika AlphaDBS']);
  });

  /// The text field a header names, through its screen reader label.
  Finder field(String label) => find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == label,
    ),
    matching: find.byType(TextField),
  );

  SessionScaleRow rating(
    String name, {
    String mode = 'min',
    String step = '',
  }) => (name: name, min: '0', max: '10', mode: mode, step: step, custom: '');

  testWidgets('clinical scales dialog returns names and their ranges', (
    tester,
  ) async {
    ({Map<String, List<String>> groups, Map<String, List<String>> ranges})?
    result;
    await pumpHost(tester, (context) async {
      result = await showClinicalPresetsDialog(
        context,
        presets: const {
          'OCD': ['Y-BOCS', 'MADRS'],
        },
        ranges: const {'Y-BOCS': (min: '0', max: '40')},
        defaults: _none,
        indications: const ['OCD'],
      );
    });

    expect(find.text('Clinical scales'), findsOneWidget);
    expect(find.textContaining(kScaleLicenceNotice), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result!.groups, {
      'OCD': ['Y-BOCS', 'MADRS'],
    });
    expect(result!.ranges, {
      'Y-BOCS': ['0', '40'],
    });
  });

  testWidgets('the ratings dialog opens on the indication of the visit', (
    tester,
  ) async {
    await pumpHost(tester, (context) async {
      await showSessionPresetsDialog(
        context,
        presets: {
          'A': [rating('Tremor')],
          'B': [rating('Rigidity')],
        },
        defaults: _none,
        indications: const ['A', 'B'],
        initial: 'B',
      );
    });
    expect(find.text('Rigidity'), findsOneWidget);
    expect(find.text('Tremor'), findsNothing);
  });

  testWidgets('Add indication offers only indications without ratings', (
    tester,
  ) async {
    await pumpHost(tester, (context) async {
      await showSessionPresetsDialog(
        context,
        presets: {
          'A': [rating('Tremor')],
        },
        defaults: _none,
        indications: const ['A', 'C'],
      );
    });
    await tester.tap(find.text('Add indication'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(MenuItemButton, 'C'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'A'), findsNothing);
  });

  testWidgets('a value to get closest to is saved only inside the range', (
    tester,
  ) async {
    Map<String, List<List<String>>>? result;
    await pumpHost(tester, (context) async {
      result = await showSessionPresetsDialog(
        context,
        presets: {
          'OCD': [rating('Energy')],
        },
        defaults: _none,
        indications: const ['OCD'],
      );
    });

    await tester.tap(find.text('Lower'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Closest to').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    const refused =
        'Not saved: Energy needs a value from 0 to 10 to be closest to.';
    expect(find.text(refused), findsOneWidget);

    await tester.enterText(field('Value'), '12');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text(refused), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(field('Value'), '7');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, {
      'OCD': [
        ['Energy', '0', '10', 'custom', '', '7'],
      ],
    });
  });

  testWidgets('a range whose Min is not below its Max is refused', (
    tester,
  ) async {
    Map<String, List<List<String>>>? result;
    await pumpHost(tester, (context) async {
      result = await showSessionPresetsDialog(
        context,
        presets: {
          'PD': [rating('Tremor')],
        },
        defaults: _none,
        indications: const ['PD'],
      );
    });
    await tester.enterText(field('Max'), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Not saved: Tremor: Min must be below Max.'),
      findsOneWidget,
    );
    expect(result, isNull);
  });

  testWidgets('steps and targets are saved with each rating', (tester) async {
    Map<String, List<List<String>>>? result;
    await pumpHost(tester, (context) async {
      result = await showSessionPresetsDialog(
        context,
        presets: {
          'PD': [rating('Tremor', mode: 'max', step: '1'), rating('Mood')],
        },
        defaults: _none,
        indications: const ['PD'],
      );
    });

    expect(find.text('Symptom and side effect ratings'), findsOneWidget);
    await tester.tap(find.text('Any value'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Half points').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, {
      'PD': [
        ['Tremor', '0', '10', 'max', '1'],
        ['Mood', '0', '10', 'min', '0.5'],
      ],
    });
  });

  testWidgets('a deleted indication is saved empty, after asking', (
    tester,
  ) async {
    Map<String, List<List<String>>>? result;
    await pumpHost(tester, (context) async {
      result = await showSessionPresetsDialog(
        context,
        presets: {
          'A': [rating('Tremor')],
          'B': [rating('Rigidity')],
        },
        defaults: _none,
        indications: const ['A', 'B'],
      );
    });
    await tester.tap(find.byTooltip('Delete the ratings of this indication'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, {
      'B': [
        ['Rigidity', '0', '10', 'min'],
      ],
      'A': <List<String>>[],
    });
  });

  testWidgets('two manufacturers with one name are refused', (tester) async {
    Devices? result;
    await pumpHost(tester, (context) async {
      result = await showDevicesDialog(
        context,
        devices: const {
          'Mine': (leads: {}, ipgs: ['Mine X']),
        },
        defaults: const {},
      );
    });
    expect(find.text('1 IPG'), findsNothing);
    expect(find.text('0 leads, 1 IPG'), findsOneWidget);
    await tester.tap(find.text('Add manufacturer'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Manufacturer'),
      'Mine',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Not saved: two manufacturers are named Mine.'),
      findsOneWidget,
    );
    expect(result, isNull);
  });

  group('Restore defaults fills the dialog with the bundled list', () {
    Future<void> restoreAndSave(WidgetTester tester, String save) async {
      expect(find.byTooltip('Defaults in the user guide'), findsOneWidget);
      await tester.tap(find.text('Restore defaults'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(save));
      await tester.pumpAndSettle();
    }

    testWidgets('a list', (tester) async {
      List<String>? result;
      await pumpHost(tester, (context) async {
        result = await showDialog<List<String>>(
          context: context,
          builder: (_) => const ListEditorDialog(
            title: 'Programs',
            items: ['Mine'],
            defaults: ['A', 'B'],
            section: 'programs',
            addLabel: 'Add program',
          ),
        );
      });
      await restoreAndSave(tester, 'Save');
      expect(result, ['A', 'B']);
    });

    testWidgets('stimulation defaults', (tester) async {
      const limits = StimLimits(
        frequency: (min: 10, max: 200),
        amplitude: (min: 0, max: 15),
        pulseWidth: (min: 10, max: 200),
        sessionScale: (min: 0, max: 10),
        defaults: {
          'PD': [100, 2, 60],
        },
      );
      Map<String, List<num>>? result;
      await pumpHost(tester, (context) async {
        result = await showStimDefaultsDialog(
          context,
          limits: limits,
          indications: const ['PD', 'ET'],
          defaults: const {
            'PD': [130, 1.5, 60],
            'OCD': [130, 5, 90],
          },
        );
      });
      await restoreAndSave(tester, 'Save');
      expect(result, {
        'PD': [130, 1.5, 60],
        'OCD': [130, 5, 90],
      });
    });

    testWidgets('leads and IPGs', (tester) async {
      Devices? result;
      await pumpHost(tester, (context) async {
        result = await showDevicesDialog(
          context,
          devices: const {
            'Mine': (leads: {}, ipgs: ['Mine X']),
          },
          defaults: const {
            'Newronika': (leads: {}, ipgs: ['Newronika AlphaDBS']),
          },
        );
      });
      await restoreAndSave(tester, 'Save');
      expect(result!.keys, ['Newronika']);
      expect(result!['Newronika']!.ipgs, ['Newronika AlphaDBS']);
    });

    testWidgets('clinical scales and their ranges', (tester) async {
      ({Map<String, List<String>> groups, Map<String, List<String>> ranges})?
      result;
      await pumpHost(tester, (context) async {
        result = await showClinicalPresetsDialog(
          context,
          presets: const {
            'Mine': ['X'],
          },
          defaults: const ScalePresets(
            buttons: [],
            clinical: {
              'OCD': ['Y-BOCS'],
            },
            session: {},
            clinicalRanges: {'Y-BOCS': (min: '0', max: '40')},
          ),
          indications: const [],
        );
      });
      await restoreAndSave(tester, 'Save');
      expect(result!.groups, {
        'OCD': ['Y-BOCS'],
      });
      expect(result!.ranges, {
        'Y-BOCS': ['0', '40'],
      });
    });

    testWidgets('ratings', (tester) async {
      Map<String, List<List<String>>>? result;
      await pumpHost(tester, (context) async {
        result = await showSessionPresetsDialog(
          context,
          presets: const {
            'Mine': [
              (
                name: 'Tremor',
                min: '0',
                max: '10',
                mode: 'max',
                step: '',
                custom: '',
              ),
            ],
          },
          defaults: const ScalePresets(
            buttons: [],
            clinical: {},
            session: {
              'PD': [
                (
                  name: 'Rigidity R',
                  min: '0',
                  max: '4',
                  mode: 'min',
                  step: '1',
                  custom: '',
                ),
              ],
            },
          ),
          indications: const [],
        );
      });
      await restoreAndSave(tester, 'Save');
      expect(result, {
        'PD': [
          ['Rigidity R', '0', '4', 'min', '1'],
        ],
      });
    });
  });
}
