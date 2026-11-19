import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/report/report_data.dart';
import 'package:dbs_annotator/report/session_docx.dart';
import 'package:dbs_annotator/report/session_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const stim = {
    'left_stim_freq': '125',
    'left_anode': 'case',
    'left_cathode': 'E1',
    'left_amplitude': '2',
    'left_pulse_width': '90',
  };

  SessionReportData report(String fromDevice) => buildSessionReportData(
    rows:
        (SessionAuthoring()..addInsert(
              isInitial: false,
              stim: stim,
              programId: 'B',
              fromDevice: fromDevice,
              at: DateTime.utc(2026, 2, 3, 9),
            ))
            .rows,
  );

  String cell(SessionReportData data, String header) =>
      data.tableData.first[sessionTableHeaders.indexOf(header)];

  String docx(SessionReportData data) => utf8.decode(
    ZipDecoder()
        .decodeBytes(buildSessionDocx(data: data, subjectId: '01'))
        .findFile('word/document.xml')!
        .readBytes()!,
  );

  test('a mix marks each value that came from the device', () {
    final data = report('left_amplitude left_pulse_width');
    expect(cell(data, 'Amp (mA)'), '2$kDeviceMark');
    expect(cell(data, 'PW (µs)'), '90$kDeviceMark');
    expect(cell(data, 'Freq (Hz)'), '125');
    expect(cell(data, '-'), '1');
    expect(cell(data, 'Group'), 'B');
    expect(
      data.lastConfig['Left'],
      '1- / case+ = 2 mA$kDeviceMark, 125 Hz, 90 µs$kDeviceMark',
    );
    expect(data.hasDeviceValues, isTrue);
  });

  test('a line read entirely from the device carries one mark', () {
    final data = report(
      'program_id left_stim_freq left_anode left_cathode left_amplitude '
      'left_pulse_width',
    );
    expect(
      data.lastConfig['Left'],
      '1- / case+ = 2 mA, 125 Hz, 90 µs$kDeviceMark',
    );
    expect(data.lastConfig['Group'], 'B$kDeviceMark');
    expect(cell(data, 'Group'), 'B$kDeviceMark');
    expect(cell(data, '+'), 'case$kDeviceMark');
  });

  test(
    'both formats print the legend, and only when something is marked',
    () async {
      final marked = report('left_amplitude');
      expect(docx(marked), contains(kDeviceLegend));
      final pdf = await buildSessionPdf(data: marked, subjectId: '01');
      expect(pdf.bytes.sublist(0, 4), '%PDF'.codeUnits);
      expect(pdf.lostCharacters, isFalse);

      final entered = report('');
      expect(entered.hasDeviceValues, isFalse);
      expect(docx(entered), isNot(contains(kDeviceLegend)));
      expect(
        [
          ...entered.tableData.expand((r) => r),
          ...entered.lastConfig.values,
        ].any((t) => t.contains(kDeviceMark)),
        isFalse,
      );
    },
  );
}
