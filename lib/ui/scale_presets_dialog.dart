import 'package:flutter/material.dart';

import '../core/session/scale_presets.dart';

/// Edit the clinical scale presets (disease group -> scale names) and each
/// scale's range, mirroring the desktop `ClinicalScalesSettingsDialog`. The
/// range only sets the clinical figure's y axis, so it may be left blank.
/// Returns the edited groups and ranges on Save & Close, or null on Cancel.
Future<({Map<String, List<String>> groups, Map<String, List<String>> ranges})?>
showClinicalPresetsDialog(
  BuildContext context, {
  required Map<String, List<String>> presets,
  Map<String, ScaleRange> ranges = const {},
}) async {
  final groups = [
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
      title: 'Clinical scales settings',
      isSession: false,
      groups: groups,
    ),
  );
  if (out == null) return null;
  // Clinical rows are [name, min, max]: the names per group, and one range per
  // scale wherever both bounds were given.
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

/// Edit the session scale presets (disease group -> (name,min,max,mode) rows),
/// mirroring the desktop `SessionScalesSettingsDialog`. The report optimization
/// [mode] is preserved (hidden) so rows stay interchangeable with the desktop.
/// Returns `{group: [[name,min,max,mode], …]}` on Save & Close, else null.
Future<Map<String, List<List<String>>>?> showSessionPresetsDialog(
  BuildContext context, {
  required Map<String, List<SessionScaleRow>> presets,
}) {
  final groups = [
    for (final e in presets.entries)
      _Group(e.key, [
        for (final r in e.value)
          _ScaleRow(name: r.name, min: r.min, max: r.max, mode: r.mode),
      ]),
  ];
  return showDialog<Map<String, List<List<String>>>>(
    context: context,
    builder: (_) => _ScalePresetsDialog(
      title: 'Session scales settings',
      isSession: true,
      groups: groups,
    ),
  );
}

/// One editable scale row. The report [mode] is carried through unchanged
/// (defaulting for new rows) and only session rows use it.
class _ScaleRow {
  _ScaleRow({
    String name = '',
    String min = '0',
    String max = '10',
    this.mode = defaultScaleOptimizationMode,
  }) {
    this.name.text = name;
    this.min.text = min;
    this.max.text = max;
  }

  final name = TextEditingController();
  final min = TextEditingController();
  final max = TextEditingController();
  String mode;

  void dispose() {
    name.dispose();
    min.dispose();
    max.dispose();
  }
}

class _Group {
  _Group(String name, this.rows) {
    this.name.text = name;
  }

  final name = TextEditingController();
  List<_ScaleRow> rows;

  void dispose() {
    name.dispose();
    for (final r in rows) {
      r.dispose();
    }
  }
}

class _ScalePresetsDialog extends StatefulWidget {
  const _ScalePresetsDialog({
    required this.title,
    required this.isSession,
    required this.groups,
  });

  final String title;
  final bool isSession;
  final List<_Group> groups;

  @override
  State<_ScalePresetsDialog> createState() => _ScalePresetsDialogState();
}

class _ScalePresetsDialogState extends State<_ScalePresetsDialog> {
  late final List<_Group> _groups = widget.groups;
  int _selected = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_groups.isEmpty) _selected = -1;
  }

  @override
  void dispose() {
    for (final g in _groups) {
      g.dispose();
    }
    super.dispose();
  }

  Future<void> _addGroup() async {
    final name = await _promptText(context, 'New preset group', 'Group name');
    if (name == null || name.trim().isEmpty) return;
    setState(() {
      _groups.add(_Group(name.trim(), [_newRow()]));
      _selected = _groups.length - 1;
    });
  }

  /// A new row: 0 to 10 for a session scale, no range for a clinical one.
  _ScaleRow _newRow() =>
      widget.isSession ? _ScaleRow() : _ScaleRow(min: '', max: '');

  void _deleteGroup(int i) {
    setState(() {
      _groups.removeAt(i).dispose();
      _selected = _groups.isEmpty ? -1 : i.clamp(0, _groups.length - 1);
    });
  }

  void _save() {
    final out = <String, List<List<String>>>{};
    for (final g in _groups) {
      final name = g.name.text.trim();
      final problem = name.isEmpty
          ? 'A preset group has no name.'
          : out.containsKey(name)
          ? 'Two preset groups are named "$name".'
          : null;
      if (problem != null) {
        setState(() => _error = 'Not saved: $problem');
        return;
      }
      final rows = <List<String>>[];
      for (final r in g.rows) {
        final n = r.name.text.trim();
        if (n.isEmpty) continue;
        rows.add(
          widget.isSession
              ? [n, r.min.text.trim(), r.max.text.trim(), r.mode]
              : [n, r.min.text.trim(), r.max.text.trim()],
        );
      }
      out[name] = rows;
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 180, child: _groupList()),
                  const VerticalDivider(width: 16),
                  Expanded(child: _editor()),
                ],
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save & Close')),
      ],
    );
  }

  Widget _groupList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _groups.isEmpty
              ? const Center(child: Text('No groups'))
              : ListView.builder(
                  itemCount: _groups.length,
                  itemBuilder: (_, i) => ListTile(
                    dense: true,
                    selected: i == _selected,
                    title: Text(
                      _groups[i].name.text.isEmpty
                          ? '(unnamed)'
                          : _groups[i].name.text,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${_groups[i].rows.length} scales'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: 'Delete group',
                      onPressed: () => _deleteGroup(i),
                    ),
                    onTap: () => setState(() => _selected = i),
                  ),
                ),
        ),
        TextButton.icon(
          onPressed: _addGroup,
          icon: const Icon(Icons.add),
          label: const Text('Add group'),
        ),
      ],
    );
  }

  Widget _editor() {
    if (_selected < 0 || _selected >= _groups.length) {
      return const Center(child: Text('Select or add a group to edit.'));
    }
    final g = _groups[_selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: g.name,
          decoration: const InputDecoration(
            labelText: 'Group name',
            isDense: true,
          ),
          // Keep the left-hand list label in sync while typing.
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: g.rows.length,
            itemBuilder: (_, i) => _rowEditor(g.rows[i], g),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => g.rows.add(_newRow())),
            icon: const Icon(Icons.add),
            label: const Text('Add scale'),
          ),
        ),
      ],
    );
  }

  Widget _rowEditor(_ScaleRow r, _Group g) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: r.name,
              decoration: const InputDecoration(
                labelText: 'Scale name',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 64, child: _numField(r.min, 'Min')),
          const SizedBox(width: 8),
          SizedBox(width: 64, child: _numField(r.max, 'Max')),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'Remove scale',
            onPressed: () => setState(() {
              g.rows.remove(r);
              r.dispose();
            }),
          ),
        ],
      ),
    );
  }

  Widget _numField(TextEditingController c, String label) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, isDense: true),
  );
}

/// Small single-field text prompt (used for a new group name).
Future<String?> _promptText(
  BuildContext context,
  String title,
  String label,
) async {
  final ctrl = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return result;
}
