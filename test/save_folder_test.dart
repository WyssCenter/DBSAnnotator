import 'dart:io';

import 'package:dbs_annotator/ui/save_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;

  setUp(() => folder = Directory.systemTemp.createTempSync('save_folder'));
  tearDown(() => folder.deleteSync(recursive: true));

  test('a new session file is created in the chosen folder', () async {
    final target = await createNewTsv(
      dialogTitle: 'unused',
      fileName: 'sub-01_ses-20260203_task-programming_run-01_beh.tsv',
      header: 'acq_time\tblock_id\n',
      folder: folder.path,
    );
    expect(target!.path, startsWith(folder.path));
    expect(File(target.path!).readAsStringSync(), 'acq_time\tblock_id\n');
  });

  test('an existing session file is never overwritten', () async {
    const name = 'sub-01_ses-20260203_task-programming_run-01_beh.tsv';
    final existing = File('${folder.path}/$name')..writeAsStringSync('kept');
    await expectLater(
      createNewTsv(
        dialogTitle: 'unused',
        fileName: name,
        header: 'acq_time\n',
        folder: folder.path,
      ),
      throwsA(isA<PathExistsException>()),
    );
    expect(existing.readAsStringSync(), 'kept');
  });
}
