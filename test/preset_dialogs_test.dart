import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/ui/devices_dialog.dart';
import 'package:dbs_annotator/ui/scale_presets_dialog.dart';
import 'package:dbs_annotator/ui/stim_defaults_dialog.dart';
import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
      );
    });

    expect(find.text('Default settings per DBS indication'), findsOneWidget);
    final etFrequency = find.widgetWithText(TextField, 'Frequency').at(1);
    await tester.enterText(etFrequency, '500');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.textContaining('ET: Frequency must be 10-200'), findsOneWidget);

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
    await tester.tap(find.byTooltip('More levels'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'E4'));
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

  testWidgets('clinical presets dialog returns names and their ranges', (
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
      );
    });

    expect(find.text('Clinical scales settings'), findsOneWidget);
    // 'OCD' appears twice (group tile + selected editor's name field), so we
    // just verify the returned map below.
    await tester.tap(find.text('Save & Close'));
    await tester.pumpAndSettle();

    expect(result!.groups, {
      'OCD': ['Y-BOCS', 'MADRS'],
    });
    // MADRS had no range, so none is invented for it.
    expect(result!.ranges, {
      'Y-BOCS': ['0', '40'],
    });
  });

  testWidgets('session presets dialog preserves [name,min,max,mode] on save', (
    tester,
  ) async {
    Map<String, List<List<String>>>? result;
    await pumpHost(tester, (context) async {
      result = await showSessionPresetsDialog(
        context,
        presets: const {
          'PD': [
            (name: 'Tremor', min: '0', max: '10', mode: 'max', step: '1'),
            (name: 'Mood', min: '0', max: '10', mode: 'min', step: ''),
          ],
        },
      );
    });

    expect(find.text('Session scales settings'), findsOneWidget);
    await tester.tap(find.text('Save & Close'));
    await tester.pumpAndSettle();

    // The hidden optimization mode and rating step are carried through.
    expect(result, {
      'PD': [
        ['Tremor', '0', '10', 'max', '1'],
        ['Mood', '0', '10', 'min'],
      ],
    });
  });
}
