import 'dart:convert';
import 'dart:typed_data';

import 'package:dbs_annotator/ui/save_target.dart';
import 'package:dbs_annotator/ui/session_screen.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/docs/example_visits.dart';
import 'video_harness.dart';

void main() {
  initVideoBinding();

  testWidgets('reports from imported sessions', (tester) async {
    debugPickedFiles = [
      for (final e in exampleVisitTexts(root: videoRoot).entries)
        _Picked(e.key, utf8.encode(e.value)),
    ];
    await startVideo(tester, const SessionScreen());
    await tapText(tester, 'Import session files');
    await pause(tester, 2000);
    await tap(tester, find.text('PDF').at(1));
    await tapText(tester, 'Electrode configuration');
    await tapText(tester, 'Programming summary');
    await tapText(tester, 'Scale targets…');
    await pause(tester, 1500);
    await tap(tester, find.text('Cancel').last);
    await pause(tester, 1000);
    await tap(tester, find.text('Export').last);
    await pause(tester, 2500);
    await endVideo(tester);
  });
}

/// An imported file held in memory, as the picker would hand it back.
final class _Picked extends PlatformFile {
  _Picked(this.name, this.bytes);

  @override
  final String name;
  final Uint8List bytes;

  @override
  Uri get uri => Uri.file(name);
  @override
  XFile get xFile => XFile.fromData(bytes, name: name);
  @override
  int? lengthSync() => bytes.length;
  @override
  Future<int> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}
