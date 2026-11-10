import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/electrode/electrode_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the catalog against the contract: it MUST parse
/// schema/electrode_models.json, the committed source of truth for lead
/// geometry. Run `flutter test` from the repo root.
void main() {
  ElectrodeCatalog loadCatalog() {
    final file = File('schema/electrode_models.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'schema/*.json is a committed contract; restore it from git.',
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return ElectrodeCatalog.fromJson(json);
  }

  test('Boston Scientific Vercise Directed parses with correct geometry', () {
    final catalog = loadCatalog();
    expect(catalog.models, contains('Boston Scientific Vercise Directed'));
    final model = catalog.models['Boston Scientific Vercise Directed']!;

    expect(model.numContacts, 4);
    expect(model.contactHeight, 1.5);
    expect(model.contactSpacing, 0.5);
    expect(model.leadDiameter, 1.3);
    expect(model.isDirectional, isTrue);
    expect(model.tipContact, isTrue);
    expect(model.segmentsPerLevel, 3);
    expect(model.directionalLevels, [1, 2]);
    expect(model.levelDirectional, [false, true, true, false]);

    expect(model.isLevelDirectional(0), isFalse);
    expect(model.isLevelDirectional(1), isTrue);
    expect(model.isLevelDirectional(2), isTrue);
    expect(model.isLevelDirectional(3), isFalse);
  });

  test('non-directional model has no directional levels', () {
    final catalog = loadCatalog();
    expect(catalog.models, contains('Medtronic 3389'));
    final model = catalog.models['Medtronic 3389']!;

    expect(model.isDirectional, isFalse);
    expect(model.tipContact, isFalse);
    expect(model.segmentsPerLevel, 1);
    expect(model.directionalLevels, isNull);
    expect(model.levelDirectional, [false, false, false, false]);
  });

  test('manufacturers grouping matches the desktop app', () {
    final catalog = loadCatalog();
    expect(catalog.manufacturers.keys.toSet(), {
      'Medtronic',
      'Boston Scientific',
      'Abbott',
      'PINS Medical',
      'ALEVA',
    });
    expect(
      catalog.manufacturers['Boston Scientific'],
      contains('Boston Scientific Vercise Directed'),
    );

    // Every model listed under a manufacturer resolves in the catalog.
    for (final names in catalog.manufacturers.values) {
      for (final name in names) {
        expect(catalog.models, contains(name));
      }
    }
  });
  test('every lead manufacturer offers IPGs too', () {
    final catalog = loadCatalog();
    expect(catalog.ipgs.keys, containsAll(catalog.manufacturers.keys));
  });

  test("the user's devices are offered per manufacturer", () {
    final bundled = loadCatalog();
    final m3389 = bundled.models['Medtronic 3389']!;
    final designed = m3389.redesigned(
      levelDirectional: [false, true, true, true, false],
      tipContact: true,
    );
    final catalog = bundled.withDevices({
      'Medtronic': (
        leads: {'Medtronic 3389': m3389},
        ipgs: ['Medtronic Percept RC'],
      ),
      'Newronika': (leads: {'Newronika Lead A': designed}, ipgs: const []),
    });
    expect(catalog.manufacturers, {
      'Medtronic': ['Medtronic 3389'],
      'Newronika': ['Newronika Lead A'],
    });
    expect(catalog.ipgs, {
      'Medtronic': ['Medtronic Percept RC'],
    });
    final lead = catalog.models['Newronika Lead A']!;
    expect(lead.name, 'Newronika Lead A');
    expect(lead.numContacts, 5);
    expect(lead.directionalLevels, [1, 2, 3]);
    expect(lead.isDirectional, isTrue);
    expect(lead.tipContact, isTrue);
    expect(lead.contactHeight, m3389.contactHeight);
    // A design survives the saved settings.
    final back = ElectrodeModel.fromJson(lead.toJson());
    expect(back.levelDirectional, lead.levelDirectional);
    // A hidden lead still draws, so older files keep their diagrams.
    expect(catalog.models, contains('Medtronic 3387'));
    // The bundled devices round-trip unchanged.
    final again = bundled.withDevices(bundled.devices);
    expect(again.manufacturers, bundled.manufacturers);
    expect(again.ipgs, bundled.ipgs);
    expect(bundled.withDevices(null), same(bundled));
  });
}
