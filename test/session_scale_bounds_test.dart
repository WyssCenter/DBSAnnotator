import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:dbs_annotator/ui/stim_params_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  final catalog = ElectrodeCatalog.fromJson(
    readJson('schema/electrode_models.json'),
  );
  final limits = StimLimits.fromJson(readJson('schema/limits.json'));
  final bundled = ScalePresets.fromJson(readJson('schema/scale_presets.json'));

  /// The first rating saved for a PD session whose one rating has the range
  /// [min] to [max], as typed in the session ratings settings.
  Future<String> firstScaleValue(
    WidgetTester tester, {
    required String min,
    required String max,
  }) async {
    final presets = ScalePresets(
      buttons: bundled.buttons,
      clinical: bundled.clinical,
      clinicalRanges: bundled.clinicalRanges,
      pathologies: bundled.pathologies,
      targets: bundled.targets,
      session: {
        ...bundled.session,
        'PD': [(name: 'Tremor', min: min, max: max, mode: 'min', step: '')],
      },
    );
    final authoring = SessionAuthoring();
    await tester.binding.setSurfaceSize(const Size(1400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: SessionScreen(
          catalog: catalog,
          limits: limits,
          scalePresets: presets,
          authoring: authoring,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(
      find.widgetWithText(DropdownMenu<String>, 'DBS indication'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('PD').last);
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    final save = find.text('Save configuration');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    expect(tester.takeException(), isNull);
    return authoring.rows
        .firstWhere((r) => r.isInitial == '0' && r.scaleName == 'Tremor')
        .scaleValue;
  }

  testWidgets('a rating is held inside the typed range', (tester) async {
    expect(await firstScaleValue(tester, min: '2', max: '5'), '2');
  });

  testWidgets('a decimal comma is read as a decimal point', (tester) async {
    expect(await firstScaleValue(tester, min: '1,5', max: '4,5'), '1.5');
  });

  testWidgets('NaN and Infinity fall back to the contract range', (
    tester,
  ) async {
    final value = await firstScaleValue(tester, min: 'NaN', max: 'Infinity');
    expect(double.parse(value).isFinite, isTrue);
  });
}
