/// The desktop Save-As path of every export: what the dialog is
/// asked for, the extension, replacing an existing file, and its failures.
library;

import 'dart:io';

import 'package:dbs_annotator/ui/save_target.dart';
import 'package:dbs_annotator/ui/share_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screen_test_helpers.dart';

class _Asker {
  _Asker(this.answer);

  final bool answer;
  final asked = <String>[];

  Future<bool> call(String fileName) async {
    asked.add(fileName);
    return answer;
  }
}

String _slashes(String path) => path.replaceAll('\\', '/');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dbs_desktop_save');
    debugSaveDir = null;
    addTearDown(() {
      debugDialogConfirmsReplace = null;
      removeQuietly(dir);
    });
  });

  group('chooseSavePath', () {
    Future<String?> choose(
      ConfirmReplace confirm, {
      AvoidFile? avoid,
      String fileName = 'a_beh.tsv',
    }) => chooseSavePath(
      suggestedName: fileName,
      extension: 'tsv',
      confirmReplace: confirm,
      avoid: avoid,
    );

    test('asks the dialog for the name and a tsv type group', () async {
      final selector = useFakeFileSelector()..savePath = '${dir.path}/a.tsv';
      await choose(mustNotAsk);
      expect(selector.lastSuggestedName, 'a_beh.tsv');
      final groups = selector.lastTypeGroups!;
      expect(groups, hasLength(1));
      expect(groups.single.extensions, ['tsv']);
    });

    test('a dialog that cannot open throws', () async {
      useFakeFileSelector().failure = Exception('no dialog');
      await expectLater(
        choose(mustNotAsk),
        throwsA(isA<SaveDialogUnavailable>()),
      );
    });

    test('a dialog that confirms itself is not asked again', () async {
      debugDialogConfirmsReplace = true;
      final existing = File('${dir.path}/a_beh.tsv')..writeAsStringSync('old');
      useFakeFileSelector().savePath = existing.path;
      expect(await choose(mustNotAsk), existing.path);
      expect(existing.readAsStringSync(), 'old');
    });

    group('where the dialog does not confirm replacing', () {
      setUp(() => debugDialogConfirmsReplace = false);

      test('a new name is chosen without asking', () async {
        final path = '${dir.path}/a_beh.tsv';
        useFakeFileSelector().savePath = path;
        expect(await choose(mustNotAsk), path);
      });

      test('an existing file is asked about by name and kept on No', () async {
        final existing = File('${dir.path}/a_beh.tsv')
          ..writeAsStringSync('old');
        useFakeFileSelector().savePath = existing.path;
        final asker = _Asker(false);
        expect(await choose(asker.call), isNull);
        expect(asker.asked, ['a_beh.tsv']);
        expect(existing.readAsStringSync(), 'old');
      });

      test('an existing file is chosen on Yes', () async {
        final existing = File('${dir.path}/a_beh.tsv')
          ..writeAsStringSync('old');
        useFakeFileSelector().savePath = existing.path;
        final asker = _Asker(true);
        expect(await choose(asker.call), existing.path);
      });

      test('an avoided file is refused before any question', () async {
        final existing = File('${dir.path}/a_beh.tsv')
          ..writeAsStringSync('old');
        useFakeFileSelector().savePath = existing.path;
        await expectLater(
          choose(mustNotAsk, avoid: (path: existing.path, reason: 'same')),
          throwsA(isA<SameFileException>()),
        );
        expect(existing.readAsStringSync(), 'old');
      });
    });

    group('a name typed without the extension', () {
      test('gets .tsv', () async {
        useFakeFileSelector().savePath = '${dir.path}/typed';
        final path = await choose(mustNotAsk);
        expect(_slashes(path!), _slashes('${dir.path}/typed.tsv'));
        expect(File('${dir.path}/typed').existsSync(), isFalse);
      });

      test('keeps an upper case extension', () async {
        useFakeFileSelector().savePath = '${dir.path}/typed.TSV';
        final path = await choose(mustNotAsk);
        expect(_slashes(path!), _slashes('${dir.path}/typed.TSV'));
      });

      test(
        'asks before replacing the file it now names, on any desktop',
        () async {
          debugDialogConfirmsReplace = true;
          File('${dir.path}/typed.tsv').writeAsStringSync('old');
          useFakeFileSelector().savePath = '${dir.path}/typed';
          final asker = _Asker(false);
          expect(await choose(asker.call), isNull);
          expect(asker.asked, ['typed.tsv']);

          final yes = _Asker(true);
          expect(await choose(yes.call), isNotNull);
          expect(yes.asked, ['typed.tsv']);
        },
      );

      test('refuses the avoided file it now names, without asking', () async {
        debugDialogConfirmsReplace = true;
        final existing = File('${dir.path}/typed.tsv')
          ..writeAsStringSync('old');
        useFakeFileSelector().savePath = '${dir.path}/typed';
        await expectLater(
          choose(mustNotAsk, avoid: (path: existing.path, reason: 'same')),
          throwsA(isA<SameFileException>()),
        );
        expect(existing.readAsStringSync(), 'old');
      });
    });
  });

  group('exportFile', () {
    /// The outcome, or null while a Replace question is open.
    Future<ExportOutcome?> run(
      WidgetTester tester, {
      String filename = 'a_beh.tsv',
      AvoidFile? avoid,
    }) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final pending = exportFile(
        context,
        filename: filename,
        avoid: avoid,
        build: () async => (bytes: 'exported'.codeUnits, warning: null),
      );
      ExportOutcome? outcome;
      pending.then((value) => outcome = value);
      for (var i = 0; i < 500 && outcome == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.text('Replace $filename?').evaluate().isNotEmpty) break;
      }
      return outcome;
    }

    testWidgets('asks the dialog for the name and the file type', (
      tester,
    ) async {
      useExportCache(tester);
      final selector = useFakeFileSelector()..savePath = '${dir.path}/out.pdf';
      expect(await run(tester, filename: 'a_report.pdf'), ExportOutcome.saved);
      expect(selector.lastSuggestedName, 'a_report.pdf');
      expect(selector.lastTypeGroups!.single.extensions, ['pdf']);
      expect(File('${dir.path}/out.pdf').readAsStringSync(), 'exported');
    });

    testWidgets('a name typed without the extension gets it', (tester) async {
      useExportCache(tester);
      useFakeFileSelector().savePath = '${dir.path}/typed';
      expect(await run(tester, filename: 'a.zip'), ExportOutcome.saved);
      expect(File('${dir.path}/typed.zip').readAsStringSync(), 'exported');
      expect(File('${dir.path}/typed').existsSync(), isFalse);
    });

    testWidgets('a path that cannot be written says Not saved', (tester) async {
      useExportCache(tester);
      useFakeFileSelector().savePath = '${dir.path}/missing/a_beh.tsv';
      expect(await run(tester), ExportOutcome.notDelivered);
      expect(find.textContaining('Not saved: a_beh.tsv ('), findsOneWidget);
    });

    testWidgets('a dialog that cannot open saves under an unused name', (
      tester,
    ) async {
      final cache = useExportCache(tester);
      useFakeFileSelector().failure = Exception('no dialog');
      final taken = File('${cache.path}/a_beh.tsv')..writeAsStringSync('old');
      expect(await run(tester), ExportOutcome.saved);
      expect(taken.readAsStringSync(), 'old');
      expect(File('${cache.path}/a_beh-2.tsv').readAsStringSync(), 'exported');
    });

    testWidgets('an extension added here is checked against the avoided file', (
      tester,
    ) async {
      useExportCache(tester);
      debugDialogConfirmsReplace = true;
      final existing = File('${dir.path}/typed.tsv')..writeAsStringSync('old');
      useFakeFileSelector().savePath = '${dir.path}/typed';
      expect(
        await run(
          tester,
          avoid: (path: existing.path, reason: 'Not over the opened file.'),
        ),
        ExportOutcome.notDelivered,
      );
      expect(find.text('Not over the opened file.'), findsOneWidget);
      expect(existing.readAsStringSync(), 'old');
    });

    group('where the dialog does not confirm replacing', () {
      setUp(() => debugDialogConfirmsReplace = false);

      testWidgets('Cancel keeps the file and says Not saved', (tester) async {
        useExportCache(tester);
        final existing = File('${dir.path}/a_beh.tsv')
          ..writeAsStringSync('old');
        useFakeFileSelector().savePath = existing.path;
        expect(await run(tester), isNull);
        expect(find.text('Replace a_beh.tsv?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await pumpUntilFound(tester, find.text('Not saved: a_beh.tsv'));
        expect(existing.readAsStringSync(), 'old');
      });

      testWidgets('Replace writes the file', (tester) async {
        useExportCache(tester);
        final existing = File('${dir.path}/a_beh.tsv')
          ..writeAsStringSync('old');
        useFakeFileSelector().savePath = existing.path;
        expect(await run(tester), isNull);
        await tester.tap(find.text('Replace'));
        await tester.pump();
        await pumpUntilFound(tester, find.textContaining('Saved to '));
        expect(existing.readAsStringSync(), 'exported');
      });
    });
  });
}
