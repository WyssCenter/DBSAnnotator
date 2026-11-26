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
    expect(p.buttons, [
      'Obsessive-compulsive disorder',
      'Major depressive disorder',
      "Parkinson's disease",
      'Essential tremor',
      'Dystonia',
      'Tourette syndrome',
    ]);

    // Every button resolves in both tables (no dangling pill).
    for (final name in p.buttons) {
      expect(p.clinical, contains(name));
      expect(p.session, contains(name));
    }
  });

  test('clinicalRows returns the desktop Step-1 scale names', () {
    final p = loadPresets();
    final ocd = clinicalRows(p, 'Obsessive-compulsive disorder');
    expect(ocd, contains('Y-BOCS'));
    expect(ocd, ['Y-BOCS', 'Y-BOCS-o', 'Y-BOCS-c', 'MADRS', 'OCI-R']);
    expect(clinicalRows(p, 'Major depressive disorder'), ['MADRS', 'HAM-D']);
  });

  test('no licensed scale is bundled, nor named in a rating', () {
    final p = loadPresets();
    expect(clinicalRows(p, "Parkinson's disease"), ['UPDRS', 'CGI-S']);
    expect(p.clinicalRanges, isNot(contains('UPDRS')));
    final names = [
      ...p.clinicalRanges.keys,
      for (final g in p.buttons) ...clinicalRows(p, g),
      for (final g in p.buttons) ...sessionRows(p, g).map((r) => r.name),
    ];
    for (final licensed in ['MDS-UPDRS', 'UDysRS', 'PDQ-39', 'BDI']) {
      expect(names.where((n) => n.contains(licensed)), isEmpty);
    }
  });

  test('PD rates eight items 0 to 4 in whole steps', () {
    final p = loadPresets();
    final pd = sessionRows(p, "Parkinson's disease");
    expect(pd.map((r) => r.name), [
      'Finger tapping R',
      'Finger tapping L',
      'Rigidity R',
      'Rigidity L',
      'Rest tremor amplitude R',
      'Rest tremor amplitude L',
      'Dyskinesia',
      'Paresthesia',
    ]);
    for (final row in pd) {
      expect((row.min, row.max, row.mode, row.step), ('0', '4', 'min', '1'));
    }
  });

  test('other presets keep continuous 0 to 10 rows', () {
    final p = loadPresets();
    for (final group in [
      'Obsessive-compulsive disorder',
      'Major depressive disorder',
      'Essential tremor',
      'Dystonia',
      'Tourette syndrome',
    ]) {
      for (final row in sessionRows(p, group)) {
        expect((row.min, row.max, row.step), ('0', '10', ''));
      }
    }
  });

  test('mood and energy are best closest to 7', () {
    final p = loadPresets();
    for (final group in [
      'Obsessive-compulsive disorder',
      'Major depressive disorder',
    ]) {
      final rows = {for (final r in sessionRows(p, group)) r.name: r};
      for (final name in ['Mood', 'Energy']) {
        expect((rows[name]!.mode, rows[name]!.custom), ('custom', '7'));
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
      custom: '',
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
