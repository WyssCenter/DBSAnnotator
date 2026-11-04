/// The single decision point for "does writing reach the clinician's file",
/// plus the basename helper the report provenance line depends on.
library;

import 'dart:io';

import 'package:dbs_annotator/ui/save_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pickedBasename', () {
    // Both call sites carried `path.replaceAll(r'', '/').split('/').last`,
    // where the raw string is empty: `replaceAll('', '/')` inserts a
    // separator between every character, so the last segment was always ''
    // and every report was filed with no record of its source file.
    test('is never empty for a real path (the provenance regression)', () {
      const windows = r'C:\Users\clinician\Documents\sub-01_beh.tsv';
      const posix = '/home/clinician/documents/sub-01_beh.tsv';
      for (final path in [windows, posix, 'sub-01_beh.tsv']) {
        expect(pickedBasename(path), isNotEmpty, reason: path);
        expect(pickedBasename(path), 'sub-01_beh.tsv', reason: path);
      }
    });

    test('handles a Windows path', () {
      expect(
        pickedBasename(r'C:\Users\lucia\sub-01_ses-20260909_beh.tsv'),
        'sub-01_ses-20260909_beh.tsv',
      );
    });

    test('handles a POSIX path', () {
      expect(pickedBasename('/var/mobile/Documents/notes.tsv'), 'notes.tsv');
    });

    test('handles mixed separators, as Windows itself accepts', () {
      expect(pickedBasename(r'C:\Users\lucia/Documents\x.tsv'), 'x.tsv');
    });

    test('a bare filename is returned unchanged', () {
      expect(pickedBasename('x.tsv'), 'x.tsv');
    });

    test('a trailing separator yields empty rather than throwing', () {
      // Not a case the pickers produce, but it must not throw: the value is
      // interpolated straight into a clinical document's header.
      expect(pickedBasename('/a/b/'), '');
    });
  });

  group('pickedPathAutosavesToOriginal', () {
    test('a null path never autosaves anywhere', () {
      expect(pickedPathAutosavesToOriginal(null), isFalse);
    });
  });

  group('workingPath', () {
    test('never reuses a name another session holds', () async {
      final dir = Directory.systemTemp.createTempSync('dbs_work');
      addTearDown(() => dir.deleteSync(recursive: true));
      debugWorkingDir = dir;
      addTearDown(() => debugWorkingDir = null);
      final first = await workingPath('sub-01_ses-20260203_beh.tsv');
      File(first).writeAsStringSync('rows');
      final second = await workingPath('sub-01_ses-20260203_beh.tsv');
      expect(second, isNot(first));
      expect(second, endsWith('sub-01_ses-20260203_beh-2.tsv'));
    });
  });

  group('createNewTsv', () {
    test('refuses the same file spelled another way', () async {
      final dir = Directory.systemTemp.createTempSync('dbs_same');
      addTearDown(() => dir.deleteSync(recursive: true));
      debugSaveDir = dir;
      addTearDown(() => debugSaveDir = null);
      final existing = File('${dir.path}/a_beh.tsv')..writeAsStringSync('x');
      await expectLater(
        createNewTsv(
          dialogTitle: 't',
          fileName: 'a_beh.tsv',
          header: 'h',
          avoidPath: '${dir.path}/./${existing.uri.pathSegments.last}',
        ),
        throwsA(isA<SameFileException>()),
      );
      expect(existing.readAsStringSync(), 'h');
    });
  });

  group('sandboxCopyNotice', () {
    test('says both what autosave does and what to do instead', () {
      expect(sandboxCopyNotice, contains('not'));
      expect(sandboxCopyNotice.toLowerCase(), contains('export'));
    });
  });
}
