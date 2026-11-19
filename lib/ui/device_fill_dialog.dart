import 'package:flutter/material.dart';

import '../core/electrode/amplitude.dart' show parseAmplitude;
import '../percept/therapy.dart';
import '../core/session/device_fill.dart';
import '../core/session/session_row.dart';
import '../core/timestamps.dart' show recordedTime;
import '../report/report_data.dart' show trimZeros;

typedef PerceptFile = ({String file, PerceptTimeline? timeline, String? error});

typedef DeviceFillChoice = ({DeviceFillPlan plan, Set<String> keep, bool add});

Future<DeviceFillChoice?> showDeviceFillDialog(
  BuildContext context, {
  required List<SessionRow> rows,
  required List<PerceptFile> exports,
}) => showDialog<DeviceFillChoice>(
  context: context,
  builder: (_) => _DeviceFillDialog(rows: rows, exports: exports),
);

class _DeviceFillDialog extends StatefulWidget {
  const _DeviceFillDialog({required this.rows, required this.exports});

  final List<SessionRow> rows;
  final List<PerceptFile> exports;

  @override
  State<_DeviceFillDialog> createState() => _DeviceFillDialogState();
}

class _DeviceFillDialogState extends State<_DeviceFillDialog> {
  var _swap = false;
  var _add = true;
  final _keep = <String>{};
  late DeviceFillPlan _plan = _planned();

  DeviceFillPlan _planned() => planDeviceFill(widget.rows, [
    for (final e in widget.exports) ?e.timeline,
  ], swapSides: _swap);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final warning = small?.copyWith(color: theme.colorScheme.error);
    final plan = _plan;
    final read = [
      for (final e in widget.exports)
        if (e.timeline != null) e.file,
    ];
    final changing = [
      for (final f in plan.fills)
        if (f.changes.isNotEmpty) f,
    ];
    final agreeing = [
      for (final f in plan.fills)
        if (f.changes.isEmpty) _label(f.blockId, f.acqTime, f.isInitial),
    ];
    final adds = _add && plan.additions.isNotEmpty;
    final fills = changing.any((f) => !_keep.contains(f.blockId));
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(text, style: theme.textTheme.titleSmall),
    );

    return AlertDialog(
      title: const Text('Stimulation from the Percept export'),
      scrollable: true,
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              read.isEmpty
                  ? 'No export in this visit could be read.'
                  : 'Read from ${read.join(', ')}. Each configuration is '
                        'matched to the setting the device had when it was '
                        'saved. Values filled here are marked in the report as '
                        'read from the device.',
            ),
            for (final e in widget.exports)
              if (e.error != null)
                Text('Could not read ${e.file}: ${e.error}', style: warning),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _swap,
              title: const Text('Swap sides'),
              subtitle: Text(
                "Take the device's left lead as this session's right, when "
                "the stimulator labels the patient's sides the other way "
                'round.',
                style: small,
              ),
              onChanged: (v) => setState(() {
                _swap = v;
                _keep.clear();
                _plan = _planned();
              }),
            ),
            if (plan.refusal case final refusal?)
              Text(refusal, style: warning)
            else ...[
              if (changing.isNotEmpty)
                heading('Saved configurations the export changes'),
              for (final f in changing)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: !_keep.contains(f.blockId),
                  title: Text(_label(f.blockId, f.acqTime, f.isInitial)),
                  subtitle: Text(
                    [
                      for (final e in f.changes.entries)
                        '${_column(e.key)}: ${_shown(f.current[e.key])} → '
                            '${e.value}',
                      if (f.held case final held?
                          when held < const Duration(seconds: 10))
                        'The device had held this setting for '
                            '${held.inSeconds} s when it was saved.',
                    ].join('\n'),
                    style: small,
                  ),
                  onChanged: (v) => setState(
                    () => v == true
                        ? _keep.remove(f.blockId)
                        : _keep.add(f.blockId),
                  ),
                ),
              if (agreeing.isNotEmpty)
                Text(
                  'Already as the device has them: ${agreeing.join(', ')}.',
                  style: small,
                ),
              if (plan.uncovered.isNotEmpty)
                Text(
                  'The export has no setting at the time of '
                  '${plan.uncovered.map((u) => _label(u.blockId, u.acqTime, false)).join(', ')}, '
                  'so their values stay as entered.',
                  style: small,
                ),
              if (plan.additions.isNotEmpty)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _add,
                  title: Text(
                    'Add the ${plan.additions.length} '
                    '${plan.additions.length == 1 ? 'setting' : 'settings'} '
                    'the device held that were not saved',
                  ),
                  subtitle: Text(
                    [
                      for (final a in plan.additions)
                        '${a.isInitial ? 'Initial assessment' : recordedTime(a.acqTime)}: '
                            '${_setting(cellsOf(a.setting))}',
                    ].join('\n'),
                    style: small,
                  ),
                  onChanged: (v) => setState(() => _add = v ?? false),
                ),
              if (plan.fills.isEmpty && plan.additions.isEmpty)
                const Text('The export holds nothing to fill.'),
              for (final note in plan.notes) Text(note, style: small),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: plan.refusal == null && (fills || adds)
              ? () => Navigator.pop(context, (
                  plan: plan,
                  keep: {..._keep},
                  add: _add,
                ))
              : null,
          child: const Text('Fill'),
        ),
      ],
    );
  }
}

String _label(String blockId, String acqTime, bool isInitial) => isInitial
    ? 'the initial assessment'
    : '#$blockId at ${recordedTime(acqTime)}';

String _shown(String? value) =>
    value == null || value.isEmpty ? 'empty' : value;

const _what = {
  'stim_freq': 'frequency (Hz)',
  'anode': 'anode',
  'cathode': 'cathode',
  'amplitude': 'amplitude (mA)',
  'pulse_width': 'pulse width (µs)',
};

String _column(String column) {
  if (column == 'program_id') return 'Group';
  final split = column.indexOf('_');
  final side = column.substring(0, split) == 'left' ? 'Left' : 'Right';
  return '$side ${_what[column.substring(split + 1)] ?? column}';
}

String _setting(Map<String, String> cells) => [
  for (final side in ['left', 'right'])
    if (cells.keys.any((k) => k.startsWith('${side}_')))
      [
        side,
        ?cells['${side}_cathode'],
        if (cells['${side}_amplitude'] case final a?)
          '${trimZeros(parseAmplitude(a).total)} mA',
        if (cells['${side}_stim_freq'] case final f?) '$f Hz',
        if (cells['${side}_pulse_width'] case final p?) '$p µs',
      ].join(' '),
].join(', ');
