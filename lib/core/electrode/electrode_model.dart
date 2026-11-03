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

  Map<String, dynamic> toJson() => {
    'name': name,
    'num_contacts': numContacts,
    'contact_height': contactHeight,
    'contact_spacing': contactSpacing,
    'lead_diameter': leadDiameter,
    'is_directional': isDirectional,
    'tip_contact': tipContact,
    'segments_per_level': segmentsPerLevel,
    'directional_levels': directionalLevels,
    'level_directional': levelDirectional,
  };

  /// This lead with another name or contact layout; the sizes stay.
  ElectrodeModel redesigned({
    String? name,
    List<bool>? levelDirectional,
    int? segmentsPerLevel,
    bool? tipContact,
  }) {
    final levels = levelDirectional ?? this.levelDirectional;
    return ElectrodeModel(
      name: name ?? this.name,
      numContacts: levels.length,
      contactHeight: contactHeight,
      contactSpacing: contactSpacing,
      leadDiameter: leadDiameter,
      isDirectional: levels.contains(true),
      tipContact: tipContact ?? this.tipContact,
      segmentsPerLevel: segmentsPerLevel ?? this.segmentsPerLevel,
      directionalLevels: [
        for (final (i, d) in levels.indexed)
          if (d) i,
      ],
      levelDirectional: List.unmodifiable(levels),
    );
  }
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

  /// Each manufacturer's leads, with their contact layout, and IPGs.
  Devices get devices => {
    for (final maker in {...manufacturers.keys, ...ipgs.keys})
      maker: (
        leads: {
          for (final name in manufacturers[maker] ?? const <String>[])
            name: models[name]!,
        },
        ipgs: [...?ipgs[maker]],
      ),
  };

  /// This catalog offering the user's [devices]; null keeps the bundled ones.
  /// Every bundled model stays drawable, so older files keep their diagrams.
  ElectrodeCatalog withDevices(Devices? devices) => devices == null
      ? this
      : ElectrodeCatalog(
          models: {
            ...models,
            for (final d in devices.values)
              for (final MapEntry(:key, :value) in d.leads.entries)
                key: value.redesigned(name: key),
          },
          manufacturers: {
            for (final MapEntry(:key, :value) in devices.entries)
              if (value.leads.isNotEmpty) key: value.leads.keys.toList(),
          },
          ipgs: {
            for (final MapEntry(:key, :value) in devices.entries)
              if (value.ipgs.isNotEmpty) key: value.ipgs,
          },
        );
}

/// Per manufacturer: each lead's name and contact layout, and IPG names.
typedef Devices =
    Map<String, ({Map<String, ElectrodeModel> leads, List<String> ipgs})>;

/// Loads the bundled electrode catalog; tests read `schema/` via `dart:io`.
Future<ElectrodeCatalog> loadElectrodeCatalog() async {
  final raw = await rootBundle.loadString('schema/electrode_models.json');
  return ElectrodeCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
