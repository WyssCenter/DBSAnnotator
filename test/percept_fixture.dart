Map<String, dynamic> electrode(String name, String result, {int? of64}) => {
  'Electrode': 'ElectrodeDef.$name',
  'ElectrodeStateResult': 'ElectrodeStateDef.$result',
  'ElectrodeAmplitudeInMilliAmps': 1.0,
  if (of64 != null) 'ElectrodeFractionOf64': -of64,
};

List<Map<String, dynamic>> monopolar(List<(String, int?)> cathodes) => [
  for (final (name, of64) in cathodes) electrode(name, 'Negative', of64: of64),
  electrode('Case', 'Positive'),
];

Map<String, dynamic> sensingGroup(
  String id, {
  bool active = true,
  double rate = 125,
  Map<String, dynamic>? left,
  Map<String, dynamic>? right,
}) => {
  'GroupId': 'GroupIdDef.GROUP_$id',
  'ActiveGroup': active,
  'ProgramSettings': {
    'RateInHertz': rate,
    'SensingChannel': [
      if (left != null)
        {...left, 'HemisphereLocation': 'HemisphereLocationDef.Left'},
      if (right != null)
        {...right, 'HemisphereLocation': 'HemisphereLocationDef.Right'},
    ],
  },
};

Map<String, dynamic> sensingSide({
  required List<Map<String, dynamic>> electrodes,
  double pulseWidth = 90,
  double rate = 125,
}) => {
  'RateInHertz': rate,
  'PulseWidthInMicroSecond': pulseWidth,
  'ElectrodeState': electrodes,
};

Map<String, dynamic> programGroup(
  String id, {
  bool active = true,
  double rate = 130,
  Map<String, dynamic>? left,
  Map<String, dynamic>? right,
}) => {
  'GroupId': 'GroupIdDef.GROUP_$id',
  'ActiveGroup': active,
  'ProgramSettings': {
    'RateInHertz': rate,
    if (left != null)
      'LeftHemisphere': {
        'Programs': [left],
      },
    if (right != null)
      'RightHemisphere': {
        'Programs': [right],
      },
  },
};

Map<String, dynamic> programSide({
  required double amplitude,
  required List<Map<String, dynamic>> electrodes,
  double pulseWidth = 90,
}) => {
  'AmplitudeInMilliAmps': amplitude,
  'PulseWidthInMicroSecond': pulseWidth,
  'ElectrodeState': electrodes,
};

Map<String, dynamic> snapshotSide({
  List<Map<String, dynamic>>? electrodes,
  double pulseWidth = 90,
  double rate = 125,
}) => {
  'RateInHertz': rate,
  'PulseWidthInMicroSecond': pulseWidth,
  'SensingChannel': 'SensingChannelDef.ONE_THREE_LEFT',
  'ElectrodeState': ?electrodes,
};

Map<String, dynamic> segment(
  DateTime start,
  List<(int, double?, double?)> steps, {
  required int endSeconds,
  Map<String, dynamic>? left,
  Map<String, dynamic>? right,
  String group = 'B',
  int firstTick = 1000,
}) {
  final samples = <Map<String, dynamic>>[];
  for (var ms = 0; ms <= endSeconds * 1000; ms += 500) {
    final step = steps.lastWhere((s) => s.$1 * 1000 <= ms);
    samples.add({
      'Seq': samples.length,
      'TicksInMs': (firstTick + ms) % 3276800,
      if (step.$2 != null) 'Left': {'LFP': 100, 'mA': step.$2},
      if (step.$3 != null) 'Right': {'LFP': 100, 'mA': step.$3},
    });
  }
  return {
    'Channel': 'ONE_THREE_LEFT,ONE_THREE_RIGHT',
    'FirstPacketDateTime': start.toUtc().toIso8601String(),
    'SampleRateInHz': 2,
    'TherapySnapshot': {
      'ActiveGroup': 'GroupIdDef.GROUP_$group',
      'Left': ?left,
      'Right': ?right,
    },
    'LfpData': samples,
  };
}

Map<String, dynamic> perceptJson({
  required DateTime start,
  required DateTime end,
  List<Map<String, dynamic>> initial = const [],
  List<Map<String, dynamic>> last = const [],
  List<Map<String, dynamic>> segments = const [],
  String leftLead = 'B33005',
  String rightLead = 'B33005',
  Map<String, dynamic>? stimulation,
}) => {
  'SessionDate': start.toUtc().toIso8601String(),
  'SessionEndDate': end.toUtc().toIso8601String(),
  'ProgrammerUtcOffset': '+00:00',
  'LeadConfiguration': {
    'Final': [
      {
        'Hemisphere': 'HemisphereLocationDef.Left',
        'Model': 'LeadModelDef.LEAD_$leftLead',
      },
      {
        'Hemisphere': 'HemisphereLocationDef.Right',
        'Model': 'LeadModelDef.LEAD_$rightLead',
      },
    ],
  },
  'Groups': {'Initial': initial, 'Final': last},
  'BrainSenseLfp': segments,
  'Stimulation':
      stimulation ??
      {
        'InitialStimStatus': 'StimStatusDef.ON',
        'FinalStimStatus': 'StimStatusDef.ON',
      },
};
