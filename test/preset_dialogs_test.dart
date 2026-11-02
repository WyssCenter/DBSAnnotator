import 'package:dbs_annotator/ui/scale_presets_dialog.dart';
import 'package:dbs_annotator/ui/setting_presets_dialog.dart';
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

  testWidgets('setting presets dialog sorts + de-dupes and returns lists', (
    tester,
  ) async {
    const limits = StimLimits(
      frequency: (min: 10, max: 200),
      amplitude: (min: 0, max: 15),
      pulseWidth: (min: 10, max: 200),
      sessionScale: (min: 0, max: 10),
    );
    StimPresetLists? result;
    await pumpHost(tester, (context) async {
      result = await showSettingPresetsDialog(
        context,
        limits: limits,
        frequencies: const [125, 25], // intentionally unsorted
        amplitudes: const [1.5],
        pulseWidths: const [60],
      );
    });

    expect(find.text('Edit parameter presets'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.frequencies, [25, 125]); // sorted ascending
    expect(result!.amplitudes, [1.5]);
    expect(result!.pulseWidths, [60]);
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
