typedef Contact = ({String electrode, bool cathode, double? share});

class DeviceSide {
  const DeviceSide({this.rate, this.pulseWidth, this.amplitude, this.contacts});

  final double? rate;
  final double? pulseWidth;
  final double? amplitude;
  final List<Contact>? contacts;

  DeviceSide withAmplitude(double? mA) => DeviceSide(
    rate: rate,
    pulseWidth: pulseWidth,
    amplitude: mA,
    contacts: contacts,
  );
}

class DeviceSetting {
  const DeviceSetting({
    required this.start,
    required this.end,
    this.group = '',
    this.left,
    this.right,
  });

  final DateTime start;
  final DateTime end;
  final String group;
  final DeviceSide? left;
  final DeviceSide? right;

  Duration get held => end.difference(start);

  DeviceSetting swapped() => DeviceSetting(
    start: start,
    end: end,
    group: group,
    left: right,
    right: left,
  );

  DeviceSetting between(DateTime from, DateTime to) => DeviceSetting(
    start: from,
    end: to,
    group: group,
    left: left,
    right: right,
  );
}

class PerceptTimeline {
  const PerceptTimeline({
    required this.sessionStart,
    required this.sessionEnd,
    required this.runs,
    this.initial,
    this.last,
    this.leadModels = const {},
    this.notes = const [],
  });

  final DateTime sessionStart;
  final DateTime sessionEnd;
  final DeviceSetting? initial;
  final DeviceSetting? last;
  final List<DeviceSetting> runs;
  final Map<String, String> leadModels;
  final List<String> notes;
}

bool isPerceptExport(Object? json) =>
    json is Map &&
    json.containsKey('SessionDate') &&
    json.containsKey('Groups') &&
    json.containsKey('LeadConfiguration');

const int _tickRolloverMs = 3276800;
const Duration _minHold = Duration(seconds: 10);
const Duration _maxGap = Duration(seconds: 30);

PerceptTimeline perceptTimeline(Map<String, dynamic> json) {
  final notes = <String>[];
  final start = _time(json['SessionDate']);
  if (start == null) throw const FormatException('No SessionDate.');
  final end = _time(json['SessionEndDate']) ?? start;
  final stim = json['Stimulation'];
  bool stimOn(String key) => stim is! Map || stim[key] != 'StimStatusDef.OFF';

  DeviceSetting? group(String phase, DateTime at, String statusKey) {
    final groups = json['Groups'];
    if (groups is! Map) return null;
    final active = _list(groups[phase])
        .whereType<Map>()
        .where((g) => g['ActiveGroup'] == true);
    if (active.isEmpty) return null;
    final when = phase == 'Initial' ? 'start' : 'end';
    if (!stimOn(statusKey)) {
      notes.add('Stimulation was off at the $when of the visit.');
      return null;
    }
    final g = active.first;
    final settings = g['ProgramSettings'];
    if (settings is! Map) return null;
    final sides = <String, DeviceSide>{};
    for (final c in _list(settings['SensingChannel']).whereType<Map>()) {
      final side = _hemisphere(c['HemisphereLocation']);
      if (side == null) continue;
      final amplitude = _num(c['AmplitudeInMilliAmps']);
      if (amplitude == null) {
        notes.add(
          'The export does not state the $side amplitude at the $when of the '
          'visit in a confirmed field.',
        );
      }
      sides[side] = DeviceSide(
        rate: _num(settings['RateInHertz']) ?? _num(c['RateInHertz']),
        pulseWidth: _num(c['PulseWidthInMicroSecond']),
        amplitude: amplitude,
        contacts: _contacts(c['ElectrodeState']),
      );
    }
    for (final side in ['left', 'right']) {
      final hemisphere =
          settings[side == 'left' ? 'LeftHemisphere' : 'RightHemisphere'];
      if (hemisphere is! Map) continue;
      final programs = _list(hemisphere['Programs']).whereType<Map>().toList();
      if (programs.length != 1) {
        notes.add(
          'The $side side runs ${programs.length} programs at the $when of '
          'the visit, which is not read.',
        );
        continue;
      }
      final p = programs.single;
      sides[side] = DeviceSide(
        rate: _num(settings['RateInHertz']) ?? _num(p['RateInHertz']),
        pulseWidth: _num(p['PulseWidthInMicroSecond']),
        amplitude: _num(p['AmplitudeInMilliAmps']),
        contacts: _contacts(p['ElectrodeState']),
      );
    }
    return DeviceSetting(
      start: at,
      end: at,
      group: _group(g['GroupId']),
      left: sides['left'],
      right: sides['right'],
    );
  }

  final runs = <DeviceSetting>[];
  for (final segment in _list(json['BrainSenseLfp']).whereType<Map>()) {
    final first = _time(segment['FirstPacketDateTime']);
    final snapshot = segment['TherapySnapshot'];
    if (first == null || snapshot is! Map) continue;
    DeviceSide? side(String key) {
      final s = snapshot[key];
      if (s is! Map) return null;
      return DeviceSide(
        rate: _num(s['RateInHertz']),
        pulseWidth: _num(s['PulseWidthInMicroSecond']),
        contacts: _contacts(s['ElectrodeState']),
      );
    }

    final left = side('Left');
    final right = side('Right');
    final group = _group(snapshot['ActiveGroup']);
    num? firstTick;
    num? previous;
    var offset = 0;
    DeviceSetting? open;
    DateTime? lastAt;
    for (final sample in _list(segment['LfpData']).whereType<Map>()) {
      final tick = _num(sample['TicksInMs']);
      if (tick == null) continue;
      if (previous != null && tick + offset < previous) {
        offset += _tickRolloverMs;
      }
      previous = tick + offset;
      firstTick ??= previous;
      final at = first.add(
        Duration(milliseconds: (previous - firstTick).round()),
      );
      double? mA(String key) {
        final s = sample[key];
        final v = s is Map ? _num(s['mA']) : null;
        return v == null ? null : (v * 100).round() / 100;
      }

      final setting = DeviceSetting(
        start: at,
        end: at,
        group: group,
        left: left?.withAmplitude(mA('Left')),
        right: right?.withAmplitude(mA('Right')),
      );
      if (open == null || !_same(open, setting)) {
        if (open != null) runs.add(open.between(open.start, at));
        open = setting;
      }
      lastAt = at;
    }
    if (open != null && lastAt != null) {
      runs.add(open.between(open.start, lastAt));
    }
  }
  runs.sort((a, b) => a.start.compareTo(b.start));

  final leadModels = <String, String>{};
  final leads = json['LeadConfiguration'];
  for (final lead in _list(leads is Map ? leads['Final'] : null)) {
    if (lead is! Map) continue;
    final side = _hemisphere(lead['Hemisphere']);
    final model = '${lead['Model'] ?? ''}'.split('.').last;
    if (side != null && model.startsWith('LEAD_')) {
      leadModels[side] = model.substring(5);
    }
  }

  return PerceptTimeline(
    sessionStart: start,
    sessionEnd: end,
    initial: group('Initial', start, 'InitialStimStatus'),
    last: group('Final', end, 'FinalStimStatus'),
    runs: runs,
    leadModels: leadModels,
    notes: notes,
  );
}

List<DeviceSetting> stableSettings(List<DeviceSetting> runs) {
  final out = <DeviceSetting>[];
  for (final run in runs) {
    if (run.held < _minHold) continue;
    final prev = out.lastOrNull;
    if (prev != null &&
        _same(prev, run) &&
        run.start.difference(prev.end) <= _maxGap) {
      out[out.length - 1] = prev.between(prev.start, run.end);
    } else {
      out.add(run);
    }
  }
  return out;
}

bool _same(DeviceSetting a, DeviceSetting b) =>
    a.group == b.group &&
    _sameSide(a.left, b.left) &&
    _sameSide(a.right, b.right);

bool _sameSide(DeviceSide? a, DeviceSide? b) => a == null || b == null
    ? a == b
    : a.rate == b.rate &&
          a.pulseWidth == b.pulseWidth &&
          a.amplitude == b.amplitude &&
          _sameContacts(a.contacts, b.contacts);

bool _sameContacts(List<Contact>? a, List<Contact>? b) => a == null || b == null
    ? a == b
    : a.length == b.length &&
          Iterable.generate(a.length).every((i) => a[i] == b[i]);

List<Object?> _list(Object? x) => x is List
    ? x
    : x is Map
    ? [x]
    : const [];

DateTime? _time(Object? s) =>
    s is String ? DateTime.tryParse(s.trim())?.toUtc() : null;

double? _num(Object? v) => v is num ? v.toDouble() : null;

String? _hemisphere(Object? v) {
  final s = '$v'.toLowerCase();
  if (s.endsWith('.left') || s == 'left') return 'left';
  if (s.endsWith('.right') || s == 'right') return 'right';
  return null;
}

String _group(Object? v) =>
    RegExp(r'GROUP_([A-D])$').firstMatch('${v ?? ''}')?.group(1) ?? '';

List<Contact>? _contacts(Object? state) {
  final out = <Contact>[];
  for (final e in _list(state).whereType<Map>()) {
    final result = '${e['ElectrodeStateResult'] ?? ''}';
    if (result.endsWith('.None')) continue;
    final cathode = result.endsWith('.Negative');
    if (!cathode && !result.endsWith('.Positive')) return null;
    out.add((
      electrode: '${e['Electrode'] ?? ''}'.split('.').last,
      cathode: cathode,
      share: _fraction(e),
    ));
  }
  return out.isEmpty ? null : out;
}

double? _fraction(Map entry) {
  for (final MapEntry(:key, :value) in entry.entries) {
    final whole = int.tryParse(
      RegExp(r'^ElectrodeFractionOf(\d+)$').firstMatch('$key')?.group(1) ?? '',
    );
    if (whole != null && whole > 0 && value is num) return value.abs() / whole;
  }
  return null;
}
