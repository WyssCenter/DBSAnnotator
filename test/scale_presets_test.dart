import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/session/scale_presets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the presets against the contract: they MUST parse
/// schema/scale_presets.json, the committed source of truth for the
/// bundled scale sets. Run `flutter test` from the repo root.
void main() {
  ScalePresets loadPresets() {
    final file = File('schema/scale_presets.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'schema/*.json is a committed contract; restore it from git.',
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return ScalePresets.fromJson(json);
  }

  test('button bar carries the six desktop disease presets, in order', () {
    final p = loadPresets();
    expect(p.buttons, ['OCD', 'MDD', 'PD', 'ET', 'Dystonia', 'TS']);

    // Every button resolves in both tables (no dangling pill).
    for (final name in p.buttons) {
      expect(p.clinical, contains(name));
      expect(p.session, contains(name));
    }
  });

  test('clinicalRows returns the desktop Step-1 scale names', () {
    final p = loadPresets();
    final ocd = clinicalRows(p, 'OCD');
    expect(ocd, contains('Y-BOCS'));
    expect(ocd, ['Y-BOCS', 'Y-BOCS-o', 'Y-BOCS-c', 'MADRS', 'OCI-R']);
    expect(clinicalRows(p, 'MDD'), ['MADRS', 'HAM-D']);
  });

  test('no licensed scale is bundled, nor named in a rating', () {
    final p = loadPresets();
    expect(clinicalRows(p, 'PD'), ['CGI-S']);
    final names = [
      ...p.clinicalRanges.keys,
      for (final g in p.buttons) ...clinicalRows(p, g),
      for (final g in p.buttons) ...sessionRows(p, g).map((r) => r.name),
    ];
    for (final licensed in ['UPDRS', 'UDysRS', 'PDQ-39', 'BDI']) {
      expect(names.where((n) => n.contains(licensed)), isEmpty);
    }
  });

  test('PD rates ten motor items 0 to 4 in whole steps', () {
    final p = loadPresets();
    final pd = sessionRows(p, 'PD');
    final items = pd.where((r) => r.max == '4');
    expect(pd.first, (
      name: 'Rigidity, right arm',
      min: '0',
      max: '4',
      mode: 'min',
      step: '1',
    ));
    expect(items, hasLength(10));
    for (final row in items) {
      expect((row.min, row.max, row.step), ('0', '4', '1'));
    }
    final others = pd.where((r) => !items.contains(r));
    expect(others.map((r) => r.name), ['Dyskinesia', 'Paresthesia']);
    for (final row in pd) {
      expect(scaleOptimizationModes, contains(row.mode));
    }
  });

  test('other presets keep continuous 0 to 10 rows', () {
    final p = loadPresets();
    for (final group in ['OCD', 'MDD', 'ET', 'Dystonia', 'TS']) {
      for (final row in sessionRows(p, group)) {
        expect((row.min, row.max, row.step), ('0', '10', ''));
      }
    }
  });

  test('a preset row without a mode cell falls back to the default', () {
    // Contracts generated before optimization_mode existed carry 3 cells.
    final p = ScalePresets.fromJson({
      'buttons': ['X'],
      'clinical': {'X': <String>[]},
      'session': {
        'X': [
          ['Legacy', '0', '7'],
        ],
      },
    });
    expect(sessionRows(p, 'X').single, (
      name: 'Legacy',
      min: '0',
      max: '7',
      mode: defaultScaleOptimizationMode,
      step: '',
    ));
  });

  test('an unrecognised mode cell falls back to the default', () {
    final p = ScalePresets.fromJson({
      'buttons': ['X'],
      'clinical': {'X': <String>[]},
      'session': {
        'X': [
          ['Odd', '0', '7', 'sideways'],
        ],
      },
    });
    expect(sessionRows(p, 'X').single.mode, defaultScaleOptimizationMode);
  });

  test('unknown presets return empty lists (never throw)', () {
    final p = loadPresets();
    expect(clinicalRows(p, 'nope'), isEmpty);
    expect(sessionRows(p, 'nope'), isEmpty);
  });
}
