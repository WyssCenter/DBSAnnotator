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
  final scalePresets = ScalePresets.fromJson(
    readJson('schema/scale_presets.json'),
  );

  Future<String> firstScaleValue(
    WidgetTester tester, {
    required String min,
    required String max,
  }) async {
    final authoring = SessionAuthoring();
    await tester.binding.setSurfaceSize(const Size(1400, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: SessionScreen(
          catalog: catalog,
          limits: limits,
          scalePresets: scalePresets,
          authoring: authoring,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'PD'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'PD'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Min').first, min);
    await tester.enterText(find.widgetWithText(TextField, 'Max').first, max);
    await tester.ensureVisible(find.text('Recording'));
    await tester.tap(find.text('Recording'));
    await tester.pumpAndSettle();
    final insert = find.text('Insert recording block');
    await tester.ensureVisible(insert);
    await tester.tap(insert);
    await tester.pump();
    expect(tester.takeException(), isNull);
    return authoring.rows.first.scaleValue;
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
