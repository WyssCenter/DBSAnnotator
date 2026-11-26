import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../core/session/scale_presets.dart';
import '../core/session/scale_scoring.dart';
import 'scale_targets_dialog.dart';

/// Shown under the table of both scale dialogs.
const String kScaleLicenceNotice =
    'You can add other scales. Some, such as the MDS-UPDRS, need a licence '
    'from their owner: you are responsible for the scales you use.';

/// Edit the clinical scales offered per DBS indication and each scale's range,
/// which only sets the clinical figure's axis and may be left blank. The
/// dialog opens on [initial]; Add indication offers the [indications] without
/// scales yet; Restore defaults puts back those of [defaults]. Returns the
/// scales per indication and the ranges on Save, or null on Cancel.
Future<({Map<String, List<String>> groups, Map<String, List<String>> ranges})?>
showClinicalPresetsDialog(
  BuildContext context, {
  required Map<String, List<String>> presets,
  Map<String, ScaleRange> ranges = const {},
  required ScalePresets defaults,
  required List<String> indications,
  String? initial,
}) async {
  List<_Group> groups(
    Map<String, List<String>> presets,
    Map<String, ScaleRange> ranges,
  ) => [
    for (final e in presets.entries)
      _Group(e.key, [
        for (final n in e.value)
          _ScaleRow(
            name: n,
            min: ranges[n]?.min ?? '',
            max: ranges[n]?.max ?? '',
          ),
      ]),
  ];
  final out = await showDialog<Map<String, List<List<String>>>>(
    context: context,
    builder: (_) => _ScalePresetsDialog(
      title: 'Clinical scales',
      section: 'clinical-scales',
      isSession: false,
      groups: groups(presets, ranges),
      defaults: () => groups(defaults.clinical, defaults.clinicalRanges),
      indications: indications,
      initial: initial,
    ),
  );
  if (out == null) return null;
  return (
    groups: {
      for (final e in out.entries) e.key: [for (final r in e.value) r[0]],
    },
    ranges: {
      for (final rows in out.values)
        for (final r in rows)
          if (r[1].isNotEmpty && r[2].isNotEmpty) r[0]: [r[1], r[2]],
    },
  );
}

/// Edit the symptom and side effect ratings offered per DBS indication: each
/// rating's range, steps and target. Opens on [initial]; Add indication offers
/// the [indications] without ratings yet; Restore defaults puts back those of
/// [defaults]. Returns `{indication: [[name,min,max,mode,step,custom], …]}` on
/// Save, trailing empty cells dropped, else null.
Future<Map<String, List<List<String>>>?> showSessionPresetsDialog(
  BuildContext context, {
  required Map<String, List<SessionScaleRow>> presets,
  required ScalePresets defaults,
  required List<String> indications,
  String? initial,
}) {
  List<_Group> groups(Map<String, List<SessionScaleRow>> presets) => [
    for (final e in presets.entries)
      _Group(e.key, [
        for (final r in e.value)
          _ScaleRow(
            name: r.name,
            min: r.min,
            max: r.max,
            mode: r.mode,
            step: r.step,
            custom: r.custom,
          ),
      ]),
  ];
  return showDialog<Map<String, List<List<String>>>>(
    context: context,
    builder: (_) => _ScalePresetsDialog(
      title: 'Symptom and side effect ratings',
      section: 'symptom-and-side-effect-ratings',
      isSession: true,
      groups: groups(presets),
      defaults: () => groups(defaults.session),
      indications: indications,
      initial: initial,
    ),
  );
}

/// The steps a rating moves in, by its step cell.
const Map<String, String> _steps = {
  '1': 'Whole points',
  '0.5': 'Half points',
  '': 'Any value',
};

/// Widths of the session-only columns, before text scaling.
const double _stepsWidth = 136;
const double _removeWidth = 48;

/// One editable scale row. Only session rows use the target ([mode] and
/// [custom]) and the [step].
class _ScaleRow {
  _ScaleRow({
    String name = '',
    String min = '0',
    String max = '10',
    this.mode = defaultScaleOptimizationMode,
    this.step = '',
    String custom = '',
  }) {
    this.name.text = name;
    this.min.text = min;
    this.max.text = max;
    this.custom.text = custom;
  }

  final name = TextEditingController();
  final min = TextEditingController();
  final max = TextEditingController();
  final custom = TextEditingController();
  String mode;
  String step;

  void dispose() {
    name.dispose();
    min.dispose();
    max.dispose();
    custom.dispose();
  }
}

/// The scales of one DBS indication.
class _Group {
  _Group(this.indication, this.rows);

  final String indication;
  final List<_ScaleRow> rows;

  void dispose() {
    for (final r in rows) {
      r.dispose();
    }
  }
}

class _ScalePresetsDialog extends StatefulWidget {
  const _ScalePresetsDialog({
    required this.title,
    required this.section,
    required this.isSession,
    required this.groups,
    required this.defaults,
    required this.indications,
    this.initial,
  });

  final String title;
  final String section;
  final bool isSession;
  final List<_Group> groups;

  /// Fresh groups of the scales the app comes with.
  final List<_Group> Function() defaults;

  final List<String> indications;
  final String? initial;

  @override
  State<_ScalePresetsDialog> createState() => _ScalePresetsDialogState();
}

class _ScalePresetsDialogState extends State<_ScalePresetsDialog> {
  late final List<_Group> _groups = widget.groups;
  late int _selected = _groups.isEmpty
      ? -1
      : _groups
            .indexWhere((g) => g.indication == widget.initial)
            .clamp(0, _groups.length - 1);
  String? _error;

  /// Indications deleted here, saved as empty so they stay deleted.
  final _deleted = <String>{};

  String get _noun => widget.isSession ? 'rating' : 'scale';

  @override
  void dispose() {
    for (final g in _groups) {
      g.dispose();
    }
    super.dispose();
  }

  /// The indications that have no scales here yet.
  List<String> get _available => [
    for (final i in widget.indications)
      if (!_groups.any((g) => g.indication == i)) i,
  ];

  void _addGroup(String indication) => setState(() {
    _deleted.remove(indication);
    _groups.add(_Group(indication, [_newRow()]));
    _selected = _groups.length - 1;
  });

  /// A new row: 0 to 10 for a session scale, no range for a clinical one.
  _ScaleRow _newRow() =>
      widget.isSession ? _ScaleRow() : _ScaleRow(min: '', max: '');

  void _restore() => setState(() {
    final shown = _selected < 0 ? null : _groups[_selected].indication;
    for (final g in _groups) {
      g.dispose();
    }
    _groups
      ..clear()
      ..addAll(widget.defaults());
    _deleted.clear();
    _selected = _groups.isEmpty
        ? -1
        : _groups
              .indexWhere((g) => g.indication == shown)
              .clamp(0, _groups.length - 1);
    _error = null;
  });

  Future<void> _deleteGroup() async {
    final g = _groups[_selected];
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete the ${_noun}s of ${g.indication}?'),
        content: Text(
          'New sessions for ${g.indication} then start without ${_noun}s. '
          'Saved sessions are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      _deleted.add(g.indication);
      _groups.removeAt(_selected).dispose();
      _selected = _groups.isEmpty ? -1 : _selected.clamp(0, _groups.length - 1);
    });
  }

  /// Why [r] cannot be saved, or null.
  String? _problem(_ScaleRow r, String name) {
    final lo = r.min.text.trim();
    final hi = r.max.text.trim();
    if (!widget.isSession && lo.isEmpty && hi.isEmpty) return null;
    final (low, high) = (double.tryParse(lo), double.tryParse(hi));
    if (low == null || high == null) {
      return '$name needs a number for Min and for Max.';
    }
    if (low >= high) return '$name: Min must be below Max.';
    if (widget.isSession && r.mode == ScaleMode.custom.name) {
      final v = double.tryParse(r.custom.text.trim());
      if (v == null || v < low || v > high) {
        return '$name needs a value from $lo to $hi to be closest to.';
      }
    }
    return null;
  }

  void _save() {
    final out = <String, List<List<String>>>{};
    for (final g in _groups) {
      final rows = <List<String>>[];
      for (final r in g.rows) {
        final n = r.name.text.trim();
        if (n.isEmpty) continue;
        if (_problem(r, n) case final problem?) {
          setState(() {
            _selected = _groups.indexOf(g);
            _error = 'Not saved: $problem';
          });
          return;
        }
        final custom = r.mode == ScaleMode.custom.name
            ? r.custom.text.trim()
            : '';
        rows.add(
          widget.isSession
              ? [
                  n,
                  r.min.text.trim(),
                  r.max.text.trim(),
                  r.mode,
                  if (r.step.isNotEmpty || custom.isNotEmpty) r.step,
                  if (custom.isNotEmpty) custom,
                ]
              : [n, r.min.text.trim(), r.max.text.trim()],
        );
      }
      out[g.indication] = rows;
    }
    for (final d in _deleted) {
      out.putIfAbsent(d, () => []);
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    final screen = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: DefaultsTitle(widget.title, section: widget.section),
      constraints: const BoxConstraints(),
      content: SizedBox(
        width: min(widget.isSession ? 920 : 640, screen.width - 112),
        height: min(560, screen.height - 240),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _indicationBar(),
            const SizedBox(height: 12),
            Expanded(
              child: _selected < 0
                  ? Center(
                      child: Text(
                        'No indication has ${_noun}s yet. Add one with Add '
                        'indication.',
                      ),
                    )
                  : _table(_groups[_selected]),
            ),
            Text(
              widget.isSession
                  ? 'The defaults for new sessions. Saving also updates the '
                        "open session's ratings. $kScaleLicenceNotice"
                  : 'The range only sets the axis of the clinical figure and '
                        'may be left empty. $kScaleLicenceNotice',
              style: theme.textTheme.bodySmall,
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: picklistActions(context, onRestore: _restore, onSave: _save),
    );
  }

  /// The indication shown, with Delete, and Add indication.
  Widget _indicationBar() {
    final available = _available;
    return Row(
      children: [
        if (_groups.isNotEmpty) ...[
          DropdownMenu<int>(
            key: ValueKey('$_selected/${_groups.length}'),
            width: scaledWidth(context, 340),
            label: const Text('DBS indication'),
            initialSelection: _selected,
            requestFocusOnTap: false,
            dropdownMenuEntries: [
              for (final (i, g) in _groups.indexed)
                DropdownMenuEntry(
                  value: i,
                  label: '${g.indication} (${g.rows.length})',
                ),
            ],
            onSelected: (i) => setState(() {
              _selected = i ?? _selected;
              _error = null;
            }),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete the ${_noun}s of this indication',
            onPressed: _deleteGroup,
          ),
        ],
        const Spacer(),
        MenuAnchor(
          menuChildren: [
            for (final i in available)
              MenuItemButton(onPressed: () => _addGroup(i), child: Text(i)),
          ],
          builder: (context, menu, _) => TextButton.icon(
            onPressed: available.isEmpty
                ? null
                : () => menu.isOpen ? menu.close() : menu.open(),
            icon: const Icon(Icons.add),
            label: const Text('Add indication'),
          ),
        ),
      ],
    );
  }

  /// The scales of [g] under one header, one line each, or two lines each
  /// when the window is too narrow for the columns.
  Widget _table(_Group g) => LayoutBuilder(
    builder: (context, box) {
      final columns = [
        ('Min', kRangeWidth),
        ('Max', kRangeWidth),
        if (widget.isSession) ...[
          ('Steps', _stepsWidth),
          ('Better when', kTargetWidth),
          ('Value', kValueWidth),
        ],
      ];
      final fixed = columns.fold(0.0, (w, c) => w + 8 + c.$2);
      final wide =
          !widget.isSession ||
          box.maxWidth - scaledWidth(context, fixed) - _removeWidth >= 160;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            tableHeader(
              context,
              widget.isSession ? 'Rating' : 'Scale',
              columns,
              trailing: _removeWidth,
            ),
          Expanded(
            child: ListView.builder(
              itemCount: g.rows.length,
              itemBuilder: (_, i) =>
                  wide ? _line(g.rows[i], g) : _twoLines(g.rows[i], g),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => g.rows.add(_newRow())),
              icon: const Icon(Icons.add),
              label: Text('Add $_noun'),
            ),
          ),
        ],
      );
    },
  );

  Widget _name(_ScaleRow r, {bool labelled = false}) => Semantics(
    label: widget.isSession ? 'Rating' : 'Scale',
    child: TextField(
      controller: r.name,
      decoration: InputDecoration(
        labelText: labelled ? (widget.isSession ? 'Rating' : 'Scale') : null,
        isDense: true,
      ),
    ),
  );

  Widget _remove(_ScaleRow r, _Group g) => SizedBox(
    width: _removeWidth,
    child: IconButton(
      icon: const Icon(Icons.remove_circle_outline),
      tooltip: 'Remove $_noun',
      onPressed: () => setState(() {
        g.rows.remove(r);
        r.dispose();
      }),
    ),
  );

  Widget _stepsField(_ScaleRow r, {bool labelled = false}) => SizedBox(
    width: scaledWidth(context, _stepsWidth),
    child: Semantics(
      label: 'Steps',
      child: DropdownButtonFormField<String>(
        key: ValueKey(r.step),
        initialValue: r.step,
        isDense: true,
        isExpanded: true,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          labelText: labelled ? 'Steps' : null,
          isDense: true,
        ),
        items: [
          for (final MapEntry(:key, :value) in {
            ..._steps,
            if (!_steps.containsKey(r.step)) r.step: 'Steps of ${r.step}',
          }.entries)
            DropdownMenuItem(
              value: key,
              child: Text(value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => r.step = v ?? r.step),
      ),
    ),
  );

  TargetFields _target(_ScaleRow r, {bool labelled = false}) => TargetFields(
    mode: scaleModeFromString(r.mode),
    custom: r.custom,
    labelled: labelled,
    onChanged: (m) => setState(() => r.mode = m.name),
  );

  Widget _line(_ScaleRow r, _Group g) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: _name(r)),
        const SizedBox(width: 8),
        numberField(context, r.min, 'Min'),
        const SizedBox(width: 8),
        numberField(context, r.max, 'Max'),
        if (widget.isSession) ...[
          const SizedBox(width: 8),
          _stepsField(r),
          const SizedBox(width: 8),
          _target(r),
        ],
        _remove(r, g),
      ],
    ),
  );

  Widget _twoLines(_ScaleRow r, _Group g) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _name(r, labelled: true)),
            const SizedBox(width: 8),
            numberField(context, r.min, 'Min', labelled: true),
            const SizedBox(width: 8),
            numberField(context, r.max, 'Max', labelled: true),
            _remove(r, g),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _stepsField(r, labelled: true),
            _target(r, labelled: true),
          ],
        ),
      ],
    ),
  );
}
