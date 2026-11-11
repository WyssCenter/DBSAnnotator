import 'dart:io';

import 'package:dbs_annotator/core/prefs/user_prefs.dart';
import 'package:dbs_annotator/ui/save_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late String patient01;
  late String patient02;

  setUp(() {
    root = Directory.systemTemp.createTempSync('report_folder');
    patient01 = '${root.path}/derivatives/sub-01';
    patient02 = '${root.path}/derivatives/sub-02';
    Directory(patient01).createSync(recursive: true);
    Directory(patient02).createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test("a first report opens in the patient's derivatives folder", () {
    expect(
      reportFolderFor(UserPrefs(), root: root.path, subject: '02'),
      patient02,
    );
  });

  test('a folder the user chose last time is offered again', () {
    final chosen = Directory('${root.path}/clinic reports')..createSync();
    expect(
      reportFolderFor(
        UserPrefs(reportFolder: chosen.path),
        root: root.path,
        subject: '02',
      ),
      chosen.path,
    );
  });

  test("another patient's folder is not reused for this one", () {
    expect(
      reportFolderFor(
        UserPrefs(reportFolder: patient01),
        root: root.path,
        subject: '02',
      ),
      patient02,
    );
  });
}
