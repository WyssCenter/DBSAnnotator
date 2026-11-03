import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Immutable description of a DBS electrode model, ported from the Python
/// `ElectrodeModel`. Instances are normally loaded from the generated
/// `schema/electrode_models.json` contract rather than hard-coded.
class ElectrodeModel {
  const ElectrodeModel({
    required this.name,
    required this.numContacts,
    required this.contactHeight,
    required this.contactSpacing,
    required this.leadDiameter,
    required this.isDirectional,
    required this.tipContact,
    required this.segmentsPerLevel,
    required this.directionalLevels,
    required this.levelDirectional,
  });

  factory ElectrodeModel.fromJson(Map<String, dynamic> json) {
    return ElectrodeModel(
      name: json['name'] as String,
      numContacts: json['num_contacts'] as int,
      contactHeight: (json['contact_height'] as num).toDouble(),
      contactSpacing: (json['contact_spacing'] as num).toDouble(),
      leadDiameter: (json['lead_diameter'] as num).toDouble(),
      isDirectional: json['is_directional'] as bool,
      tipContact: json['tip_contact'] as bool,
      segmentsPerLevel: json['segments_per_level'] as int,
      directionalLevels: (json['directional_levels'] as List?)
          ?.map((e) => e as int)
          .toList(growable: false),
      levelDirectional: (json['level_directional'] as List)
          .map((e) => e as bool)
          .toList(growable: false),
    );
  }

  final String name;

  final int numContacts;

  /// Contact height in mm.
  final double contactHeight;

  /// Spacing between contacts in mm.
  final double contactSpacing;

  /// Lead diameter in mm.
  final double leadDiameter;

  final bool isDirectional;

  /// True if the distal contact IS the tip (e.g. Boston Scientific).
  final bool tipContact;

  final int segmentsPerLevel;

  /// 0-indexed segmented levels; `null` means the Python default (all but the
  /// first and last). The resolved per-level answer is [levelDirectional].
  final List<int>? directionalLevels;

  /// Per-level directionality (length == [numContacts]), pre-computed by the
  /// schema exporter from the Python `is_level_directional()`.
  final List<bool> levelDirectional;

  bool isLevelDirectional(int levelIdx) => levelDirectional[levelIdx];
}

/// Models keyed by name plus manufacturer grouping for the UI; mirrors
/// `ELECTRODE_MODELS` and `MANUFACTURERS` in the Python config module.
class ElectrodeCatalog {
  const ElectrodeCatalog({
    required this.models,
    required this.manufacturers,
    this.ipgs = const {},
  });

  /// Parses `{manufacturers: {mfr: [names]}, models: {name: {...}}}`.
  factory ElectrodeCatalog.fromJson(Map<String, dynamic> json) {
    final modelsJson = json['models'] as Map<String, dynamic>;
    final models = <String, ElectrodeModel>{
      for (final entry in modelsJson.entries)
        entry.key: ElectrodeModel.fromJson(entry.value as Map<String, dynamic>),
    };

    Map<String, List<String>> groups(Object? raw) => {
      for (final entry in (raw as Map<String, dynamic>? ?? {}).entries)
        entry.key: (entry.value as List)
            .map((e) => e as String)
            .toList(growable: false),
    };

    return ElectrodeCatalog(
      models: models,
      manufacturers: groups(json['manufacturers']),
      ipgs: groups(json['ipgs']),
    );
  }

  final Map<String, ElectrodeModel> models;

  final Map<String, List<String>> manufacturers;

  /// Implanted pulse generator names per manufacturer, offered in Setup.
  final Map<String, List<String>> ipgs;
}

/// Loads the bundled electrode catalog; tests read `schema/` via `dart:io`.
Future<ElectrodeCatalog> loadElectrodeCatalog() async {
  final raw = await rootBundle.loadString('schema/electrode_models.json');
  return ElectrodeCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
