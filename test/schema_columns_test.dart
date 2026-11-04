import 'dart:convert';
import 'dart:io';

import 'package:dbs_annotator/core/schema_columns.dart';
import 'package:flutter_test/flutter_test.dart';

/// The TSV column contract in `schema/tsv_schema.json`, which the app bundles
/// and the docs render their column tables from.
void main() {
  test('Dart column lists match the contract', () {
    final file = File('schema/tsv_schema.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'schema/*.json is a committed contract; restore it from git.',
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    List<String> columnsOf(String key) =>
        ((json[key] as Map<String, dynamic>)['columns'] as List)
            .map((c) => (c as Map<String, dynamic>)['name'] as String)
            .toList();

    expect(annotationColumns, columnsOf('annotation_tsv'));
    expect(sessionColumns, columnsOf('session_tsv'));
  });

  test('only numeric columns declare Units', () {
    // `Units` is what makes bids-validator type a column as a number, and it
    // rejected `3.0_2.0` in left_amplitude for exactly that reason: the column
    // is declared `string` because a steered current is several values joined
    // by an underscore, so claiming a unit on it asserts a shape the data does
    // not have. The unit belongs in the description instead.
    final json = jsonDecode(
      File('schema/tsv_schema.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final block in json.values.whereType<Map<String, dynamic>>()) {
      for (final column in (block['columns'] as List? ?? [])) {
        final c = column as Map<String, dynamic>;
        if (c['units'] == null) continue;
        expect(
          c['type'],
          anyOf("float", "integer"),
          reason: '${c['name']} declares Units but is ${c['type']}',
        );
      }
    }
  });
}
