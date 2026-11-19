/// Session stimulation filled from a Percept export, matched by time.
library;

import '../../percept/therapy.dart';
import '../electrode/amplitude.dart';
import '../schema_columns.dart';
import '../timestamps.dart';
import 'authoring.dart';
import 'session_row.dart';

class BlockFill {
  const BlockFill({
    required this.blockId,
    required this.acqTime,
    required this.isInitial,
    required this.current,
    required this.device,
    this.held,
  });

  final String blockId;
  final String acqTime;
  final bool isInitial;

  final Map<String, String> current;
  final Map<String, String> device;

  final Duration? held;

  Map<String, String> get changes => {
    for (final e in device.entries)
      if ((current[e.key] ?? '') != e.value) e.key: e.value,
  };
}

typedef DeviceAddition = ({
  DeviceSetting setting,
  bool isInitial,
  String acqTime,
});

class DeviceFillPlan {
  const DeviceFillPlan({
    this.fills = const [],
    this.uncovered = const [],
    this.additions = const [],
    this.notes = const [],
    this.refusal,
  });

  final List<BlockFill> fills;

  final List<({String blockId, String acqTime})> uncovered;
  final List<DeviceAddition> additions;
  final List<String> notes;

  final String? refusal;
}

DeviceFillPlan planDeviceFill(
  List<SessionRow> rows,
  List<PerceptTimeline> exports, {
  bool swapSides = false,
}) {
  if (exports.isEmpty) {
    return const DeviceFillPlan(refusal: 'No Percept export was found.');
  }
  final sorted = [...exports]
    ..sort((a, b) => a.sessionStart.compareTo(b.sessionStart));
  DeviceSetting? oriented(DeviceSetting? s) =>
      s == null || !swapSides ? s : s.swapped();
  final runs = [
    for (final e in sorted)
      for (final r in e.runs) oriented(r)!,
  ]..sort((a, b) => a.start.compareTo(b.start));
  final initial = oriented(sorted.first.initial);
  final last = oriented(sorted.last.last);

  final codes = sorted.last.leadModels;
  for (final (side, model) in [
    ('left', electrodeModelIn(rows)),
    ('right', electrodeModelIn(rows, right: true)),
  ]) {
    final code = codes[swapSides ? (side == 'left' ? 'right' : 'left') : side];
    if (code != null && model.isNotEmpty && !model.contains(code)) {
      return DeviceFillPlan(
        refusal:
            'The export names a $code lead on the $side side, but this '
            'session names $model. Check the leads, or the side swap.',
      );
    }
  }

  final offset = _offsetOf(rows);
  final days = {for (final r in rows) recordedDate(r.acqTime)}..remove('');
  if (days.isNotEmpty && offset != null) {
    final exportDays = {
      for (final e in sorted) ...[
        _localDate(e.sessionStart, offset),
        _localDate(e.sessionEnd, offset),
      ],
    };
    if (!days.any(exportDays.contains)) {
      return DeviceFillPlan(
        refusal:
            'The export is from ${exportDays.join(', ')}, but this session '
            'was recorded on ${days.join(', ')}.',
      );
    }
  }

  final blocks = <String, List<SessionRow>>{};
  for (final r in rows) {
    (blocks[r.blockId] ??= []).add(r);
  }
  final fills = <BlockFill>[];
  final uncovered = <({String blockId, String acqTime})>[];
  final logged = <(DateTime, Map<String, String>)>[];
  var hasInitial = false;
  for (final MapEntry(key: id, value: block) in blocks.entries) {
    final first = block.first;
    final isInitial = isInitialValue(first.isInitial);
    final t = first.timestamp?.toUtc();
    final DeviceSetting? setting;
    if (isInitial) {
      hasInitial = true;
      setting = initial;
    } else {
      setting = t == null ? null : settingAt(runs, t);
    }
    final device = setting == null
        ? const <String, String>{}
        : cellsOf(setting);
    final own = first.toMap();
    if (!isInitial && t != null) logged.add((t, {...own, ...device}));
    if (device.isEmpty) {
      uncovered.add((blockId: id, acqTime: first.acqTime));
      continue;
    }
    fills.add(
      BlockFill(
        blockId: id,
        acqTime: first.acqTime,
        isInitial: isInitial,
        current: {for (final k in device.keys) k: own[k] ?? ''},
        device: device,
        held: isInitial || t == null ? null : t.difference(setting!.start),
      ),
    );
  }

  final wall = offset ?? sorted.first.sessionStart.toLocal().timeZoneOffset;
  DeviceAddition addition(DeviceSetting s, {bool isInitial = false}) => (
    setting: s,
    isInitial: isInitial,
    acqTime: _acqTimeAt(isInitial ? s.start : s.end, wall),
  );
  final additions = <DeviceAddition>[
    if (!hasInitial && initial != null && cellsOf(initial).isNotEmpty)
      addition(initial, isInitial: true),
  ];
  final stable = stableSettings(runs);
  for (final s in stable) {
    if (logged.any((l) => !l.$1.isBefore(s.start) && !l.$1.isAfter(s.end))) {
      continue;
    }
    additions.add(addition(s));
  }
  final lastCells = last == null ? const <String, String>{} : cellsOf(last);
  if (last != null && lastCells.isNotEmpty) {
    (DateTime, Map<String, String>)? latest;
    for (final c in [for (final s in stable) (s.end, cellsOf(s)), ...logged]) {
      if (latest == null || c.$1.isAfter(latest.$1)) latest = c;
    }
    final ended = latest?.$2;
    if (ended == null ||
        lastCells.entries.any((e) => ended[e.key] != e.value)) {
      additions.add(addition(last));
    }
  }

  return DeviceFillPlan(
    fills: fills,
    uncovered: uncovered,
    additions: additions,
    notes: [for (final e in sorted) ...e.notes],
  );
}

DeviceSetting? settingAt(List<DeviceSetting> runs, DateTime t) {
  DeviceSetting? found;
  for (final r in runs) {
    if (!t.isBefore(r.start) && !t.isAfter(r.end)) found = r;
  }
  return found;
}

void applyDeviceFill(
  SessionAuthoring authoring,
  DeviceFillPlan plan, {
  Set<String> keep = const {},
  bool add = true,
}) {
  for (final f in plan.fills) {
    final changes = f.changes;
    if (keep.contains(f.blockId) || changes.isEmpty) continue;
    final row = authoring.rows.firstWhere((r) => r.blockId == f.blockId);
    authoring.setOnBlock(f.blockId, {
      ...changes,
      'from_device': _columnList({...deviceColumnsOf(row), ...changes.keys}),
    });
  }
  if (add && plan.additions.isNotEmpty) {
    authoring.loadExisting([...authoring.rows]);
    final rows = authoring.rows;
    String visit(String Function(SessionRow) field) =>
        sessionValueIn(rows, field);
    final details = (
      pathology: visit((r) => r.pathology),
      target: visit((r) => r.target),
      leftModel: visit((r) => r.leftElectrodeModel),
      rightModel: visit((r) => r.rightElectrodeModel),
      leftIpg: visit((r) => r.leftIpgModel),
      rightIpg: visit((r) => r.rightIpgModel),
      leftPosition: visit((r) => r.leftIpgPosition),
      rightPosition: visit((r) => r.rightIpgPosition),
    );
    for (final a in plan.additions) {
      final cells = cellsOf(a.setting);
      final inserted = authoring.addInsert(
        isInitial: a.isInitial,
        stim: cells,
        programId: cells['program_id'] ?? '',
        pathology: details.pathology,
        target: details.target,
        leftElectrodeModel: details.leftModel,
        rightElectrodeModel: details.rightModel,
        leftIpgModel: details.leftIpg,
        rightIpgModel: details.rightIpg,
        leftIpgPosition: details.leftPosition,
        rightIpgPosition: details.rightPosition,
        fromDevice: _columnList(cells.keys.toSet()),
      );
      authoring.setOnBlock(inserted.first.blockId, {'acq_time': a.acqTime});
    }
  }
  _renumberByTime(authoring);
}

String keptDeviceColumns(SessionRow before, SessionRow after) {
  final a = before.toMap();
  final b = after.toMap();
  return _columnList({
    for (final c in deviceColumnsOf(before))
      if (a[c] == b[c]) c,
  });
}

String _columnList(Set<String> columns) => [
  for (final c in workingColumns)
    if (columns.contains(c)) c,
].join(' ');

void _renumberByTime(SessionAuthoring authoring) {
  final blocks = <String, List<SessionRow>>{};
  for (final r in authoring.rows) {
    (blocks[r.blockId] ??= []).add(r);
  }
  final order = [...blocks.values.indexed]
    ..sort((x, y) {
      int rank(List<SessionRow> b) => isInitialValue(b.first.isInitial) ? 0 : 1;
      final byKind = rank(x.$2).compareTo(rank(y.$2));
      if (byKind != 0) return byKind;
      final tx = x.$2.first.timestamp;
      final ty = y.$2.first.timestamp;
      if (tx != null && ty != null && tx != ty) return tx.compareTo(ty);
      return x.$1.compareTo(y.$1);
    });
  final renumbered = [
    for (final (i, (_, block)) in order.indexed)
      for (final r in block)
        SessionRow.fromMap({...r.toMap(), 'block_id': '$i'}),
  ];
  authoring.rows
    ..clear()
    ..addAll(renumbered);
}

Duration? _offsetOf(List<SessionRow> rows) {
  for (final r in rows) {
    final cell = r.acqTime.trim();
    if (cell.endsWith('Z')) return Duration.zero;
    final m = RegExp(r'([+-])(\d{2}):?(\d{2})$').firstMatch(cell);
    if (m == null) continue;
    final minutes = int.parse(m.group(2)!) * 60 + int.parse(m.group(3)!);
    return Duration(minutes: m.group(1) == '-' ? -minutes : minutes);
  }
  return null;
}

String _localDate(DateTime instant, Duration offset) =>
    recordedDate(_acqTimeAt(instant, offset));

String _acqTimeAt(DateTime instant, Duration offset) {
  final wall = instant.toUtc().add(offset);
  String two(int n) => n.toString().padLeft(2, '0');
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  return '${wall.year}-${two(wall.month)}-${two(wall.day)}'
      'T${two(wall.hour)}:${two(wall.minute)}:${two(wall.second)}'
      '$sign${two(abs.inHours)}:${two(abs.inMinutes.remainder(60))}';
}

Map<String, String> cellsOf(DeviceSetting s) => {
  if (s.group.isNotEmpty) 'program_id': s.group,
  ..._sideCells('left', s.left),
  ..._sideCells('right', s.right),
};

Map<String, String> _sideCells(String side, DeviceSide? d) {
  if (d == null) return const {};
  final contacts = _tokensOf(d.contacts);
  return {
    if (d.rate != null) '${side}_stim_freq': _number(d.rate!),
    if (contacts != null) ...{
      '${side}_anode': contacts.anode,
      '${side}_cathode': contacts.cathode,
    },
    if (d.amplitude != null)
      '${side}_amplitude': encodeAmplitude(
        d.amplitude!,
        contacts?.split ?? const [],
      ),
    if (d.pulseWidth != null) '${side}_pulse_width': _number(d.pulseWidth!),
  };
}

String _number(double v) => v == v.truncateToDouble() ? '${v.toInt()}' : '$v';

({String anode, String cathode, List<double> split})? _tokensOf(
  List<Contact>? contacts,
) {
  if (contacts == null) return null;
  final anodes = <String>[];
  final cathodes = <(String, double?)>[];
  for (final c in contacts) {
    final tokens = _tokens(c.electrode);
    if (tokens == null) return null;
    if (!c.cathode) {
      anodes.addAll(tokens);
      continue;
    }
    for (final t in tokens) {
      cathodes.add((t, c.share == null ? null : c.share! / tokens.length));
    }
  }
  if (cathodes.isEmpty) return null;
  anodes.sort((a, b) => _tokenOrder(a).compareTo(_tokenOrder(b)));
  cathodes.sort((a, b) => _tokenOrder(a.$1).compareTo(_tokenOrder(b.$1)));
  final shares = [for (final c in cathodes) c.$2];
  final split = cathodes.length > 1 && shares.every((s) => s != null && s > 0);
  final total = split ? shares.fold(0.0, (a, b) => a + b!) : 0.0;
  return (
    anode: anodes.join('_'),
    cathode: cathodes.map((c) => c.$1).join('_'),
    split: split ? [for (final s in shares) s! / total * 100] : const [],
  );
}

List<String>? _tokens(String electrode) {
  final e = electrode.toLowerCase();
  if (e == 'case') return ['case'];
  final ring = RegExp(r'^fourelectrodes_([0-3])$').firstMatch(e);
  if (ring != null) return ['E${ring.group(1)}'];
  final m = RegExp(r'^sensight_0?([0-3])([abc])?$').firstMatch(e);
  if (m == null) return null;
  final level = m.group(1)!;
  if (m.group(2) case final segment?) return ['E$level$segment'];
  if (level == '0' || level == '3') return ['E$level'];
  return ['E${level}a', 'E${level}b', 'E${level}c'];
}

int _tokenOrder(String token) {
  if (token == 'case') return -1;
  final m = RegExp(r'^E(\d+)([abc]?)$').firstMatch(token)!;
  final segment = m.group(2)!;
  return int.parse(m.group(1)!) * 4 +
      (segment.isEmpty ? 0 : segment.codeUnitAt(0) - 96);
}
