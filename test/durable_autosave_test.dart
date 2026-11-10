/// Every inserted entry reaches disk, whatever the file picker returned.
///
/// Autosave used to write only to the path the picker gave back. On Android
/// that is a `content://` URI, so `pickerUriToPath` yields null, so the path
/// was null and autosave was a silent no-op: a whole visit was held in memory
/// and nothing said so. The working copy exists so there is always a file.
library;

import 'dart:io';

import 'package:dbs_annotator/core/session/authoring.dart';
import 'package:dbs_annotator/core/session/session_file.dart';
import 'package:dbs_annotator/core/session/tsv_kind.dart';
import 'package:dbs_annotator/ui/save_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('dbs_work');
    debugWorkingDir = root;
  });

  tearDown(() {
    debugWorkingDir = null;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('a content:// URI yields no writable path, which is the defect', () {
    expect(
      pickerUriToPath(Uri.parse('content://com.android.providers/1')),
      null,
    );
    expect(pickerUriToPath(Uri.parse('file:///tmp/sub-01_beh.tsv')), isNotNull);
  });

  test(
    'the working copy is reachable even when the picker gives nothing',
    () async {
      final path = await workingPath('sub-01_ses-20260203_beh.tsv');
      File(path).writeAsStringSync('x');
      expect(File(path).existsSync(), isTrue);
    },
  );

  test('an unexported session is offered back, newest first', () async {
    final older = File(await workingPath('sub-01_ses-20260101_beh.tsv'))
      ..writeAsStringSync('old');
    older.setLastModifiedSync(DateTime(2026, 1, 1));
    final newer = File(await workingPath('sub-02_ses-20260203_beh.tsv'))
      ..writeAsStringSync('new');
    newer.setLastModifiedSync(DateTime(2026, 2, 3));

    final left = await unfinishedWork();
    expect(left.map((f) => pickedBasename(f.path)), [
      'sub-02_ses-20260203_beh.tsv',
      'sub-01_ses-20260101_beh.tsv',
    ]);
  });

  test('a recovered session round-trips its blocks', () async {
    final authoring = SessionAuthoring();
    final path = await workingPath('sub-01_ses-20260203_beh.tsv');
    File(path).writeAsStringSync(authoring.serialize());

    final content = File(path).readAsStringSync();
    expect(sniffTsvKind(content), TsvKind.programming);
    expect(
      SessionAuthoring()..loadExisting(parseSessionTsv(content)),
      isNotNull,
    );
  });

  test('discarding removes the copy and any interrupted write', () async {
    final path = await workingPath('sub-01_ses-20260203_beh.tsv');
    File(path).writeAsStringSync('rows');
    File('$path.tmp').writeAsStringSync('half a write');

    await discardWork(path);

    expect(File(path).existsSync(), isFalse);
    expect(File('$path.tmp').existsSync(), isFalse);
    expect(await unfinishedWork(), isEmpty);
  });

  test('discarding a null path is harmless', () async {
    await discardWork(null);
    expect(await unfinishedWork(), isEmpty);
  });
}
