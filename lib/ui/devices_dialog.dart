import 'dart:math' show min;

import 'package:flutter/material.dart';

import '../core/electrode/electrode_model.dart';
import 'electrode_view.dart';

/// Edit the leads and IPGs of each manufacturer, and each lead's contact
/// layout. Null on Cancel.
Future<Devices?> showDevicesDialog(
  BuildContext context, {
  required Devices devices,
}) => showDialog<Devices>(
  context: context,
  builder: (_) => _DevicesDialog(devices),
);

/// A new lead starts as four levels, the middle two directional.
const _newLead = ElectrodeModel(
  name: '',
  numContacts: 4,
  contactHeight: 1.5,
  contactSpacing: 0.5,
  leadDiameter: 1.3,
  isDirectional: true,
  tipContact: false,
  segmentsPerLevel: 3,
  directionalLevels: [1, 2],
  levelDirectional: [false, true, true, false],
);

class _Lead {
  _Lead(String model, this.design) : model = TextEditingController(text: model);

  final TextEditingController model;
  ElectrodeModel design;
}

class _Maker {
  _Maker(String name, Map<String, ElectrodeModel> leads, List<String> ipgs)
    : name = TextEditingController(text: name),
      leads = [
        for (final MapEntry(:key, :value) in leads.entries)
          _Lead(_model(name, key), value),
      ],
      ipgs = [
        for (final i in ipgs) TextEditingController(text: _model(name, i)),
      ];

  final TextEditingController name;
  final List<_Lead> leads;
  final List<TextEditingController> ipgs;

  /// [full] without its manufacturer, as typed under that manufacturer.
  static String _model(String maker, String full) =>
      full.startsWith('$maker ') ? full.substring(maker.length + 1) : full;

  void dispose() {
    name.dispose();
    for (final c in [...leads.map((l) => l.model), ...ipgs]) {
      c.dispose();
    }
  }
}

class _DevicesDialog extends StatefulWidget {
  const _DevicesDialog(this.devices);

  final Devices devices;

  @override
  State<_DevicesDialog> createState() => _DevicesDialogState();
}

class _DevicesDialogState extends State<_DevicesDialog> {
  late final _makers = [
    for (final MapEntry(:key, :value) in widget.devices.entries)
      _Maker(key, value.leads, value.ipgs),
  ];
  int _selected = 0;
  _Lead? _designing;

  /// The content width of the dialog with no lead open, kept when one is, and
  /// the width added beside it for the lead design.
  static const _listsWidth = 552.0;
  static const _designerWidth = 420.0;

  @override
  void dispose() {
    for (final m in _makers) {
      m.dispose();
    }
    super.dispose();
  }

  void _save() {
    final Devices out = {};
    for (final m in _makers) {
      final maker = m.name.text.trim();
      if (maker.isEmpty) continue;
      String full(TextEditingController c) =>
          c.text.trim().isEmpty ? '' : '$maker ${c.text.trim()}';
      out[maker] = (
        leads: {
          for (final l in m.leads)
            if (full(l.model).isNotEmpty)
              full(l.model): l.design.redesigned(name: full(l.model)),
        },
        ipgs: [
          for (final c in m.ipgs)
            if (full(c).isNotEmpty) full(c),
        ],
      );
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final lead = _designing;
    final screen = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: const Text('Devices settings'),
      constraints: lead == null ? null : const BoxConstraints(),
      content: SizedBox(
        width: lead == null
            ? 760
            : min(_listsWidth + 16 + _designerWidth, screen.width - 112),
        height: 560,
        child: LayoutBuilder(
          builder: (context, c) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (lead == null || c.maxWidth >= 900) ...[
                SizedBox(width: 180, child: _makerList()),
                const VerticalDivider(width: 16),
              ],
              Expanded(child: _editor()),
              if (lead != null) ...[
                const VerticalDivider(width: 16),
                SizedBox(width: _designerWidth, child: _designer(lead)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _makerList() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: ListView.builder(
          itemCount: _makers.length,
          itemBuilder: (_, i) => ListTile(
            dense: true,
            selected: i == _selected,
            title: Text(
              _makers[i].name.text.isEmpty ? '(unnamed)' : _makers[i].name.text,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_makers[i].leads.length} leads, ${_makers[i].ipgs.length} IPGs',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Delete manufacturer',
              onPressed: () => setState(() {
                _makers.removeAt(i).dispose();
                if (_selected >= _makers.length && _selected > 0) _selected--;
                _designing = null;
              }),
            ),
            onTap: () => setState(() {
              _selected = i;
              _designing = null;
            }),
          ),
        ),
      ),
      TextButton.icon(
        onPressed: () => setState(() {
          _makers.add(_Maker('', const {}, const []));
          _selected = _makers.length - 1;
          _designing = null;
        }),
        icon: const Icon(Icons.add),
        label: const Text('Add manufacturer'),
      ),
    ],
  );

  Widget _editor() {
    if (_selected >= _makers.length) {
      return const Center(child: Text('Add a manufacturer to edit.'));
    }
    final m = _makers[_selected];
    final heading = Theme.of(context).textTheme.titleSmall;
    const field = InputDecoration(isDense: true);
    Widget row(
      TextEditingController c,
      String label,
      VoidCallback onRemove, {
      _Lead? lead,
    }) => Padding(
      key: ObjectKey(c),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: c,
              onTap: lead == null
                  ? null
                  : () => setState(() => _designing = lead),
              decoration: field.copyWith(
                labelText: label,
                filled: lead != null && lead == _designing,
              ),
            ),
          ),
          if (lead != null)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Lead design',
              onPressed: () => setState(() => _designing = lead),
            ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'Remove',
            onPressed: () => setState(() {
              onRemove();
              c.dispose();
            }),
          ),
        ],
      ),
    );
    Widget add(String label, VoidCallback onPressed) => Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(onPressed),
        icon: const Icon(Icons.add),
        label: Text(label),
      ),
    );
    return ListView(
      key: ObjectKey(m),
      children: [
        TextField(
          controller: m.name,
          decoration: field.copyWith(labelText: 'Manufacturer'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Text('Leads', style: heading),
        for (final l in m.leads)
          row(l.model, 'Lead model', lead: l, () {
            m.leads.remove(l);
            if (_designing == l) _designing = null;
          }),
        add('Add lead', () {
          final lead = _Lead('', _newLead);
          m.leads.add(lead);
          _designing = lead;
        }),
        const Divider(height: 24),
        Text('IPGs', style: heading),
        for (final c in m.ipgs) row(c, 'IPG model', () => m.ipgs.remove(c)),
        add('Add IPG', () => m.ipgs.add(TextEditingController())),
      ],
    );
  }

  Widget _designer(_Lead lead) {
    final d = lead.design;
    void redesign(ElectrodeModel next) => setState(() => lead.design = next);
    final levels = d.levelDirectional;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: lead.model,
                  builder: (context, _) => Text(
                    lead.model.text.isEmpty ? 'New lead' : lead.model.text,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Close lead design',
                onPressed: () => setState(() => _designing = null),
              ),
            ],
          ),
          SizedBox(
            height: 360,
            child: IgnorePointer(
              child: ElectrodeView(
                key: ValueKey(d.toJson().toString()),
                model: d,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(child: Text('Levels')),
              IconButton(
                icon: const Icon(Icons.remove),
                tooltip: 'Fewer levels',
                onPressed: levels.length > 1
                    ? () => redesign(
                        d.redesigned(
                          levelDirectional: levels.sublist(
                            0,
                            levels.length - 1,
                          ),
                        ),
                      )
                    : null,
              ),
              Text('${levels.length}'),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'More levels',
                onPressed: levels.length < 8
                    ? () => redesign(
                        d.redesigned(levelDirectional: [...levels, false]),
                      )
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Directional levels, split into three contacts'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = levels.length - 1; i >= 0; i--)
                FilterChip(
                  label: Text('E$i'),
                  selected: levels[i],
                  onSelected: (on) => redesign(
                    d.redesigned(
                      levelDirectional: [
                        for (final (j, v) in levels.indexed) j == i ? on : v,
                      ],
                    ),
                  ),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Contact at the tip'),
            value: d.tipContact,
            onChanged: (on) => redesign(d.redesigned(tipContact: on)),
          ),
        ],
      ),
    );
  }
}
