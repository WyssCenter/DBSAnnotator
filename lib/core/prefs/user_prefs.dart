import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../electrode/electrode_model.dart';
import '../safe_file.dart';
import '../session/scale_presets.dart';

/// Per-user preset overrides, persisted as JSON in the app-support directory
/// and layered over the bundled contract defaults.
///
/// Any field left null means "use the bundled default"; the UI merges with
/// `?? <default>`.
/// A BIDS folder sessions are saved in, under the name shown in Setup.
typedef BidsFolder = ({String name, String path});

class UserPrefs {
  UserPrefs({
    this.stimDefaults,
    this.programs,
    this.clinical,
    this.clinicalRanges,
    this.session,
    this.reportPageSize,
    this.entryPanelOrder,
    this.entryVisibleConfigs,
    this.entryTableExpanded,
    this.entryChartsExpanded,
    this.reportSections,
    this.bidsFolders,
    this.defaultBidsFolder,
    this.darkTheme,
    this.textScale,
    this.pathologies,
    this.targets,
    this.devices,
  });

  /// DBS indication -> [frequency, amplitude, pulse width] to start from,
  /// overriding `limits.json` stimulation_defaults.
  Map<String, List<num>>? stimDefaults;

  /// Program names (override the default None/A/B/C/D).
  List<String>? programs;

  /// Clinical scale presets: group name -> scale names.
  Map<String, List<String>>? clinical;

  /// Clinical scale name -> [min, max], the declared ranges as edited.
  Map<String, List<String>>? clinicalRanges;

  /// Session scale presets: group name -> [name, min, max] rows.
  Map<String, List<List<String>>>? session;

  /// Paper size for exported reports, 'a4' or 'letter', applied to both the
  /// PDF and the Word document so the two always match.
  String? reportPageSize;

  /// Top-to-bottom order of the entry-review chart panels, by panel id,
  /// persisted so a clinician's arrangement survives closing the app.
  List<String>? entryPanelOrder;

  /// How many configurations fill the entry-review chart viewport (the zoom).
  int? entryVisibleConfigs;

  /// Whether the inserted-entries table below the charts is expanded.
  bool? entryTableExpanded;

  /// Whether the comparison charts in Programming are expanded.
  bool? entryChartsExpanded;

  /// The BIDS folders sessions are saved in, for example one per cohort.
  List<BidsFolder>? bidsFolders;

  /// The [bidsFolders] name Setup starts on.
  String? defaultBidsFolder;

  /// The appearance chosen in the side menu; null means light and 1.0.
  bool? darkTheme;
  double? textScale;

  /// The folder Setup starts on: the default one, else the first.
  BidsFolder? get startFolder {
    final all = bidsFolders ?? const <BidsFolder>[];
    return all.where((f) => f.name == defaultBidsFolder).firstOrNull ??
        all.firstOrNull;
  }

  /// The Setup indication and target lists as edited; null means the
  /// defaults.
  List<String>? pathologies;
  List<String>? targets;

  /// The leads and IPGs offered in Setup; null means the bundled ones.
  Devices? devices;

  /// Report sections to include, by [ReportSection.name]; null means every
  /// section. Persisted so a dropped section stays dropped on the next export.
  List<String>? reportSections;

  factory UserPrefs.fromJson(Map<String, dynamic> j) {
    return UserPrefs(
      stimDefaults: (j['stim_defaults'] as Map?)?.map(
        (k, v) => MapEntry(k as String, (v as List).cast<num>().toList()),
      ),
      programs: (j['programs'] as List?)?.map((e) => e as String).toList(),
      clinical: (j['clinical'] as Map?)?.map(
        (k, v) =>
            MapEntry(k as String, (v as List).map((e) => e as String).toList()),
      ),
      clinicalRanges: (j['clinical_ranges'] as Map?)?.map(
        (k, v) =>
            MapEntry(k as String, (v as List).map((e) => e as String).toList()),
      ),
      session: (j['session'] as Map?)?.map(
        (k, v) => MapEntry(
          k as String,
          (v as List)
              .map((r) => (r as List).map((e) => e as String).toList())
              .toList(),
        ),
      ),
      reportPageSize: j['report_page_size'] as String?,
      entryPanelOrder: (j['entry_panel_order'] as List?)
          ?.map((e) => e as String)
          .toList(),
      entryVisibleConfigs: (j['entry_visible_configs'] as num?)?.toInt(),
      entryTableExpanded: j['entry_table_expanded'] as bool?,
      entryChartsExpanded: j['entry_charts_expanded'] as bool?,
      bidsFolders: switch (j['bids_folders']) {
        final List<dynamic> list => [
          for (final f in list.cast<Map<String, dynamic>>())
            (name: f['name'] as String, path: f['path'] as String),
        ],
        _ => switch (j['save_folder']) {
          final String path => [(name: 'Default', path: path)],
          _ => null,
        },
      },
      defaultBidsFolder: j['default_bids_folder'] as String?,
      darkTheme: j['dark_theme'] as bool?,
      textScale: (j['text_scale'] as num?)?.toDouble(),
      pathologies: (j['pathologies'] as List?)?.cast<String>(),
      targets: (j['targets'] as List?)?.cast<String>(),
      devices: (j['devices'] as Map?)?.map(
        (k, v) => MapEntry(k as String, (
          leads: ((v as Map)['leads'] as Map).map(
            (name, json) => MapEntry(
              name as String,
              ElectrodeModel.fromJson(json as Map<String, dynamic>),
            ),
          ),
          ipgs: (v['ipgs'] as List).cast<String>(),
        )),
      ),
      reportSections: (j['report_sections'] as List?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (stimDefaults != null) 'stim_defaults': stimDefaults,
    if (programs != null) 'programs': programs,
    if (clinical != null) 'clinical': clinical,
    if (clinicalRanges != null) 'clinical_ranges': clinicalRanges,
    if (session != null) 'session': session,
    if (reportPageSize != null) 'report_page_size': reportPageSize,
    if (entryPanelOrder != null) 'entry_panel_order': entryPanelOrder,
    if (entryVisibleConfigs != null)
      'entry_visible_configs': entryVisibleConfigs,
    if (entryTableExpanded != null) 'entry_table_expanded': entryTableExpanded,
    if (entryChartsExpanded != null)
      'entry_charts_expanded': entryChartsExpanded,
    if (reportSections != null) 'report_sections': reportSections,
    if (bidsFolders case final folders?)
      'bids_folders': [
        for (final f in folders) {'name': f.name, 'path': f.path},
      ],
    if (defaultBidsFolder != null) 'default_bids_folder': defaultBidsFolder,
    if (darkTheme != null) 'dark_theme': darkTheme,
    if (textScale != null) 'text_scale': textScale,
    if (pathologies != null) 'pathologies': pathologies,
    if (targets != null) 'targets': targets,
    if (devices case final d?)
      'devices': {
        for (final MapEntry(:key, :value) in d.entries)
          key: {
            'leads': {
              for (final l in value.leads.entries) l.key: l.value.toJson(),
            },
            'ipgs': value.ipgs,
          },
      },
  };
}

/// Default report paper size: A4 rather than the desktop's US Letter, which is
/// only python-docx's default. [UserPrefs.reportPageSize] overrides it.
const String kDefaultReportPageSize = 'a4';

/// The paper sizes the report exporters accept.
const List<String> kReportPageSizes = ['a4', 'letter'];

/// Default program names (desktop `ProgramConfigManager.DEFAULT_PROGRAMS`).
const List<String> kDefaultPrograms = ['None', 'A', 'B', 'C', 'D'];

/// Bundled [base] scale presets with the user's saved overrides layered on
/// top: an edited or added disease group wins over the contract default, and a
/// new group name is appended to the button bar.
ScalePresets mergeScalePresets(ScalePresets base, UserPrefs prefs) {
  final clinical = {...base.clinical};
  prefs.clinical?.forEach((k, v) => clinical[k] = v);
  // Saved ranges replace the bundled ones wholesale: a range the user cleared
  // must stay cleared rather than reappear from the contract.
  final clinicalRanges = prefs.clinicalRanges == null
      ? base.clinicalRanges
      : {
          for (final e in prefs.clinicalRanges!.entries)
            if (e.value.length == 2) e.key: (min: e.value[0], max: e.value[1]),
        };
  final session = {...base.session};
  prefs.session?.forEach(
    (k, rows) => session[k] = [
      for (final r in rows)
        (
          name: r.isNotEmpty ? r[0] : '',
          min: r.length > 1 ? r[1] : '0',
          max: r.length > 2 ? r[2] : '10',
          // Rows saved before the optimization mode existed fall back.
          mode:
              r.length > 3 &&
                  scaleOptimizationModes.contains(r[3].trim().toLowerCase())
              ? r[3].trim().toLowerCase()
              : defaultScaleOptimizationMode,
          step: r.length > 4 ? r[4] : '',
        ),
    ],
  );
  final buttons = [
    ...base.buttons,
    for (final k in {...clinical.keys, ...session.keys})
      if (!base.buttons.contains(k)) k,
  ];
  return ScalePresets(
    buttons: buttons,
    clinical: clinical,
    session: session,
    clinicalRanges: clinicalRanges,
    pathologies: base.pathologies,
    targets: base.targets,
  );
}

/// Overrides where preferences live, so tests never touch the user's own.
Directory? debugPrefsDir;

Future<File> _prefsFile() async {
  final dir = debugPrefsDir ?? await getApplicationSupportDirectory();
  return File('${dir.path}/dbs_user_prefs.json');
}

/// Load overrides, or empty prefs when absent/unreadable.
Future<UserPrefs> loadUserPrefs() async {
  try {
    final f = await _prefsFile();
    if (!await f.exists()) return UserPrefs();
    return UserPrefs.fromJson(
      jsonDecode(await f.readAsString()) as Map<String, dynamic>,
    );
  } catch (_) {
    return UserPrefs();
  }
}

final _prefsWriter = SafeFileWriter();

/// Persist overrides so edits survive relaunch.
Future<void> saveUserPrefs(UserPrefs prefs) async {
  final f = await _prefsFile();
  await _prefsWriter.write(f.path, jsonEncode(prefs.toJson()));
}
