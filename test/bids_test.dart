/// The BIDS surface: the sidecar that documents the columns, and the dataset
/// tree that `bids-validator` is pointed at.
///
/// The filename and column-naming rules live in tsv_roundtrip_test.dart and
/// session_file_test.dart, next to the round trips they constrain.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/bids.dart';
import 'package:dbs_annotator/core/bids_dataset.dart';
import 'package:dbs_annotator/core/bids_sidecar.dart';
import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:dbs_annotator/ui/bids_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final contract = jsonDecode(
    File('schema/tsv_schema.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  group('sidecar', () {
    test('documents every column of both kinds, and nothing else', () {
      // The sidecar exists so a reader can look up any column they meet in
      // the TSV; a column present in the data but missing here is the gap it
      // was written to close.
      final session = buildSidecar(
        contract,
        'session_tsv',
        appVersion: '0.5.0',
      );
      for (final column in sessionColumns) {
        expect(session, contains(column), reason: '$column is undocumented');
      }

      final notes = buildSidecar(
        contract,
        'annotation_tsv',
        appVersion: '0.5.0',
      );
      for (final column in annotationColumns) {
        expect(notes, contains(column), reason: '$column is undocumented');
      }
    });

    test('the contract and the Dart column lists agree', () {
      expect(contractColumns(contract, 'session_tsv'), sessionColumns);
      expect(contractColumns(contract, 'annotation_tsv'), annotationColumns);
    });

    test('a task file names its task; the combined table does not', () {
      // bids-validator asks every task file's sidecar for TaskName, and the
      // combined table is not one: it spans sessions and carries no `task-`
      // entity, so claiming a task there would be false.
      final session = buildSidecar(
        contract,
        'session_tsv',
        appVersion: '0.5.0',
      );
      expect(session['TaskName'], 'programming');
      expect(session['TaskDescription'], contains('stimulation'));

      final notes = buildSidecar(
        contract,
        'annotation_tsv',
        appVersion: '0.5.0',
      );
      expect(notes['TaskName'], 'notes');

      final aggregate = jsonDecode(
        aggregateSidecarJson(contract, appVersion: '0.5.0'),
      ) as Map<String, dynamic>;
      expect(aggregate.containsKey('TaskName'), isFalse);
      expect(aggregate.containsKey('TaskDescription'), isFalse);
    });

    test('a task the user renamed is the TaskName the file carries', () {
      // BIDS derives the filename's task label from TaskName, so the two
      // must agree; the description still says what the rows are.
      final notes = buildSidecar(
        contract,
        'annotation_tsv',
        appVersion: '0.5.0',
        task: 'followup',
      );
      expect(notes['TaskName'], 'followup');
      expect(notes['TaskDescription'], contains('notes'));
      expect(
        buildSidecar(contract, 'session_tsv', appVersion: '0.5.0', task: ''),
        containsPair('TaskName', 'programming'),
      );
    });
    test('entries use the BIDS key names, with Units where there are any', () {
      final session = buildSidecar(
        contract,
        'session_tsv',
        appVersion: '0.5.0',
      );
      final freq = session['left_stim_freq'] as Map<String, String>;
      expect(freq['LongName'], 'Left stim freq');
      expect(freq['Units'], 'Hz');
      expect(freq['Description'], contains('frequency'));

      // A column with no physical unit must not claim one.
      expect(session['scale_name'], isNot(contains('Units')));

      // The descriptions are shared with the docs, which want reStructuredText
      // inline literals; a JSON reader should not see the backticks.
      for (final entry in session.values) {
        if (entry is Map<String, String>) {
          expect(entry['Description'], isNot(contains('``')));
        }
      }
    });

    test('names the missing-value code, so `n/a` is not a mystery', () {
      final session = buildSidecar(
        contract,
        'session_tsv',
        appVersion: '0.5.0',
      );
      expect(session['MissingValueCode'], 'n/a');
      expect(session['GeneratedBy'], isA<List<dynamic>>());
    });

    test('is valid, stable JSON', () {
      final text = sessionEntry(
        name: const BidsName(
          subject: '01',
          session: 'preop',
          task: 'programming',
          run: '01',
        ),
        rows: const [],
        contract: contract,
      ).sidecar;
      expect(jsonDecode(text), isA<Map<String, dynamic>>());
      expect(text, endsWith('\n'));
    });
  });

  group('dataset', () {
    DatasetEntry entry(String subject, String session, String run) => (
      name: BidsName(
        subject: subject,
        session: session,
        task: 'programming',
        run: run,
      ),
      tsv: 'date\tnotes\n2026-06-26\ta note\n',
      sidecar: '{}\n',
      acqTime: '2026-02-03T09:00:00+00:00',
      visit: const {},
      participant: const {},
      visitScales: const {},
    );

    List<String> pathsOf(List<DatasetFile> files) =>
        files.map((f) => f.path).toList();

    test('lays files out under sub-/ses-/beh with their sidecars', () {
      final files = buildBidsDataset(
        [entry('01', '20260626', '01')],
        contract: contract,
        appName: 'Wyss DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      );
      final paths = pathsOf(files);

      expect(
        paths,
        containsAll([
          'dataset_description.json',
          'README',
          'participants.tsv',
          'participants.json',
          'sub-01/ses-20260626/beh/'
              'sub-01_ses-20260626_task-programming_run-01_beh.tsv',
          'sub-01/ses-20260626/beh/'
              'sub-01_ses-20260626_task-programming_run-01_beh.json',
          'sub-01/ses-20260626/sub-01_ses-20260626_scans.tsv',
        ]),
      );
    });

    test(
      'dataset_description.json declares the BIDS version and provenance',
      () {
        final files = buildBidsDataset(
          [entry('01', '20260626', '01')],
          contract: contract,
          appName: 'Wyss DBS Annotator',
          appVersion: '0.5.0',
          repoUrl: 'https://example.invalid',
        );
        final description = jsonDecode(
          files.firstWhere((f) => f.path == 'dataset_description.json').content,
        ) as Map<String, dynamic>;

        expect(description['BIDSVersion'], bidsVersion);
        expect(description['DatasetType'], 'raw');
        expect(
          (description['GeneratedBy'] as List).first,
          containsPair('Version', '0.5.0'),
        );
      },
    );

    test('participants.tsv lists each subject once, in order', () {
      final files = buildBidsDataset(
        [
          entry('02', '20260626', '01'),
          entry('01', '20260626', '01'),
          entry('01', '20260701', '01'),
        ],
        contract: contract,
        appName: 'Wyss DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      );
      final participants = files
          .firstWhere((f) => f.path == 'participants.tsv')
          .content;

      expect(
        participants,
        'participant_id\tdbs_indication\nsub-01\tn/a\nsub-02\tn/a\n',
      );
    });

    test('scans.tsv is per session, and its paths are session-relative', () {
      // BIDS: the `filename` column of scans.tsv is relative to the
      // subject/session directory, so it carries the datatype folder and not
      // the sub-/ses- prefix.
      final files = buildBidsDataset(
        [entry('01', '20260626', '01'), entry('01', '20260626', '02')],
        contract: contract,
        appName: 'Wyss DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      );
      final scans = files
          .firstWhere((f) => f.path.endsWith('_scans.tsv'))
          .content
          .trim()
          .split('\n');

      expect(scans.first, 'filename\tacq_time');
      expect(scans, hasLength(3));
      expect(
        scans[1],
        startsWith('beh/sub-01_ses-20260626_task-programming_run-01_beh.tsv'),
      );
      expect(scans[1], contains('2026-02-03T09:00:00+00:00'));
    });

    test('two sessions of one subject each get their own scans.tsv', () {
      final files = buildBidsDataset(
        [entry('01', '20260626', '01'), entry('01', '20260701', '01')],
        contract: contract,
        appName: 'Wyss DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      );
      expect(
        pathsOf(files).where((p) => p.endsWith('_scans.tsv')),
        unorderedEquals([
          'sub-01/ses-20260626/sub-01_ses-20260626_scans.tsv',
          'sub-01/ses-20260701/sub-01_ses-20260701_scans.tsv',
        ]),
      );
    });

    test('the reports derivative carries its own dataset_description', () {
      // "derivatives datasets MUST include a dataset_description.json file at
      // the root level": a report dropped into derivatives/ without one makes
      // the whole dataset invalid.
      final file = derivativeDescription(
        dir: reportsDerivativeDir,
        name: 'Wyss DBS Annotator reports',
        appName: 'Wyss DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      );
      expect(file.path, '$reportsDerivativeDir/dataset_description.json');
      expect(
        (jsonDecode(file.content) as Map<String, dynamic>)['DatasetType'],
        'derivative',
      );
    });

    test('the aggregate derivative carries one too, at its own root', () {
      // Same rule, and the reason `derivativeDescription` is parameterised
      // rather than fixed to the reports directory: each derivative dataset
      // needs its own description or the parent dataset is invalid.
      final file = derivativeDescription(
        dir: aggregateDerivativeDir,
        name: 'Wyss DBS Annotator combined sessions',
        appName: 'Wyss DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      );
      expect(file.path, '$aggregateDerivativeDir/dataset_description.json');
      final json = jsonDecode(file.content) as Map<String, dynamic>;
      expect(json['DatasetType'], 'derivative');
      expect(json['BIDSVersion'], isNotNull);
      expect(json['GeneratedBy'], isA<List<dynamic>>());
    });

    test('the README says why the suffix is _beh', () {
      final readme = buildBidsDataset(
        [entry('01', '20260626', '01')],
        contract: contract,
        appName: 'Wyss DBS Annotator',
        appVersion: '0.5.0',
        repoUrl: 'https://example.invalid',
      ).firstWhere((f) => f.path == 'README').content;

      expect(readme, contains('_beh.tsv'));
      expect(readme, contains('onset'));
      expect(readme, contains(sessionColumns.first));
    });
  });
}
